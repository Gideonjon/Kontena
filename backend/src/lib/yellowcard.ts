import type { Env } from "./env";
import { HttpError } from "./util";

/**
 * USDC -> NGN/GHS off-ramp via Yellow Card's Payments API (disbursement).
 *
 * UNVERIFIED against live docs: request signing and body shape are written from Yellow Card's public
 * API glossary (POST /business/payments locks a rate and must be accepted). Check every field against
 * https://docs.yellowcard.engineering in sandbox before going live. The "manual" provider queues the
 * payout for ops instead.
 */
async function sha256b64(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return btoa(String.fromCharCode(...new Uint8Array(d)));
}

async function sign(env: Env, method: string, path: string, body: string | undefined) {
  const ts = new Date().toISOString();
  let msg = ts + path + method;
  if (body) msg += await sha256b64(body);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.YELLOWCARD_SECRET ?? ""), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg)));
  return { "X-YC-Timestamp": ts, Authorization: `YcHmacV1 ${env.YELLOWCARD_API_KEY}:${btoa(String.fromCharCode(...sig))}` };
}

async function yc<T>(env: Env, method: string, path: string, body?: unknown): Promise<T> {
  if (!env.YELLOWCARD_API_KEY || !env.YELLOWCARD_SECRET) throw new HttpError(503, "Off-ramp not configured");
  const raw = body ? JSON.stringify(body) : undefined;
  const res = await fetch(env.YELLOWCARD_BASE + path, {
    method, body: raw, headers: { "Content-Type": "application/json", ...(await sign(env, method, path, raw)) },
  });
  const j = (await res.json().catch(() => ({}))) as T & { message?: string };
  if (!res.ok) throw new HttpError(502, `Yellow Card: ${(j as { message?: string }).message ?? res.status}`);
  return j;
}

export type Dest = { accountNumber: string; accountName: string; bankName: string; bankCode: string; currency: "NGN" | "GHS"; kind: "bank" | "momo" };

/** Creates a disbursement. Yellow Card debits the partner's pre-funded USDC settlement balance (treasury top-up is an ops task). */
export async function disburse(env: Env, a: { amountUsd: number; dest: Dest; sequenceId: string; reason: string }) {
  const channels = await yc<{ channels: { id: string; currency: string; channelType: string; status: string }[] }>(env, "GET", "/business/channels");
  const ch = channels.channels.find((c) => c.currency === a.dest.currency && c.status === "active" &&
    (a.dest.kind === "momo" ? c.channelType === "momo" : c.channelType === "bank"));
  if (!ch) throw new HttpError(502, `No ${a.dest.currency} ${a.dest.kind} channel available`);
  return yc<{ id: string; status: string }>(env, "POST", "/business/payments", {
    channelId: ch.id,
    sequenceId: a.sequenceId,
    amount: a.amountUsd,
    reason: a.reason,
    forceAccept: true,
    destination: {
      accountNumber: a.dest.accountNumber, accountType: a.dest.kind === "momo" ? "momo" : "bank",
      networkName: a.dest.bankName, accountName: a.dest.accountName, bankCode: a.dest.bankCode,
    },
  });
}
