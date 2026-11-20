import { Hono } from "hono";
import type { App } from "./types";
import { hmacHex, now, safeEqual } from "../lib/util";
import { finishWithdrawal, markFunded } from "../lib/orders";
import type { Env } from "../lib/env";

export const webhooks = new Hono<App>();

async function once(env: Env, source: string, id: string): Promise<boolean> {
  const r = await env.DB.prepare("INSERT OR IGNORE INTO webhook_events (id,source,created_at) VALUES (?,?,?)").bind(`${source}:${id}`, source, now()).run();
  return (r.meta.changes ?? 0) > 0;
}

// Paystack: signature is HMAC-SHA512 of the raw body with your secret key.
webhooks.post("/paystack", async (c) => {
  const raw = await c.req.text();
  const sig = c.req.header("x-paystack-signature") ?? "";
  if (!safeEqual(sig, await hmacHex("SHA-512", c.env.PAYSTACK_SECRET_KEY, raw))) return c.text("bad signature", 401);
  const ev = JSON.parse(raw) as { event: string; data: { id?: number; reference: string; amount?: number; currency?: string; metadata?: { orderId?: string } } };
  if (!(await once(c.env, "paystack", `${ev.event}:${ev.data.id ?? ev.data.reference}`))) return c.text("ok");

  if (ev.event === "charge.success") {
    const o = await c.env.DB.prepare("SELECT id,pay_amount_minor,pay_currency FROM orders WHERE paystack_ref=?").bind(ev.data.reference)
      .first<{ id: string; pay_amount_minor: number; pay_currency: string }>();
    // never trust the webhook alone: amount and currency must match what we asked for
    if (o && ev.data.amount! >= o.pay_amount_minor && ev.data.currency === o.pay_currency) await markFunded(c.env, o.id, "card/bank");
  } else if (ev.event === "transfer.success") {
    await finishWithdrawal(c.env, ev.data.reference, true);
  } else if (ev.event === "transfer.failed" || ev.event === "transfer.reversed") {
    await finishWithdrawal(c.env, ev.data.reference, false, ev.event);
  }
  return c.text("ok");
});

// FossaPay: HMAC-SHA256 hex of JSON.stringify(body.data), header x-fossapay-signature.
webhooks.post("/fossapay", async (c) => {
  const body = (await c.req.json()) as { eventId: string; eventType: string; data: Record<string, any> };
  const sig = (c.req.header("x-fossapay-signature") ?? "").toLowerCase();
  if (!sig || !safeEqual(sig, await hmacHex("SHA-256", c.env.FOSSAPAY_WEBHOOK_SECRET, JSON.stringify(body.data)))) return c.text("bad signature", 401);
  if (!(await once(c.env, "fossapay", body.eventId))) return c.text("ok");

  const d = body.data;
  // A USDC payment from a buyer to our treasury has completed on-chain.
  if (body.eventType === "transfer.completed" && d.recipient?.address === c.env.PLATFORM_STELLAR_ADDRESS && String(d.currency).toLowerCase() === "usdc") {
    const sender = d.sender?.address as string | undefined;
    const paid = Math.round(Number(d.amount) * 100);
    const { results } = await c.env.DB.prepare(
      `SELECT o.id, o.total_cents FROM orders o JOIN users u ON u.id=o.buyer_id
       WHERE o.status='awaiting_payment' AND o.funding='usdc' AND u.stellar_address=? ORDER BY o.created_at`,
    ).bind(sender ?? "").all<{ id: string; total_cents: number }>();
    // FossaPay takes its fee out of the gross amount, so accept anything within the fee buffer
    const match = results.find((o) => paid >= o.total_cents - 10) ?? (d.reference ? results[0] : undefined);
    if (match) await markFunded(c.env, match.id, "USDC");
  }
  if (body.eventType === "deposit.completed" && d.blockchain && String(d.currency).toLowerCase() === "usdc" && d.customerId) {
    const u = await c.env.DB.prepare("SELECT id FROM users WHERE fossa_customer_id=?").bind(d.customerId).first<{ id: string }>();
    if (u) {
      const { notify } = await import("../lib/fcm");
      await notify(c.env, u.id, "USDC received", `$${Number(d.amount).toFixed(2)} arrived in your Kontena wallet.`);
    }
  }
  return c.text("ok");
});
