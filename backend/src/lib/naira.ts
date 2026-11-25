import type { Env } from "./env";
import { bad, HttpError, now, uid } from "./util";
import { notify } from "./fcm";

export const ngn = (kobo: number) => `₦${(kobo / 100).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export async function walletBalance(env: Env, userId: string): Promise<number> {
  const r = await env.DB.prepare("SELECT COALESCE(SUM(amount_kobo),0) AS s FROM wallet_entries WHERE user_id=?").bind(userId).first<{ s: number }>();
  return r?.s ?? 0;
}

/** Adds money to a wallet. Safe to call twice with the same (kind, ref): the second call does nothing and returns false. */
export async function creditWallet(env: Env, userId: string, kind: string, kobo: number, ref: string, o: { orderId?: string; note?: string; silent?: boolean } = {}): Promise<boolean> {
  if (!Number.isInteger(kobo) || kobo <= 0) throw bad("Invalid amount");
  const r = await env.DB.prepare("INSERT OR IGNORE INTO wallet_entries (id,user_id,kind,amount_kobo,ref,order_id,note,created_at) VALUES (?,?,?,?,?,?,?,?)")
    .bind(uid(), userId, kind, kobo, ref, o.orderId ?? null, o.note ?? "", now()).run();
  const added = (r.meta.changes ?? 0) > 0;
  if (added && !o.silent) {
    const title = kind === "refund" ? "Refund added to your wallet" : "Money received";
    await notify(env, userId, title, `${ngn(kobo)} is now in your Kontena Naira wallet.`, o.orderId);
  }
  return added;
}

/** Takes money out only if the balance covers it, in one statement, so two taps can never overdraw. */
export async function debitWallet(env: Env, userId: string, kind: string, kobo: number, ref: string, o: { orderId?: string; note?: string } = {}): Promise<void> {
  if (!Number.isInteger(kobo) || kobo <= 0) throw bad("Invalid amount");
  const r = await env.DB.prepare(
    `INSERT OR IGNORE INTO wallet_entries (id,user_id,kind,amount_kobo,ref,order_id,note,created_at)
     SELECT ?,?,?,?,?,?,?,? WHERE (SELECT COALESCE(SUM(amount_kobo),0) FROM wallet_entries WHERE user_id=?) >= ?`,
  ).bind(uid(), userId, kind, -kobo, ref, o.orderId ?? null, o.note ?? "", now(), userId, kobo).run();
  if (!(r.meta.changes ?? 0)) throw bad("Not enough money in your Naira wallet");
}

export const maxBalanceKobo = (env: Env) => Math.round(Number(env.WALLET_MAX_NGN ?? 300000) * 100);

export async function virtualAccount(env: Env, userId: string) {
  return env.DB.prepare("SELECT status,account_number,account_name,bank_name FROM virtual_accounts WHERE user_id=?").bind(userId)
    .first<{ status: string; account_number: string | null; account_name: string | null; bank_name: string | null }>();
}

export async function recentEntries(env: Env, userId: string, limit = 40) {
  const { results } = await env.DB.prepare("SELECT id,kind,amount_kobo,note,order_id,created_at FROM wallet_entries WHERE user_id=? ORDER BY created_at DESC, rowid DESC LIMIT ?")
    .bind(userId, limit).all();
  return results;
}

async function userByCustomer(env: Env, customerCode: string | undefined, email: string | undefined): Promise<string | null> {
  if (customerCode) {
    const a = await env.DB.prepare("SELECT user_id FROM virtual_accounts WHERE customer_code=?").bind(customerCode).first<{ user_id: string }>();
    if (a) return a.user_id;
  }
  if (email) {
    const u = await env.DB.prepare("SELECT id FROM users WHERE lower(email)=lower(?)").bind(email).first<{ id: string }>();
    if (u) return u.id;
  }
  return null;
}

/** Called by the Paystack webhook when a bank transfer lands in a user's dedicated account. */
export async function creditFromTransfer(env: Env, c: { customerCode?: string; email?: string }, kobo: number, reference: string): Promise<boolean> {
  const uidv = await userByCustomer(env, c.customerCode, c.email);
  if (!uidv) return false;
  await creditWallet(env, uidv, "transfer_in", kobo, reference, { note: "Bank transfer" });
  return true;
}

export async function storeAssignedAccount(env: Env, c: { customerCode?: string; email?: string }, acct: { account_number: string; account_name: string; bank?: { name?: string } }) {
  const userId = await userByCustomer(env, c.customerCode, c.email);
  if (!userId) return;
  await env.DB.prepare("UPDATE virtual_accounts SET status='active', customer_code=COALESCE(?,customer_code), account_number=?, account_name=?, bank_name=? WHERE user_id=?")
    .bind(c.customerCode ?? null, acct.account_number, acct.account_name, acct.bank?.name ?? "", userId).run();
  await notify(env, userId, "Your Naira account number is ready", `${acct.account_number} · ${acct.bank?.name ?? "bank"}. Transfer money in any time.`);
}

export async function failAssignedAccount(env: Env, c: { customerCode?: string; email?: string }) {
  const userId = await userByCustomer(env, c.customerCode, c.email);
  if (userId) await env.DB.prepare("UPDATE virtual_accounts SET status='failed' WHERE user_id=?").bind(userId).run();
}
