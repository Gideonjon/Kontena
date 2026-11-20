import type { Env, User } from "./env";
import { HttpError } from "./util";

const BASE = "https://api-production.fossapay.com/api/v1";

async function fp<T>(env: Env, method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(BASE + path, {
    method,
    headers: { "x-api-key": env.FOSSAPAY_API_KEY, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = (await res.json().catch(() => ({}))) as { message?: string; data?: T };
  if (!res.ok) throw new HttpError(502, `FossaPay: ${j.message ?? res.status}`);
  return j.data as T;
}

/** Creates the FossaPay customer and its Stellar wallet. Wallet creation is not idempotent, so callers must check first. */
export async function createCustomer(env: Env, u: User): Promise<string> {
  const [first, ...rest] = (u.name || "Kontena User").trim().split(/\s+/);
  const d = await fp<{ id: string }>(env, "POST", "/customers", {
    firstName: first.replace(/[^A-Za-z]/g, "") || "User",
    lastName: (rest.join("").replace(/[^A-Za-z]/g, "")) || "Trader",
    emailAddress: u.email,
    mobileNumber: u.phone,
    dateOfBirth: u.dob,
    address: u.address,
    city: u.city,
    country: u.country === "GH" ? "Ghana" : "Nigeria",
    type: "individual",
  });
  return d.id;
}

export const createStellarWallet = (env: Env, customerId: string) =>
  fp<{ id: string; walletId: string; address: string; network: string }>(env, "POST", "/wallets/crypto/create", {
    network: "stellar", customerId,
  });

export type StellarBalance = { xlm: string; usdc: string };

export async function stellarBalance(env: Env, customerId: string): Promise<StellarBalance> {
  const d = await fp<{ tokens?: { xlm?: { amount: string }; usdc?: { amount: string } } }[]>(
    env, "GET", `/wallets/crypto/customer/${customerId}/balance?network=stellar`);
  const t = d?.[0]?.tokens ?? {};
  return { xlm: t.xlm?.amount ?? "0", usdc: t.usdc?.amount ?? "0" };
}

/** Sends USDC on Stellar. FossaPay deducts its configured fee from `amount`; no idempotency key exists, so never auto-retry. */
export const sendUsdc = (env: Env, a: { customerId: string; recipient: string; amountUsd: number; memo?: string }) =>
  fp<{ status: string }>(env, "POST", "/transfers/crypto", {
    customerId: a.customerId,
    recipient: a.recipient,
    network: "stellar",
    currency: "usdc",
    amount: Number(a.amountUsd.toFixed(7)),
    ...(a.memo ? { memo: a.memo.slice(0, 28) } : {}),
  });
