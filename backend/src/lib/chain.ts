/**
 * Keeps each order's on-chain escrow in step with its status in the database.
 *
 * `syncChain` is idempotent: it looks at where the order is on-chain (`chain_state`) and where the app says it
 * should be (`status`), then performs the missing contract calls in order. It runs right after every status
 * change and again from the cron, so a step that failed (network blip, RPC down) is retried automatically.
 */
import type { Env } from "./env";
import { addEvent, creditOffchainPayouts, getOrder, type Order } from "./orders";
import { now, uid } from "./util";
import * as st from "./stellar";

type ChainState = "none" | "funded" | "accepted" | "released" | "refunded" | "offchain";

const wanted = (status: string): ChainState =>
  status === "funded" ? "funded"
  : status === "accepted" || status === "inspection" ? "accepted"
  : status === "shipped" || status === "delivered" ? "released"
  : status === "refunded" ? "refunded"
  : "none";

async function parties(env: Env, o: Order) {
  const buyer = await env.DB.prepare("SELECT stellar_address FROM users WHERE id=?").bind(o.buyer_id).first<{ stellar_address: string | null }>();
  const seller = await env.DB.prepare("SELECT stellar_address FROM users WHERE id=?").bind(o.vendor_id).first<{ stellar_address: string | null }>();
  return { buyer: buyer?.stellar_address ?? null, seller: seller?.stellar_address ?? null };
}

/** True when this order's supplier payouts and USDC refunds happen on-chain instead of in the internal ledger. */
export async function usesChain(env: Env, o: Order): Promise<boolean> {
  if (!st.chainEnabled(env)) return false;
  const fresh = await env.DB.prepare("SELECT chain_state FROM orders WHERE id=?").bind(o.id).first<{ chain_state: string }>();
  if (fresh?.chain_state === "offchain") return false;
  return !!(await parties(env, o)).seller;
}

async function record(env: Env, o: Order, step: st.ChainStep, hash: string, cents: number | null, note: string, state?: ChainState) {
  await env.DB.prepare("INSERT OR IGNORE INTO chain_txs (id,order_id,step,tx_hash,amount_cents,note,created_at) VALUES (?,?,?,?,?,?,?)")
    .bind(uid(), o.id, step, hash, cents, note, now()).run();
  if (state) await env.DB.prepare("UPDATE orders SET chain_state=?, chain_error=NULL WHERE id=?").bind(state, o.id).run();
  await addEvent(env, o.id, `chain_${step}`, `${note} · recorded on Stellar`);
}

const hasTx = async (env: Env, orderId: string, step: string) =>
  !!(await env.DB.prepare("SELECT 1 FROM chain_txs WHERE order_id=? AND step=?").bind(orderId, step).first());

export async function syncChain(env: Env, orderId: string): Promise<void> {
  if (!st.chainEnabled(env)) return;
  const o = await getOrder(env, orderId);
  if (!o) return;
  let state = (o.chain_state ?? "none") as ChainState;
  const want = wanted(o.status);
  if (state === "offchain" || want === "none" || state === want) return;
  try {
    if (state === "none") {
      const p = await parties(env, o);
      const deadlineGone = o.status === "refunded" || o.accept_by <= now() + 60;
      if (!p.seller || deadlineGone) {
        await env.DB.prepare("UPDATE orders SET chain_state='offchain' WHERE id=?").bind(o.id).run();
        if (p.seller) await creditOffchainPayouts(env, o); // payouts were held back for the chain: pay them in-app
        if (!p.seller) await addEvent(env, o.id, "chain_skipped", "Supplier has no Stellar wallet yet, so this order is protected by Kontena's off-chain escrow");
        return;
      }
      if (o.pay_currency === "NGN" && env.NGN_ASSET && o.pay_amount_minor && !(await hasTx(env, o.id, "convert"))) {
        const subtotalKobo = Math.round((o.pay_amount_minor * o.subtotal_cents) / o.total_cents);
        const maxKobo = Math.round(subtotalKobo * (1 + Number(env.PATH_SLIPPAGE_PERCENT ?? 2) / 100));
        const c = await st.convertNgnToUsdc(env, o.subtotal_cents, maxKobo);
        await record(env, o, "convert", c.hash, o.subtotal_cents, `₦${Number(c.nairaSpent).toLocaleString("en-US", { maximumFractionDigits: 2 })} converted to $${(o.subtotal_cents / 100).toFixed(2)} USDC on the Stellar exchange (${c.path.join(" → ")})`);
      }
      const op = st.operatorAddress(env);
      const refundTo = o.funding === "usdc" && p.buyer ? p.buyer : op;
      const hash = await st.escrowFund(env, {
        orderId: o.id, buyer: p.buyer ?? op, seller: p.seller, refundTo, amountCents: o.subtotal_cents,
        depositPct: Number(env.DEPOSIT_PERCENT), acceptBy: o.accept_by, leadDays: o.lead_days,
      });
      await record(env, o, "fund", hash, o.subtotal_cents, `$${(o.subtotal_cents / 100).toFixed(2)} locked in the escrow contract`, "funded");
      state = "funded";
    }
    if (state === "funded" && (want === "accepted" || want === "released")) {
      const hash = await st.escrowAccept(env, o.id);
      await record(env, o, "accept", hash, o.deposit_cents, `$${(o.deposit_cents / 100).toFixed(2)} deposit paid to the supplier`, "accepted");
      state = "accepted";
    }
    if (state === "accepted" && want === "released") {
      const hash = await st.escrowRelease(env, o.id);
      await record(env, o, "release", hash, o.balance_cents, `$${(o.balance_cents / 100).toFixed(2)} balance paid to the supplier after inspection`, "released");
      state = "released";
    }
    if (want === "refunded" && (state === "funded" || state === "accepted")) {
      const back = state === "funded" ? o.subtotal_cents : o.balance_cents;
      const ev = await env.DB.prepare("SELECT 1 FROM order_events WHERE order_id=? AND type IN ('expired','missed_deadline')").bind(o.id).first();
      let hash: string, step: st.ChainStep = "refund";
      if (ev) {
        try { hash = await st.escrowExpire(env, o.id); step = "expire"; } catch { hash = await st.escrowRefund(env, o.id); }
      } else hash = await st.escrowRefund(env, o.id);
      await record(env, o, step, hash, back, step === "expire" ? `Deadline passed: contract returned $${(back / 100).toFixed(2)}` : `Inspection failed: contract returned $${(back / 100).toFixed(2)}`, "refunded");
    }
  } catch (e) {
    const msg = String((e as Error).message ?? e).slice(0, 300);
    console.error("chain sync", o.ref, msg);
    await env.DB.prepare("UPDATE orders SET chain_error=? WHERE id=?").bind(msg, o.id).run();
  }
}

/** Cron + admin: retry every order whose chain state is behind. */
export async function syncPendingChain(env: Env, limit = 15) {
  if (!st.chainEnabled(env)) return 0;
  const { results } = await env.DB.prepare(
    `SELECT id FROM orders WHERE chain_state <> 'offchain' AND status IN ('funded','accepted','inspection','shipped','delivered','refunded')
       AND NOT (chain_state='funded' AND status='funded') AND NOT (chain_state='accepted' AND status IN ('accepted','inspection'))
       AND NOT (chain_state='released' AND status IN ('shipped','delivered')) AND NOT (chain_state='refunded' AND status='refunded')
       AND NOT (chain_state='none' AND status='refunded')
     ORDER BY updated_at LIMIT ?`).bind(limit).all<{ id: string }>();
  for (const r of results) await syncChain(env, r.id);
  return results.length;
}

/** What the app shows on an order: contract link, state and every transaction with its explorer link. */
export async function chainInfo(env: Env, o: Order) {
  if (!st.chainEnabled(env)) return null;
  const { results } = await env.DB.prepare("SELECT step,tx_hash,amount_cents,note,created_at FROM chain_txs WHERE order_id=? ORDER BY created_at, rowid").bind(o.id).all<{ step: string; tx_hash: string; amount_cents: number | null; note: string; created_at: number }>();
  return {
    network: env.STELLAR_NETWORK ?? "testnet",
    contract: env.ESCROW_CONTRACT_ID, contractUrl: st.explorerContract(env),
    state: o.chain_state ?? "none", error: o.chain_error ?? null,
    txs: results.map((t) => ({ step: t.step, hash: t.tx_hash, url: st.explorerTx(env, t.tx_hash), amountCents: t.amount_cents, note: t.note, at: t.created_at })),
  };
}
