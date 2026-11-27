import { Hono } from "hono";
import type { App } from "./types";
import { bad, forbidden, notFound } from "../lib/util";
import { isAdmin } from "../lib/auth";
import { chainInfo } from "../lib/chain";
import { requirePasskeyIfEnrolled } from "../lib/passkeys";
import {
  cancelUnpaid, confirmDelivery, createOrder, getOrder, inspectionResult, startCardPayment, startUsdcPayment, startWalletPayment, withdraw, type Order, type WithdrawInput,
} from "../lib/orders";

export const orders = new Hono<App>();

async function detail(c: { env: App["Bindings"] }, o: Order) {
  const { results: items } = await c.env.DB.prepare("SELECT product_id,name,unit_cents,qty FROM order_items WHERE order_id=?").bind(o.id).all();
  const { results: events } = await c.env.DB.prepare("SELECT type,note,created_at FROM order_events WHERE order_id=? ORDER BY created_at, rowid").bind(o.id).all();
  const store = await c.env.DB.prepare("SELECT slug,name,logo_key,verified FROM stores WHERE id=?").bind(o.store_id).first();
  const buyer = await c.env.DB.prepare("SELECT name FROM users WHERE id=?").bind(o.buyer_id).first<{ name: string }>();
  let pool = null;
  if (o.pool_id) {
    pool = await c.env.DB.prepare(
      `SELECT pl.target_qty, pl.ends_at,
        COALESCE((SELECT SUM(oi.qty) FROM orders x JOIN order_items oi ON oi.order_id=x.id WHERE x.pool_id=pl.id AND x.status NOT IN ('cancelled','refunded')),0) AS joined_qty
       FROM pools pl WHERE pl.id=?`).bind(o.pool_id).first();
  }
  return { ...o, proof_keys: JSON.parse(o.proof_keys), items, events, store, buyerName: buyer?.name ?? "", pool, chain: await chainInfo(c.env, o) };
}

async function load(c: { env: App["Bindings"]; get: (k: "user") => App["Variables"]["user"]; req: { param: (k: string) => string } }, who: "buyer" | "any" = "buyer") {
  const o = await getOrder(c.env, c.req.param("id"));
  if (!o) throw notFound("Order not found");
  const u = c.get("user");
  if (who === "buyer" && o.buyer_id !== u.id) throw forbidden();
  if (who === "any" && o.buyer_id !== u.id && o.vendor_id !== u.id && !isAdmin(c.env, u)) throw forbidden();
  return o;
}

orders.post("/", async (c) => {
  const b = await c.req.json<{ storeId: string; items: { productId: string; qty: number }[]; poolId?: string }>();
  const o = await createOrder(c.env, c.get("user").id, b);
  return c.json({ order: await detail(c, o) }, 201);
});

orders.get("/", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT o.id,o.ref,o.status,o.total_cents,o.created_at,o.pool_id, s.name AS store_name, s.logo_key,
       (SELECT GROUP_CONCAT(oi.qty || '× ' || oi.name, ', ') FROM order_items oi WHERE oi.order_id=o.id) AS summary
     FROM orders o JOIN stores s ON s.id=o.store_id WHERE o.buyer_id=? ORDER BY o.created_at DESC LIMIT 100`,
  ).bind(c.get("user").id).all();
  return c.json({ orders: results });
});

orders.get("/:id", async (c) => c.json({ order: await detail(c, await load(c, "any")) }));

orders.post("/:id/pay", async (c) => {
  const o = await load(c);
  const { method } = await c.req.json<{ method: "card" | "usdc" | "wallet" }>();
  const u = c.get("user");
  await requirePasskeyIfEnrolled(c.env, u.id, c.req.header("X-Passkey-Token"), `pay:${o.id}`);
  if (method === "usdc") return c.json(await startUsdcPayment(c.env, o, u));
  if (method === "wallet") return c.json(await startWalletPayment(c.env, o, u.id, u.country));
  if (method === "card") return c.json(await startCardPayment(c.env, o, u.email, u.country));
  throw bad("method must be card, usdc or wallet");
});

orders.post("/:id/cancel", async (c) => { await cancelUnpaid(c.env, await load(c)); return c.json({ ok: true }); });
orders.post("/:id/confirm-delivery", async (c) => { await confirmDelivery(c.env, await load(c)); return c.json({ ok: true }); });

/** Buyer may approve small orders themselves; large ones need a Kontena inspector. */
orders.post("/:id/inspection", async (c) => {
  const o = await load(c, "any");
  const u = c.get("user");
  const b = await c.req.json<{ pass: boolean; note?: string }>();
  const max = Number(c.env.INSPECTION_BUYER_MAX_CENTS ?? 100_000);
  const allowed = isAdmin(c.env, u) || (o.buyer_id === u.id && o.total_cents <= max);
  if (!allowed) throw forbidden("This order needs a Kontena inspector");
  if (!isAdmin(c.env, u)) await requirePasskeyIfEnrolled(c.env, u.id, c.req.header("X-Passkey-Token"), `inspection:${o.id}`);
  await inspectionResult(c.env, o, !!b.pass, b.note ?? "");
  return c.json({ ok: true });
});

orders.get("/admin/queue", async (c) => {
  if (!isAdmin(c.env, c.get("user"))) throw forbidden();
  const { results } = await c.env.DB.prepare("SELECT id,ref,total_cents,balance_cents,created_at FROM orders WHERE status='inspection' ORDER BY updated_at").all();
  return c.json({ orders: results });
});

// ---------- group buys ----------

orders.post("/join-pool", async (c) => {
  const b = await c.req.json<{ poolId: string; qty: number }>();
  const pool = await c.env.DB.prepare("SELECT * FROM pools WHERE id=? AND status='open' AND ends_at>unixepoch()").bind(b.poolId)
    .first<{ id: string; product_id: string; store_id: string }>();
  if (!pool) throw notFound("This group order has closed");
  const o = await createOrder(c.env, c.get("user").id, { storeId: pool.store_id, items: [{ productId: pool.product_id, qty: b.qty }], poolId: pool.id });
  return c.json({ order: await detail(c, o) }, 201);
});

// ---------- withdrawals (vendor wallet) ----------

export const withdrawals = new Hono<App>();
withdrawals.post("/", async (c) => {
  await requirePasskeyIfEnrolled(c.env, c.get("user").id, c.req.header("X-Passkey-Token"), "withdraw");
  const b = await c.req.json<{ method: "usdc" | "fiat"; amountUsd: number; address?: string; memo?: string; payoutAccountId?: string }>();
  const cents = Math.round((b.amountUsd ?? 0) * 100);
  let input: WithdrawInput;
  if (b.method === "usdc") {
    if (!b.address || !/^G[A-Z2-7]{55}$/.test(b.address)) throw bad("Enter a valid Stellar address (starts with G)");
    input = { method: "usdc", amountCents: cents, address: b.address, memo: b.memo };
  } else if (b.method === "fiat") {
    if (!b.payoutAccountId) throw bad("Choose a payout account");
    input = { method: "fiat", amountCents: cents, payoutAccountId: b.payoutAccountId };
  } else throw bad("Unknown method");
  return c.json(await withdraw(c.env, c.get("user").id, input));
});
