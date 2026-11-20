import { SignJWT, importPKCS8 } from "jose";
import type { Env } from "./env";
import { now, uid } from "./util";

let cached: { token: string; exp: number } | null = null;

async function accessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256" }).setIssuer(sa.client_email).setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token").setIssuedAt().setExpirationTime("55m").sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = (await res.json()) as { access_token: string; expires_in: number };
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return j.access_token;
}

/** Writes an in-app notification and, if FCM is configured, pushes it to the user's devices. Never throws. */
export async function notify(env: Env, userId: string, title: string, body: string, orderId?: string) {
  try {
    await env.DB.prepare("INSERT INTO notifications (id,user_id,title,body,order_id,created_at) VALUES (?,?,?,?,?,?)")
      .bind(uid(), userId, title, body, orderId ?? null, now()).run();
    if (!env.FCM_SERVICE_ACCOUNT_JSON) return;
    const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);
    const { results } = await env.DB.prepare("SELECT token FROM device_tokens WHERE user_id=?").bind(userId).all<{ token: string }>();
    if (!results.length) return;
    const at = await accessToken(sa);
    await Promise.all(results.map(async ({ token }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST", headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token, notification: { title, body }, data: orderId ? { orderId } : {} } }),
      });
      if (res.status === 404) await env.DB.prepare("DELETE FROM device_tokens WHERE token=?").bind(token).run();
    }));
  } catch (e) {
    console.error("notify failed", e);
  }
}
