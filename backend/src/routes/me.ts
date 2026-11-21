import { Hono } from "hono";
import type { App } from "./types";
import type { User } from "../lib/env";
import { bad, HttpError, now, uid, currencyFor } from "../lib/util";
import { availableCents, lockedCents } from "../lib/orders";
import * as paystack from "../lib/paystack";
import * as fossa from "../lib/fossapay";
import { isAdmin } from "../lib/auth";
import type { Env } from "../lib/env";

export const me = new Hono<App>();

const publicUser = (u: User, env: Env) => ({
  isAdmin: isAdmin(env, u),
  id: u.id, email: u.email, name: u.name, phone: u.phone, country: u.country, role: u.role,
  hasWallet: !!u.stellar_address, stellarAddress: u.stellar_address, kycDone: !!(u.dob && u.address && u.city),
});

me.get("/me", async (c) => {
  const u = c.get("user");
  const store = await c.env.DB.prepare("SELECT id,slug,name FROM stores WHERE owner_id=?").bind(u.id).first();
  return c.json({ user: publicUser(u, c.env), store });
});

me.patch("/me", async (c) => {
  const u = c.get("user");
  const b = await c.req.json<Partial<{ name: string; phone: string; country: string; role: string; dob: string; address: string; city: string }>>();
  if (b.country && !["NG", "GH"].includes(b.country)) throw bad("Country must be NG or GH");
  if (b.role && !["customer", "vendor"].includes(b.role)) throw bad("Role must be customer or vendor");
  if (b.dob && !/^\d{4}-\d{2}-\d{2}$/.test(b.dob)) throw bad("Date of birth must be YYYY-MM-DD");
  await c.env.DB.prepare(
    "UPDATE users SET name=COALESCE(?,name), phone=COALESCE(?,phone), country=COALESCE(?,country), role=COALESCE(?,role), dob=COALESCE(?,dob), address=COALESCE(?,address), city=COALESCE(?,city) WHERE id=?",
  ).bind(b.name ?? null, b.phone ?? null, b.country ?? null, u.role === "admin" ? null : b.role ?? null, b.dob ?? null, b.address ?? null, b.city ?? null, u.id).run();
  const fresh = (await c.env.DB.prepare("SELECT * FROM users WHERE id=?").bind(u.id).first<User>())!;
  return c.json({ user: publicUser(fresh, c.env) });
});

me.post("/device-token", async (c) => {
  const u = c.get("user");
  const { token, platform } = await c.req.json<{ token: string; platform?: string }>();
  if (!token) throw bad("token required");
  await c.env.DB.prepare("INSERT INTO device_tokens (token,user_id,platform,created_at) VALUES (?,?,?,?) ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id")
    .bind(token, u.id, platform ?? "", now()).run();
  return c.json({ ok: true });
});

me.get("/notifications", async (c) => {
  const { results } = await c.env.DB.prepare("SELECT id,title,body,order_id,read,created_at FROM notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 50")
    .bind(c.get("user").id).all();
  return c.json({ notifications: results });
});

me.post("/notifications/read", async (c) => {
  await c.env.DB.prepare("UPDATE notifications SET read=1 WHERE user_id=?").bind(c.get("user").id).run();
  return c.json({ ok: true });
});

// ---------- wallet ----------

/** Creates the user's custodial Stellar wallet on FossaPay. Needs KYC fields on the profile. */
me.post("/wallet", async (c) => {
  if (c.env.PAYMENT_MODE === "sandbox") throw new HttpError(503, "USDC wallets are disabled in sandbox mode");
  const u = c.get("user");
  if (u.stellar_address) return c.json({ address: u.stellar_address });
  if (!u.dob || !u.address || !u.city || !u.phone || !u.email) throw bad("Add your phone, date of birth, address and city first");
  let customerId = u.fossa_customer_id;
  if (!customerId) {
    customerId = await fossa.createCustomer(c.env, u);
    await c.env.DB.prepare("UPDATE users SET fossa_customer_id=? WHERE id=?").bind(customerId, u.id).run();
  }
  const w = await fossa.createStellarWallet(c.env, customerId);
  await c.env.DB.prepare("UPDATE users SET fossa_wallet_id=?, stellar_address=? WHERE id=?").bind(w.id, w.address, u.id).run();
  return c.json({ address: w.address });
});

me.get("/wallet", async (c) => {
  const u = c.get("user");
  let usdc = "0.00", xlm = "0";
  if (u.fossa_customer_id && u.stellar_address) {
    try { const b = await fossa.stellarBalance(c.env, u.fossa_customer_id); usdc = b.usdc; xlm = b.xlm; } catch { /* show zero if provider is down */ }
  }
  const [available, locked] = await Promise.all([availableCents(c.env, u.id), lockedCents(c.env, u.id)]);
  const { results: withdrawals } = await c.env.DB.prepare("SELECT id,method,amount_cents,fiat_currency,fiat_minor,status,created_at FROM withdrawals WHERE user_id=? ORDER BY created_at DESC LIMIT 30").bind(u.id).all();
  const { results: accounts } = await c.env.DB.prepare("SELECT id,kind,currency,bank_name,account_number,account_name FROM payout_accounts WHERE user_id=?").bind(u.id).all();
  return c.json({ usdc, xlm, address: u.stellar_address, earnings: { availableCents: available, lockedCents: locked }, withdrawals, accounts });
});

// ---------- payout accounts ----------

me.get("/banks", async (c) => {
  const country = c.req.query("country") === "GH" ? "ghana" : "nigeria";
  const type = c.req.query("type") === "momo" ? "mobile_money" : undefined;
  const banks = await paystack.listBanks(c.env, country, type);
  return c.json({ banks: banks.map((b) => ({ name: b.name, code: b.code })) });
});

me.post("/payout-accounts", async (c) => {
  const u = c.get("user");
  const b = await c.req.json<{ kind: "bank" | "momo"; bankCode: string; bankName: string; accountNumber: string; accountName?: string }>();
  if (!b.bankCode || !b.accountNumber) throw bad("Bank and account number required");
  const currency = currencyFor(u.country);
  let name = b.accountName ?? "";
  if (b.kind === "bank" && currency === "NGN") {
    // Name enquiry is only offered for Nigerian bank accounts; everything else trusts the name entered.
    name = (await paystack.resolveAccount(c.env, b.accountNumber, b.bankCode)).account_name;
  }
  if (!name) throw bad("Account name required");
  const id = uid();
  await c.env.DB.prepare("INSERT INTO payout_accounts (id,user_id,kind,currency,bank_code,bank_name,account_number,account_name,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
    .bind(id, u.id, b.kind, currency, b.bankCode, b.bankName, b.accountNumber, name, now()).run();
  return c.json({ id, accountName: name });
});

me.delete("/payout-accounts/:id", async (c) => {
  await c.env.DB.prepare("DELETE FROM payout_accounts WHERE id=? AND user_id=?").bind(c.req.param("id"), c.get("user").id).run();
  return c.json({ ok: true });
});

// ---------- media upload ----------

me.post("/media", async (c) => {
  const type = c.req.header("Content-Type") ?? "";
  if (!/^image\/(jpeg|png|webp)$/.test(type)) throw bad("Only JPEG, PNG or WebP images");
  const buf = await c.req.arrayBuffer();
  if (buf.byteLength > 4 * 1024 * 1024) throw new HttpError(413, "Image must be under 4 MB");
  const ext = type.split("/")[1];
  const key = `${c.get("user").id}/${uid()}.${ext}`;
  await c.env.MEDIA.put(key, buf, { httpMetadata: { contentType: type } });
  return c.json({ key });
});
