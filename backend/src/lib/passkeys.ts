/**
 * Passkeys (WebAuthn): users confirm money actions with their fingerprint or face instead of a password or a
 * seed phrase. Their Stellar wallet stays custodial, so there is nothing to back up.
 *
 * Flow: the app asks for options, the device signs with the passkey, the server verifies it and hands back a
 * short-lived confirmation token. Money endpoints then require that token (X-Passkey-Token) for anyone who has
 * set up a passkey.
 */
import {
  generateAuthenticationOptions, generateRegistrationOptions, verifyAuthenticationResponse, verifyRegistrationResponse,
  type AuthenticationResponseJSON, type RegistrationResponseJSON, type AuthenticatorTransportFuture,
} from "@simplewebauthn/server";
import type { Env, User } from "./env";
import { bad, forbidden, hmacHex, now } from "./util";

const TOKEN_TTL = 180;

const b64u = {
  enc: (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""),
  dec: (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0)),
};

const secret = (env: Env) => env.PASSKEY_SECRET ?? `pk:${env.PAYSTACK_SECRET_KEY}`;

/** The passkey belongs to the site the app is opened on, so rpID and origin follow the request's Origin. */
export function rp(env: Env, origin: string | undefined) {
  const allowed = [env.SITE_URL, env.APP_URL, "https://usekontena.web.app", "https://www.kontena.store"].map((u) => new URL(u).origin);
  const o = origin && (allowed.includes(origin) || /^http:\/\/localhost:\d+$/.test(origin)) ? origin : new URL(env.SITE_URL).origin;
  const host = new URL(o).hostname;
  return { origin: o, rpID: env.PASSKEY_RP_ID && host.endsWith(env.PASSKEY_RP_ID) ? env.PASSKEY_RP_ID : host };
}

async function saveChallenge(env: Env, userId: string, challenge: string, kind: string) {
  await env.DB.prepare("INSERT INTO passkey_challenges (user_id,challenge,kind,expires_at) VALUES (?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET challenge=excluded.challenge, kind=excluded.kind, expires_at=excluded.expires_at")
    .bind(userId, challenge, kind, now() + 300).run();
}
async function takeChallenge(env: Env, userId: string, kind: string): Promise<string> {
  const r = await env.DB.prepare("DELETE FROM passkey_challenges WHERE user_id=? AND kind=? RETURNING challenge, expires_at").bind(userId, kind).first<{ challenge: string; expires_at: number }>();
  if (!r || r.expires_at < now()) throw bad("Passkey request expired. Try again.");
  return r.challenge;
}

type Row = { id: string; public_key: string; counter: number; transports: string | null };
const list = async (env: Env, userId: string) =>
  (await env.DB.prepare("SELECT id,public_key,counter,transports FROM passkeys WHERE user_id=?").bind(userId).all<Row>()).results;

export const hasPasskey = async (env: Env, userId: string) => !!(await env.DB.prepare("SELECT 1 FROM passkeys WHERE user_id=? LIMIT 1").bind(userId).first());

export async function registrationOptions(env: Env, u: User, origin?: string) {
  const { rpID } = rp(env, origin);
  const opts = await generateRegistrationOptions({
    rpName: "Kontena", rpID, userName: u.email || u.id, userDisplayName: u.name || u.email, userID: Uint8Array.from(new TextEncoder().encode(u.id)),
    attestationType: "none",
    excludeCredentials: (await list(env, u.id)).map((k) => ({ id: k.id, transports: k.transports ? (JSON.parse(k.transports) as AuthenticatorTransportFuture[]) : undefined })),
    authenticatorSelection: { residentKey: "preferred", userVerification: "required" },
  });
  await saveChallenge(env, u.id, opts.challenge, "register");
  return opts;
}

export async function registerVerify(env: Env, u: User, response: RegistrationResponseJSON, label: string, origin?: string) {
  const { origin: expectedOrigin, rpID } = rp(env, origin);
  const v = await verifyRegistrationResponse({ response, expectedChallenge: await takeChallenge(env, u.id, "register"), expectedOrigin, expectedRPID: rpID, requireUserVerification: true });
  if (!v.verified || !v.registrationInfo) throw bad("Passkey could not be verified");
  const cred = v.registrationInfo.credential;
  await env.DB.prepare("INSERT INTO passkeys (id,user_id,public_key,counter,transports,label,created_at) VALUES (?,?,?,?,?,?,?)")
    .bind(cred.id, u.id, b64u.enc(cred.publicKey), cred.counter, JSON.stringify(cred.transports ?? []), label.slice(0, 60) || "This device", now()).run();
  return { ok: true };
}

export async function authOptions(env: Env, u: User, origin?: string) {
  const keys = await list(env, u.id);
  if (!keys.length) throw bad("Set up fingerprint or face confirmation first");
  const opts = await generateAuthenticationOptions({
    rpID: rp(env, origin).rpID, userVerification: "required",
    allowCredentials: keys.map((k) => ({ id: k.id, transports: k.transports ? (JSON.parse(k.transports) as AuthenticatorTransportFuture[]) : undefined })),
  });
  await saveChallenge(env, u.id, opts.challenge, "auth");
  return opts;
}

/** Verifies a fingerprint/face confirmation and returns a token valid for a few minutes. */
export async function authVerify(env: Env, u: User, response: AuthenticationResponseJSON, origin?: string) {
  const key = await env.DB.prepare("SELECT id,public_key,counter,transports FROM passkeys WHERE id=? AND user_id=?").bind(response.id, u.id).first<Row>();
  if (!key) throw bad("Unknown passkey");
  const { origin: expectedOrigin, rpID } = rp(env, origin);
  const v = await verifyAuthenticationResponse({
    response, expectedChallenge: await takeChallenge(env, u.id, "auth"), expectedOrigin, expectedRPID: rpID, requireUserVerification: true,
    credential: { id: key.id, publicKey: b64u.dec(key.public_key), counter: key.counter, transports: key.transports ? JSON.parse(key.transports) : undefined },
  });
  if (!v.verified) throw bad("Fingerprint confirmation failed");
  await env.DB.prepare("UPDATE passkeys SET counter=?, last_used_at=? WHERE id=?").bind(v.authenticationInfo.newCounter, now(), key.id).run();
  const exp = now() + TOKEN_TTL;
  return { token: `${u.id}.${exp}.${await hmacHex("SHA-256", secret(env), `${u.id}.${exp}`)}`, expiresIn: TOKEN_TTL };
}

/** For money endpoints: if the user has a passkey, a fresh confirmation token is required. */
export async function requirePasskeyIfEnrolled(env: Env, userId: string, token: string | undefined, _action: string) {
  if ((env.PASSKEY_MODE ?? "required") !== "required") return;
  if (!(await hasPasskey(env, userId))) return;
  const [uid, exp, sig] = (token ?? "").split(".");
  if (uid !== userId || !exp || Number(exp) < now() || sig !== (await hmacHex("SHA-256", secret(env), `${uid}.${exp}`)))
    throw forbidden("PASSKEY_REQUIRED");
}

export async function removePasskeys(env: Env, userId: string) {
  await env.DB.prepare("DELETE FROM passkeys WHERE user_id=?").bind(userId).run();
}
