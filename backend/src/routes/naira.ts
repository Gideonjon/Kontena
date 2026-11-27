import { Hono } from "hono";
import type { App } from "./types";
import { bad, HttpError, now, uid } from "../lib/util";
import * as paystack from "../lib/paystack";
import { creditWallet, debitWallet, maxBalanceKobo, ngn, recentEntries, virtualAccount, walletBalance } from "../lib/naira";
import { requirePasskeyIfEnrolled } from "../lib/passkeys";

export const naira = new Hono<App>();

const MIN_TOPUP = 10_000;          // ₦100
const MIN_WITHDRAW = 10_000;       // ₦100

naira.get("/", async (c) => {
  const u = c.get("user");
  const [balance, account, entries] = await Promise.all([walletBalance(c.env, u.id), virtualAccount(c.env, u.id), recentEntries(c.env, u.id)]);
  return c.json({ balanceKobo: balance, account, entries, refundTo: u.refund_to ?? "wallet", maxBalanceKobo: maxBalanceKobo(c.env) });
});

/** Ask Paystack for a personal NGN account number. It arrives by webhook a few seconds later. */
naira.post("/account", async (c) => {
  const u = c.get("user");
  if (u.country !== "NG") throw bad("Naira accounts are for Nigeria only");
  const existing = await virtualAccount(c.env, u.id);
  if (existing && existing.status !== "failed") return c.json({ status: existing.status, account: existing });
  const b = await c.req.json<{ bvn?: string; accountNumber?: string; bankCode?: string }>().catch(() => ({}) as { bvn?: string; accountNumber?: string; bankCode?: string });
  if (!u.phone) throw bad("Add your phone number in Profile first");
  const [first, ...rest] = (u.name || "Kontena user").trim().split(/\s+/);
  await paystack.assignDedicatedAccount(c.env, {
    email: u.email, firstName: first, lastName: rest.join(" ") || first, phone: u.phone,
    preferredBank: c.env.PAYSTACK_DVA_BANK ?? "test-bank", bvn: b.bvn, accountNumber: b.accountNumber, bankCode: b.bankCode,
  });
  await c.env.DB.prepare("INSERT INTO virtual_accounts (user_id,status,created_at) VALUES (?,'pending',?) ON CONFLICT(user_id) DO UPDATE SET status='pending'").bind(u.id, now()).run();
  return c.json({ status: "pending" }, 202);
});

/** Add money by card, bank transfer or USSD through Paystack checkout. */
naira.post("/topup", async (c) => {
  const u = c.get("user");
  if (u.country !== "NG") throw bad("Naira wallet is for Nigeria only");
  const { amountNgn } = await c.req.json<{ amountNgn: number }>();
  const kobo = Math.round((amountNgn ?? 0) * 100);
  if (!Number.isFinite(kobo) || kobo < MIN_TOPUP) throw bad("Minimum top-up is ₦100");
  const bal = await walletBalance(c.env, u.id);
  if (bal + kobo > maxBalanceKobo(c.env)) throw bad(`Your wallet can hold up to ${ngn(maxBalanceKobo(c.env))}. Complete verification to raise this limit.`);
  const reference = `WT-${uid().slice(0, 18)}`;
  const init = await paystack.initializeTopup(c.env, { email: u.email, amountKobo: kobo, reference, callbackUrl: `${c.env.APP_URL}/#/c/wallet?topup=1`, userId: u.id });
  return c.json({ url: init.authorization_url, reference });
});

/** Send wallet money to the user's own saved bank account. */
naira.post("/withdraw", async (c) => {
  await requirePasskeyIfEnrolled(c.env, c.get("user").id, c.req.header("X-Passkey-Token"), "naira:withdraw");
  const u = c.get("user");
  const b = await c.req.json<{ amountNgn: number; payoutAccountId: string }>();
  const kobo = Math.round((b.amountNgn ?? 0) * 100);
  if (!Number.isFinite(kobo) || kobo < MIN_WITHDRAW) throw bad("Minimum withdrawal is ₦100");
  const acct = await c.env.DB.prepare("SELECT * FROM payout_accounts WHERE id=? AND user_id=? AND currency='NGN' AND kind='bank'").bind(b.payoutAccountId, u.id)
    .first<{ id: string; bank_code: string; account_number: string; account_name: string; paystack_recipient: string | null }>();
  if (!acct) throw bad("Choose one of your Nigerian bank accounts");
  const id = uid();
  await debitWallet(c.env, u.id, "withdrawal", kobo, id, { note: `To ${acct.account_name}` });
  const t = now();
  await c.env.DB.prepare("INSERT INTO withdrawals (id,user_id,method,amount_cents,fiat_currency,fiat_minor,dest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,'processing',?,?)")
    .bind(id, u.id, "wallet_bank", 0, "NGN", kobo, JSON.stringify({ accountId: acct.id }), t, t).run();
  try {
    let code = acct.paystack_recipient;
    if (!code) {
      code = (await paystack.createRecipient(c.env, { kind: "bank", currency: "NGN", name: acct.account_name, accountNumber: acct.account_number, bankCode: acct.bank_code })).recipient_code;
      await c.env.DB.prepare("UPDATE payout_accounts SET paystack_recipient=? WHERE id=?").bind(code, acct.id).run();
    }
    const tr = await paystack.sendTransfer(c.env, { amountMinor: kobo, recipient: code, reference: id, reason: "Kontena wallet withdrawal", currency: "NGN" });
    await c.env.DB.prepare("UPDATE withdrawals SET provider_ref=?, updated_at=? WHERE id=?").bind(tr.transfer_code, now(), id).run();
    return c.json({ id, status: "processing" });
  } catch (e) {
    const { finishWithdrawal } = await import("../lib/orders");
    await finishWithdrawal(c.env, id, false, String((e as Error).message));
    throw new HttpError(502, (e as Error).message);
  }
});

/** Where Naira refunds go. */
naira.patch("/refund-to", async (c) => {
  const { refundTo } = await c.req.json<{ refundTo: string }>();
  if (!["wallet", "original"].includes(refundTo)) throw bad("refundTo must be wallet or original");
  await c.env.DB.prepare("UPDATE users SET refund_to=? WHERE id=?").bind(refundTo, c.get("user").id).run();
  return c.json({ refundTo });
});
