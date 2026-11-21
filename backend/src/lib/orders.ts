import type { Env } from "./env";
import { currencyFor, HttpError, now, pct, uid, bad, hmacHex, usdToMinor, fxRate } from "./util";
import { notify } from "./fcm";
import * as paystack from "./paystack";
import * as fossa from "./fossapay";
import * as yc from "./yellowcard";

export type Order = {
  id: string; ref: string; store_id: string; buyer_id: string; vendor_id: string; pool_id: string | null; status: string;
  subtotal_cents: number; fee_cents: number; total_cents: number; deposit_cents: number; balance_cents: number;
  funding: string | null; pay_currency: string | null; pay_amount_minor: number | null; paystack_ref: string | null; fossa_ref: string | null;
  accept_by: number; ship_by: number | null; lead_days: number; proof_keys: string; created_at: number; updated_at: number;
};

const DAY = 86400;
const money = (c: number) => `$${(c / 100).toLocaleString("en-US", { minimumFractionDigits: 2 })}`;

export async function addEvent(env: Env, orderId: string, type: string, note = "") {
  await env.DB.prepare("INSERT INTO order_events (id,order_id,type,note,created_at) VALUES (?,?,?,?,?)").bind(uid(), orderId, type, note, now()).run();
}

export const getOrder = (env: Env, id: string) => env.DB.prepare("SELECT * FROM orders WHERE id=?").bind(id).first<Order>();

/** Atomically moves an order between states. Returns false if someone else got there first. */
async function transition(env: Env, id: string, from: string | string[], to: string, extra = ""): Promise<boolean> {
  const froms = Array.isArray(from) ? from : [from];
  const r = await env.DB.prepare(
    `UPDATE orders SET status=?, updated_at=?${extra} WHERE id=? AND status IN (${froms.map(() => "?").join(",")})`,
  ).bind(to, now(), id, ...froms).run();
  return (r.meta.changes ?? 0) > 0;
}

async function credit(env: Env, userId: string, orderId: string, kind: string, cents: number): Promise<void> {
  try {
    await env.DB.prepare("INSERT INTO ledger (id,user_id,order_id,kind,amount_cents,created_at) VALUES (?,?,?,?,?,?)")
      .bind(uid(), userId, orderId, kind, cents, now()).run();
  } catch (e) {
    if (!String(e).includes("UNIQUE")) throw e; // already credited: safe no-op
  }
}

async function revenue(env: Env, kind: string, cents: number, ids: { orderId?: string; withdrawalId?: string }) {
  if (!cents) return;
  try {
    await env.DB.prepare("INSERT INTO platform_revenue (id,order_id,withdrawal_id,kind,amount_cents,created_at) VALUES (?,?,?,?,?,?)")
      .bind(uid(), ids.orderId ?? null, ids.withdrawalId ?? null, kind, cents, now()).run();
  } catch (e) {
    if (!String(e).includes("UNIQUE")) throw e;
  }
}

// ---------- creating an order ----------

export async function createOrder(env: Env, buyerId: string, a: { storeId: string; items: { productId: string; qty: number }[]; poolId?: string }) {
  if (!a.items.length) throw bad("Cart is empty");
  const store = await env.DB.prepare("SELECT * FROM stores WHERE id=? AND active=1").bind(a.storeId).first<{ id: string; owner_id: string; name: string }>();
  if (!store) throw new HttpError(404, "Store not found");
  if (store.owner_id === buyerId) throw bad("You can't buy from your own store");
  const lines: { productId: string; name: string; unit: number; qty: number; lead: number }[] = [];
  for (const it of a.items) {
    const p = await env.DB.prepare("SELECT * FROM products WHERE id=? AND store_id=? AND active=1").bind(it.productId, store.id)
      .first<{ id: string; name: string; price_cents: number; min_qty: number; lead_days: number }>();
    if (!p) throw bad("Product unavailable");
    if (!Number.isInteger(it.qty) || it.qty < p.min_qty) throw bad(`Minimum order for ${p.name} is ${p.min_qty}`);
    lines.push({ productId: p.id, name: p.name, unit: p.price_cents, qty: it.qty, lead: p.lead_days });
  }
  const subtotal = lines.reduce((s, l) => s + l.unit * l.qty, 0);
  const fee = pct(subtotal, Number(env.PLATFORM_FEE_PERCENT));
  const deposit = pct(subtotal, Number(env.DEPOSIT_PERCENT));
  const id = uid();
  const { orderRef } = await import("./util");
  const ref = orderRef();
  const t = now();
  const lead = Math.max(...lines.map((l) => l.lead));
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO orders (id,ref,store_id,buyer_id,vendor_id,pool_id,status,subtotal_cents,fee_cents,total_cents,deposit_cents,balance_cents,accept_by,lead_days,created_at,updated_at)
      VALUES (?,?,?,?,?,?, 'awaiting_payment', ?,?,?,?,?, ?,?,?,?)`)
      .bind(id, ref, store.id, buyerId, store.owner_id, a.poolId ?? null, subtotal, fee, subtotal + fee, deposit, subtotal - deposit, t + 3 * DAY, lead, t, t),
    ...lines.map((l) => env.DB.prepare("INSERT INTO order_items (id,order_id,product_id,name,unit_cents,qty) VALUES (?,?,?,?,?,?)").bind(uid(), id, l.productId, l.name, l.unit, l.qty)),
  ]);
  await addEvent(env, id, "created", "Order created");
  return (await getOrder(env, id))!;
}

// ---------- paying ----------

export async function startCardPayment(env: Env, o: Order, email: string, country: string) {
  if (o.status !== "awaiting_payment") throw bad("Order is not awaiting payment");
  const currency = currencyFor(country);
  const minor = usdToMinor(env, o.total_cents, currency);
  const reference = `${o.ref}-${Date.now().toString(36)}`;
  await env.DB.prepare("UPDATE orders SET funding='paystack', pay_currency=?, pay_amount_minor=?, paystack_ref=?, updated_at=? WHERE id=?")
    .bind(currency, minor, reference, now(), o.id).run();
  const init = await paystack.initializeCharge(env, {
    email, amountMinor: minor, currency, reference,
    callbackUrl: `${env.APP_URL}/orders/${o.id}?paid=1`, metadata: { orderId: o.id, ref: o.ref },
  });
  return { url: init.authorization_url, currency, amountMinor: minor };
}

const USDC_FEE_BUFFER_CENTS = 10;

export async function startUsdcPayment(env: Env, o: Order, buyer: { fossa_customer_id: string | null }) {
  if (env.PAYMENT_MODE === "sandbox") throw new HttpError(503, "USDC payments are disabled in sandbox mode");
  if (o.status !== "awaiting_payment") throw bad("Order is not awaiting payment");
  if (!buyer.fossa_customer_id) throw bad("Create your USDC wallet first");
  const bal = await fossa.stellarBalance(env, buyer.fossa_customer_id);
  const gross = (o.total_cents + USDC_FEE_BUFFER_CENTS) / 100;
  if (Number(bal.usdc) < gross) throw bad(`Not enough USDC. You need $${gross.toFixed(2)} (includes network fee).`);
  // claim first so a double tap can't send twice
  const claimed = await env.DB.prepare("UPDATE orders SET funding='usdc', pay_currency='USDC', pay_amount_minor=?, fossa_ref=?, updated_at=? WHERE id=? AND status='awaiting_payment' AND funding IS NULL")
    .bind(Math.round(gross * 1e7), o.ref, now(), o.id).run();
  if (!(claimed.meta.changes ?? 0)) throw bad("Payment already started");
  try {
    await fossa.sendUsdc(env, { customerId: buyer.fossa_customer_id, recipient: env.PLATFORM_STELLAR_ADDRESS, amountUsd: gross, memo: o.ref });
  } catch (e) {
    await env.DB.prepare("UPDATE orders SET funding=NULL, pay_currency=NULL, pay_amount_minor=NULL, updated_at=? WHERE id=?").bind(now(), o.id).run();
    throw e;
  }
  await addEvent(env, o.id, "payment_sent", "USDC transfer submitted. Waiting for network confirmation.");
  return { status: "processing" };
}

/** Called from the Paystack / FossaPay webhooks once money has really arrived. */
export async function markFunded(env: Env, orderId: string, how: string) {
  const o = await getOrder(env, orderId);
  if (!o) return;
  if (!(await transition(env, orderId, "awaiting_payment", "funded"))) return;
  await addEvent(env, orderId, "funded", `Payment received (${how}). Held in escrow.`);
  await notify(env, o.vendor_id, "New order funded", `${o.ref} · ${money(o.total_cents)} is in escrow. Accept to receive your ${money(o.deposit_cents)} deposit.`, orderId);
  await notify(env, o.buyer_id, "Payment received", `${o.ref} is funded and protected until your goods are inspected.`, orderId);
}

// ---------- vendor + inspection steps ----------

export async function vendorAccept(env: Env, o: Order) {
  const shipBy = now() + o.lead_days * DAY;
  if (!(await transition(env, o.id, "funded", "accepted", `, ship_by=${shipBy}`))) throw bad("Order can't be accepted now");
  await credit(env, o.vendor_id, o.id, "deposit_release", o.deposit_cents);
  await revenue(env, "protection_fee", o.fee_cents, { orderId: o.id }); // refundable until the supplier accepts
  await addEvent(env, o.id, "accepted", `Supplier accepted. ${money(o.deposit_cents)} deposit released.`);
  await notify(env, o.buyer_id, "Supplier accepted your order", `${o.ref}: deposit of ${money(o.deposit_cents)} released. Balance stays locked until inspection.`, o.id);
}

export async function vendorReady(env: Env, o: Order, proofKeys: string[], note: string) {
  if (!proofKeys.length) throw bad("Add at least one photo or document");
  const r = await env.DB.prepare("UPDATE orders SET status='inspection', proof_keys=?, updated_at=? WHERE id=? AND status='accepted'")
    .bind(JSON.stringify(proofKeys), now(), o.id).run();
  if (!(r.meta.changes ?? 0)) throw bad("Order can't be sent to inspection now");
  await addEvent(env, o.id, "inspection_requested", note || "Goods ready for inspection");
  await notify(env, o.buyer_id, "Goods ready for inspection", `${o.ref}: the supplier uploaded proof. Inspection is next.`, o.id);
}

export async function inspectionResult(env: Env, o: Order, pass: boolean, note: string) {
  if (pass) {
    if (!(await transition(env, o.id, "inspection", "shipped"))) throw bad("Order is not in inspection");
    const commission = Math.min(o.balance_cents, pct(o.subtotal_cents, Number(env.SELLER_COMMISSION_PERCENT ?? 0)));
    await credit(env, o.vendor_id, o.id, "balance_release", o.balance_cents - commission);
    await revenue(env, "seller_commission", commission, { orderId: o.id });
    await addEvent(env, o.id, "inspection_passed", note || "Inspection passed. Balance released to supplier.");
    await notify(env, o.vendor_id, "Balance released", `${o.ref}: ${money(o.balance_cents - commission)} is now in your wallet.`, o.id);
    await notify(env, o.buyer_id, "Inspection passed", `${o.ref} passed inspection and is on its way.`, o.id);
  } else {
    if (!(await transition(env, o.id, "inspection", "refunded"))) throw bad("Order is not in inspection");
    await addEvent(env, o.id, "inspection_failed", note || "Inspection failed. Balance refunded.");
    await refundExternal(env, o, o.balance_cents);
    await notify(env, o.buyer_id, "Refund on its way", `${o.ref} failed inspection. ${money(o.balance_cents)} is being refunded.`, o.id);
  }
}

export async function confirmDelivery(env: Env, o: Order) {
  if (!(await transition(env, o.id, "shipped", "delivered"))) throw bad("Order is not shipped yet");
  await addEvent(env, o.id, "delivered", "Buyer confirmed delivery");
  await notify(env, o.vendor_id, "Order delivered", `${o.ref} was confirmed delivered.`, o.id);
}

export async function cancelUnpaid(env: Env, o: Order) {
  if (!(await transition(env, o.id, "awaiting_payment", "cancelled"))) throw bad("Only unpaid orders can be cancelled");
  await addEvent(env, o.id, "cancelled", "Cancelled before payment");
}

// ---------- refunds ----------

/** Sends money back to the buyer on the rail they paid with. Records failures as events for ops to retry. */
export async function refundExternal(env: Env, o: Order, cents: number) {
  try {
    if (o.funding === "paystack" && o.paystack_ref && o.pay_amount_minor) {
      const minor = Math.round((o.pay_amount_minor * cents) / o.total_cents);
      await paystack.refundCharge(env, o.paystack_ref, minor);
    } else if (o.funding === "usdc") {
      if (env.PAYMENT_MODE === "sandbox") throw new Error("USDC refunds are disabled in sandbox mode");
      const buyer = await env.DB.prepare("SELECT stellar_address FROM users WHERE id=?").bind(o.buyer_id).first<{ stellar_address: string | null }>();
      if (!buyer?.stellar_address) throw new Error("buyer has no stellar address");
      await fossa.sendUsdc(env, { customerId: env.PLATFORM_FOSSA_CUSTOMER_ID, recipient: buyer.stellar_address, amountUsd: cents / 100, memo: o.ref });
    } else {
      throw new Error("order was never funded");
    }
    await addEvent(env, o.id, "refund_sent", `${money(cents)} refunded to buyer`);
  } catch (e) {
    console.error("refund failed", o.ref, e);
    await addEvent(env, o.id, "refund_failed", `Refund of ${money(cents)} needs manual attention: ${String(e).slice(0, 120)}`);
  }
}

/** Cron: refunds orders whose supplier missed the accept or ship deadline. */
export async function sweepDeadlines(env: Env) {
  const t = now();
  const { results: stale } = await env.DB.prepare("SELECT * FROM orders WHERE status='funded' AND accept_by < ?").bind(t).all<Order>();
  for (const o of stale) {
    if (await transition(env, o.id, "funded", "refunded")) {
      await addEvent(env, o.id, "expired", "Supplier did not accept in time. Full refund.");
      await refundExternal(env, o, o.total_cents);
      await notify(env, o.buyer_id, "Order refunded", `${o.ref}: the supplier didn't accept in time. You'll get everything back.`, o.id);
    }
  }
  const { results: late } = await env.DB.prepare("SELECT * FROM orders WHERE status='accepted' AND ship_by IS NOT NULL AND ship_by < ?").bind(t).all<Order>();
  for (const o of late) {
    if (await transition(env, o.id, "accepted", "refunded")) {
      await addEvent(env, o.id, "missed_deadline", "Supplier missed the shipping deadline. Locked balance refunded.");
      await refundExternal(env, o, o.balance_cents);
      await notify(env, o.buyer_id, "Deadline missed: refund sent", `${o.ref}: ${money(o.balance_cents)} is on its way back to you.`, o.id);
      await notify(env, o.vendor_id, "Order closed", `${o.ref} missed the shipping deadline and was refunded.`, o.id);
    }
  }
}

// ---------- vendor wallet ----------

export async function availableCents(env: Env, userId: string): Promise<number> {
  const r = await env.DB.prepare("SELECT COALESCE(SUM(amount_cents),0) AS s FROM ledger WHERE user_id=?").bind(userId).first<{ s: number }>();
  return r?.s ?? 0;
}

export async function lockedCents(env: Env, userId: string): Promise<number> {
  const r = await env.DB.prepare("SELECT COALESCE(SUM(balance_cents),0) AS s FROM orders WHERE vendor_id=? AND status IN ('accepted','inspection')").bind(userId).first<{ s: number }>();
  return r?.s ?? 0;
}

export type WithdrawInput =
  | { method: "usdc"; amountCents: number; address: string; memo?: string }
  | { method: "fiat"; amountCents: number; payoutAccountId: string };

export async function withdraw(env: Env, userId: string, a: WithdrawInput) {
  if (env.PAYMENT_MODE === "sandbox" && a.method === "usdc") throw new HttpError(503, "USDC withdrawals are disabled in sandbox mode");
  if (!Number.isInteger(a.amountCents) || a.amountCents < 500) throw bad("Minimum withdrawal is $5");
  const id = uid();
  const t = now();
  // Reserve funds first: only insert if balance covers it, in one statement.
  const reserve = await env.DB.prepare(
    `INSERT INTO ledger (id,user_id,order_id,kind,amount_cents,ref,created_at)
     SELECT ?,?,NULL,'withdrawal',?,?,? WHERE (SELECT COALESCE(SUM(amount_cents),0) FROM ledger WHERE user_id=?) >= ?`,
  ).bind(uid(), userId, -a.amountCents, id, t, userId, a.amountCents).run();
  if (!(reserve.meta.changes ?? 0)) throw bad("Not enough available balance");

  const fail = async (msg: string): Promise<never> => {
    await env.DB.prepare("INSERT INTO ledger (id,user_id,order_id,kind,amount_cents,ref,created_at) VALUES (?,?,NULL,'withdrawal_reversal',?,?,?)")
      .bind(uid(), userId, a.amountCents, id, now()).run();
    await env.DB.prepare("UPDATE withdrawals SET status='failed', error=?, updated_at=? WHERE id=?").bind(msg.slice(0, 200), now(), id).run();
    await reverseSpread(env, id);
    throw new HttpError(502, msg);
  };

  if (a.method === "usdc") {
    await env.DB.prepare("INSERT INTO withdrawals (id,user_id,method,amount_cents,dest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,'processing',?,?)")
      .bind(id, userId, "usdc", a.amountCents, JSON.stringify({ address: a.address, memo: a.memo ?? null }), t, t).run();
    try {
      await fossa.sendUsdc(env, { customerId: env.PLATFORM_FOSSA_CUSTOMER_ID, recipient: a.address, amountUsd: a.amountCents / 100, memo: a.memo ?? id.slice(0, 20) });
    } catch (e) { return fail(String((e as Error).message)); }
    await env.DB.prepare("UPDATE withdrawals SET status='completed', updated_at=? WHERE id=?").bind(now(), id).run();
    return { id, status: "completed" };
  }

  const acct = await env.DB.prepare("SELECT * FROM payout_accounts WHERE id=? AND user_id=?").bind(a.payoutAccountId, userId)
    .first<{ id: string; kind: "bank" | "momo"; currency: "NGN" | "GHS"; bank_code: string; bank_name: string; account_number: string; account_name: string; paystack_recipient: string | null }>();
  if (!acct) return fail("Payout account not found");
  const spreadPct = Number(env.WITHDRAWAL_SPREAD_PERCENT ?? 1.5);
  const fiatMinor = Math.floor(a.amountCents * fxRate(env, acct.currency) * (1 - spreadPct / 100));
  const spreadCents = pct(a.amountCents, spreadPct);
  await env.DB.prepare("INSERT INTO withdrawals (id,user_id,method,amount_cents,fiat_currency,fiat_minor,dest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,'processing',?,?)")
    .bind(id, userId, acct.kind, a.amountCents, acct.currency, fiatMinor, JSON.stringify({ accountId: acct.id }), t, t).run();
  await revenue(env, "withdrawal_spread", spreadCents, { withdrawalId: id });

  // Rail 1: Paystack transfer from the fiat balance. Rail 2 (fallback): USDC off-ramp when Paystack balance is short.
  try {
    let code = acct.paystack_recipient;
    if (!code) {
      const r = await paystack.createRecipient(env, { kind: acct.kind, currency: acct.currency, name: acct.account_name, accountNumber: acct.account_number, bankCode: acct.bank_code });
      code = r.recipient_code;
      await env.DB.prepare("UPDATE payout_accounts SET paystack_recipient=? WHERE id=?").bind(code, acct.id).run();
    }
    const tr = await paystack.sendTransfer(env, { amountMinor: fiatMinor, recipient: code, reference: id, reason: "Kontena payout", currency: acct.currency });
    await env.DB.prepare("UPDATE withdrawals SET provider_ref=?, updated_at=? WHERE id=?").bind(tr.transfer_code, now(), id).run();
    return { id, status: "processing" };
  } catch (e) {
    const msg = String((e as Error).message);
    if (!/balance/i.test(msg)) return fail(msg);
  }
  if (env.OFFRAMP_PROVIDER === "manual") {
    await env.DB.prepare("UPDATE withdrawals SET status='pending', provider_ref='manual', updated_at=? WHERE id=?").bind(now(), id).run();
    return { id, status: "pending" };
  }
  try {
    const r = await yc.disburse(env, {
      amountUsd: a.amountCents / 100, sequenceId: id, reason: "Kontena payout",
      dest: { accountNumber: acct.account_number, accountName: acct.account_name, bankName: acct.bank_name, bankCode: acct.bank_code, currency: acct.currency, kind: acct.kind },
    });
    await env.DB.prepare("UPDATE withdrawals SET provider_ref=?, updated_at=? WHERE id=?").bind(r.id, now(), id).run();
    return { id, status: "processing" };
  } catch (e) { return fail(String((e as Error).message)); }
}

/** A failed payout earns nothing: undo the spread we booked for it. */
async function reverseSpread(env: Env, withdrawalId: string) {
  const r = await env.DB.prepare("SELECT amount_cents FROM platform_revenue WHERE withdrawal_id=? AND kind='withdrawal_spread'").bind(withdrawalId).first<{ amount_cents: number }>();
  if (r) await revenue(env, "withdrawal_spread_reversal", -r.amount_cents, { withdrawalId });
}

export async function finishWithdrawal(env: Env, id: string, ok: boolean, note = "") {
  const w = await env.DB.prepare("SELECT * FROM withdrawals WHERE id=?").bind(id).first<{ user_id: string; amount_cents: number; status: string }>();
  if (!w || w.status === "completed" || w.status === "failed") return;
  if (ok) {
    await env.DB.prepare("UPDATE withdrawals SET status='completed', updated_at=? WHERE id=?").bind(now(), id).run();
    await notify(env, w.user_id, "Withdrawal sent", `${money(w.amount_cents)} is on its way to your account.`);
  } else {
    const claimed = await env.DB.prepare("UPDATE withdrawals SET status='failed', error=?, updated_at=? WHERE id=? AND status NOT IN ('failed','completed')").bind(note.slice(0, 200), now(), id).run();
    if ((claimed.meta.changes ?? 0) > 0) {
      await env.DB.prepare("INSERT INTO ledger (id,user_id,order_id,kind,amount_cents,ref,created_at) VALUES (?,?,NULL,'withdrawal_reversal',?,?,?)")
        .bind(uid(), w.user_id, w.amount_cents, id, now()).run();
      await reverseSpread(env, id);
      await notify(env, w.user_id, "Withdrawal failed", `${money(w.amount_cents)} was returned to your Kontena balance.`);
    }
  }
}
