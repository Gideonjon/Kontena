import type { Env } from "./env";
import { HttpError } from "./util";

const BASE = "https://api.paystack.co";

async function ps<T>(env: Env, method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(BASE + path, {
    method,
    headers: { Authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = (await res.json().catch(() => ({}))) as { status?: boolean; message?: string; data?: T };
  if (!res.ok || j.status === false) throw new HttpError(502, `Paystack: ${j.message ?? res.status}`);
  return j.data as T;
}

export const initializeCharge = (env: Env, a: {
  email: string; amountMinor: number; currency: "NGN" | "GHS"; reference: string; callbackUrl: string; metadata: Record<string, unknown>;
}) =>
  ps<{ authorization_url: string; access_code: string; reference: string }>(env, "POST", "/transaction/initialize", {
    email: a.email,
    amount: a.amountMinor,
    currency: a.currency,
    reference: a.reference,
    callback_url: a.callbackUrl,
    metadata: a.metadata,
    channels: a.currency === "GHS" ? ["card", "mobile_money"] : ["card", "bank_transfer", "bank", "ussd"],
  });

export const verifyCharge = (env: Env, reference: string) =>
  ps<{ status: string; amount: number; currency: string; reference: string }>(env, "GET", `/transaction/verify/${encodeURIComponent(reference)}`);

export const refundCharge = (env: Env, reference: string, amountMinor: number) =>
  ps<{ id: number; status: string }>(env, "POST", "/refund", { transaction: reference, amount: amountMinor });

/** country: nigeria | ghana. For Ghana mobile money pass type = mobile_money. */
export const listBanks = (env: Env, country: "nigeria" | "ghana", type?: "mobile_money") =>
  ps<{ name: string; code: string; type: string; currency: string }[]>(
    env, "GET", `/bank?country=${country}&perPage=200${type ? `&type=${type}` : ""}`);

export const resolveAccount = (env: Env, accountNumber: string, bankCode: string) =>
  ps<{ account_number: string; account_name: string }>(env, "GET", `/bank/resolve?account_number=${accountNumber}&bank_code=${bankCode}`);

export const createRecipient = (env: Env, a: {
  kind: "bank" | "momo"; currency: "NGN" | "GHS"; name: string; accountNumber: string; bankCode: string;
}) =>
  ps<{ recipient_code: string }>(env, "POST", "/transferrecipient", {
    type: a.kind === "momo" ? "mobile_money" : a.currency === "GHS" ? "ghipss" : "nuban",
    name: a.name,
    account_number: a.accountNumber,
    bank_code: a.bankCode,
    currency: a.currency,
  });

export const sendTransfer = (env: Env, a: { amountMinor: number; recipient: string; reference: string; reason: string; currency: "NGN" | "GHS" }) =>
  ps<{ transfer_code: string; status: string }>(env, "POST", "/transfer", {
    source: "balance", amount: a.amountMinor, recipient: a.recipient, reference: a.reference, reason: a.reason, currency: a.currency,
  });
