import type { Env } from "./env";

export const now = () => Math.floor(Date.now() / 1000);
export const uid = () => crypto.randomUUID();

export function orderRef(): string {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const b = crypto.getRandomValues(new Uint8Array(6));
  return "KT-" + Array.from(b, (x) => a[x % a.length]).join("");
}

export function slugify(s: string): string {
  return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "store";
}

export const pct = (cents: number, p: number) => Math.round((cents * p) / 100);

export function fxRate(env: Env, currency: "NGN" | "GHS"): number {
  return Number(currency === "NGN" ? env.USD_NGN : env.USD_GHS);
}

/** USD cents -> minor units of a local currency (kobo / pesewas), with 1.5% FX spread for the customer. */
export function usdToMinor(env: Env, cents: number, currency: "NGN" | "GHS"): number {
  return Math.ceil(cents * fxRate(env, currency) * 1.015);
}

export function currencyFor(country: string): "NGN" | "GHS" {
  return country === "GH" ? "GHS" : "NGN";
}

export async function hmacHex(algo: "SHA-256" | "SHA-512", secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: algo }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return Array.from(new Uint8Array(sig), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export const bad = (m: string) => new HttpError(400, m);
export const forbidden = (m = "Not allowed") => new HttpError(403, m);
export const notFound = (m = "Not found") => new HttpError(404, m);
