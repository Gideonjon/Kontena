import { Hono } from "hono";
import type { App } from "./types";
import { isAdmin } from "../lib/auth";
import { bad, forbidden, notFound } from "../lib/util";
import { finishWithdrawal } from "../lib/orders";

export const admin = new Hono<App>();

admin.use("*", async (c, next) => {
  if (!isAdmin(c.env, c.get("user"))) throw forbidden("Admins only");
  await next();
});

const DAY = 86400;

admin.get("/summary", async (c) => {
  const db = c.env.DB;
  const since = Math.floor(Date.now() / 1000) - 30 * DAY;
  const one = async <T>(sql: string, ...a: unknown[]) => (await db.prepare(sql).bind(...a).first<T>())!;

  const rev = await db.prepare("SELECT kind, COALESCE(SUM(amount_cents),0) AS s FROM platform_revenue GROUP BY kind").all<{ kind: string; s: number }>();
  const byKind: Record<string, number> = {};
  for (const r of rev.results) byKind[r.kind] = r.s;
  const total = Object.values(byKind).reduce((a, b) => a + b, 0);
  const r30 = await one<{ s: number }>("SELECT COALESCE(SUM(amount_cents),0) AS s FROM platform_revenue WHERE created_at>=?", since);

  const st = await db.prepare("SELECT status, COUNT(*) AS n FROM orders GROUP BY status").all<{ status: string; n: number }>();
  const statuses: Record<string, number> = {};
  for (const r of st.results) statuses[r.status] = r.n;

  const gmv = await one<{ s: number }>("SELECT COALESCE(SUM(subtotal_cents),0) AS s FROM orders WHERE status IN ('accepted','inspection','shipped','delivered')");
  // money currently held for buyers: whole total while funded, only the locked balance once the deposit is out
  const held = await one<{ s: number }>("SELECT COALESCE(SUM(CASE status WHEN 'funded' THEN total_cents ELSE balance_cents END),0) AS s FROM orders WHERE status IN ('funded','accepted','inspection')");
  const owed = await one<{ s: number }>("SELECT COALESCE(SUM(amount_cents),0) AS s FROM ledger");
  const pendingW = await one<{ n: number }>("SELECT COUNT(*) AS n FROM withdrawals WHERE status IN ('pending','processing')");
  const refundIssues = await one<{ n: number }>("SELECT COUNT(DISTINCT order_id) AS n FROM order_events WHERE type='refund_failed'");
  const users = await one<{ n: number }>("SELECT COUNT(*) AS n FROM users");
  const stores = await one<{ n: number }>("SELECT COUNT(*) AS n FROM stores");

  return c.json({
    revenue: { totalCents: total, last30Cents: r30.s, byKind },
    gmvCents: gmv.s, escrowHeldCents: held.s, owedToSuppliersCents: owed.s,
    orders: statuses, pendingWithdrawals: pendingW.n, refundIssues: refundIssues.n, users: users.n, stores: stores.n,
  });
});

admin.get("/orders", async (c) => {
  const status = c.req.query("status");
  const { results } = await c.env.DB.prepare(
    `SELECT o.id,o.ref,o.status,o.total_cents,o.balance_cents,o.created_at,o.updated_at, s.name AS store_name, u.name AS buyer_name,
       (SELECT GROUP_CONCAT(oi.qty || '× ' || oi.name, ', ') FROM order_items oi WHERE oi.order_id=o.id) AS summary
     FROM orders o JOIN stores s ON s.id=o.store_id JOIN users u ON u.id=o.buyer_id
     ${status ? "WHERE o.status=?" : ""} ORDER BY o.updated_at DESC LIMIT 100`,
  ).bind(...(status ? [status] : [])).all();
  return c.json({ orders: results });
});

admin.get("/refund-issues", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT o.id,o.ref,o.status,o.total_cents,o.funding,e.note,e.created_at FROM order_events e JOIN orders o ON o.id=e.order_id
     WHERE e.type='refund_failed' ORDER BY e.created_at DESC LIMIT 50`,
  ).all();
  return c.json({ issues: results });
});

admin.get("/withdrawals", async (c) => {
  const status = c.req.query("status") ?? "pending";
  const { results } = await c.env.DB.prepare(
    `SELECT w.id,w.method,w.amount_cents,w.fiat_currency,w.fiat_minor,w.status,w.provider_ref,w.error,w.dest_json,w.created_at, u.name AS user_name, u.email,
       pa.bank_name, pa.account_number, pa.account_name
     FROM withdrawals w JOIN users u ON u.id=w.user_id
     LEFT JOIN payout_accounts pa ON pa.id=json_extract(w.dest_json,'$.accountId')
     WHERE w.status=? ORDER BY w.created_at DESC LIMIT 100`,
  ).bind(status).all();
  return c.json({ withdrawals: results });
});

admin.post("/withdrawals/:id/complete", async (c) => { await finishWithdrawal(c.env, c.req.param("id"), true); return c.json({ ok: true }); });
admin.post("/withdrawals/:id/fail", async (c) => {
  const { note } = await c.req.json<{ note?: string }>().catch(() => ({ note: "" }));
  await finishWithdrawal(c.env, c.req.param("id"), false, note || "Rejected by Kontena");
  return c.json({ ok: true });
});

admin.get("/stores", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT s.id,s.slug,s.name,s.country,s.city,s.verified,s.active,s.logo_key,u.email,
       (SELECT COUNT(*) FROM orders o WHERE o.store_id=s.id AND o.status IN ('accepted','inspection','shipped','delivered')) AS orders
     FROM stores s JOIN users u ON u.id=s.owner_id ORDER BY s.created_at DESC LIMIT 100`,
  ).all();
  return c.json({ stores: results });
});

admin.post("/stores/:id/verify", async (c) => {
  const { verified } = await c.req.json<{ verified: boolean }>();
  const r = await c.env.DB.prepare("UPDATE stores SET verified=? WHERE id=?").bind(verified ? 1 : 0, c.req.param("id")).run();
  if (!(r.meta.changes ?? 0)) throw notFound();
  return c.json({ ok: true });
});

admin.post("/stores/:id/active", async (c) => {
  const { active } = await c.req.json<{ active: boolean }>();
  if (typeof active !== "boolean") throw bad("active must be true or false");
  await c.env.DB.prepare("UPDATE stores SET active=? WHERE id=?").bind(active ? 1 : 0, c.req.param("id")).run();
  return c.json({ ok: true });
});
