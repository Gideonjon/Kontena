/** Per-order chat between the buyer, the supplier and Kontena's inspector, plus the supplier's proof rules. */
import type { Env, User } from "./env";
import { bad, now, uid } from "./util";
import { getOrder, type Order } from "./orders";
import { notify } from "./fcm";
import { isAdmin } from "./auth";

const VIDEO_EXT = /\.(mp4|mov|webm)$/i;
export const isVideoKey = (k: string) => VIDEO_EXT.test(k);

/** Suppliers must show the goods properly before inspection: several photos and at least one video. */
export function checkProof(env: Env, keys: string[]) {
  const videos = keys.filter(isVideoKey).length;
  const photos = keys.length - videos;
  const minPhotos = Number(env.PROOF_MIN_PHOTOS ?? 3), minVideos = Number(env.PROOF_MIN_VIDEOS ?? 1);
  if (photos < minPhotos || videos < minVideos) {
    const parts = [photos < minPhotos ? `${minPhotos} photos` : "", videos < minVideos ? `${minVideos} video` : ""].filter(Boolean);
    throw bad(`Add at least ${minPhotos} photos and ${minVideos} video of the goods (still needed: ${parts.join(" and ")})`);
  }
}

const roleOf = (env: Env, o: Order, u: User): "buyer" | "supplier" | "kontena" =>
  isAdmin(env, u) ? "kontena" : o.buyer_id === u.id ? "buyer" : "supplier";

export async function listMessages(env: Env, o: Order, me: User) {
  const { results } = await env.DB.prepare("SELECT id,sender_id,body,media_key,created_at FROM order_messages WHERE order_id=? ORDER BY created_at, rowid LIMIT 300")
    .bind(o.id).all<{ id: string; sender_id: string; body: string; media_key: string | null; created_at: number }>();
  const senders = new Map<string, string>();
  const out = [];
  for (const m of results) {
    if (!senders.has(m.sender_id)) {
      const su = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(m.sender_id).first<User>();
      senders.set(m.sender_id, su ? roleOf(env, o, su) : "buyer");
    }
    out.push({ id: m.id, body: m.body, mediaKey: m.media_key, isVideo: !!m.media_key && isVideoKey(m.media_key), at: m.created_at, role: senders.get(m.sender_id), mine: m.sender_id === me.id });
  }
  return out;
}

export async function postMessage(env: Env, o: Order, me: User, a: { body?: string; mediaKey?: string }) {
  const body = (a.body ?? "").trim().slice(0, 2000);
  const mediaKey = a.mediaKey || null;
  if (!body && !mediaKey) throw bad("Write a message or attach a photo or video");
  if (mediaKey && !mediaKey.startsWith(`${me.id}/`)) throw bad("You can only attach files you uploaded");
  await env.DB.prepare("INSERT INTO order_messages (id,order_id,sender_id,body,media_key,created_at) VALUES (?,?,?,?,?,?)")
    .bind(uid(), o.id, me.id, body, mediaKey, now()).run();
  const who = roleOf(env, o, me);
  const label = who === "kontena" ? "Kontena" : who === "buyer" ? "The buyer" : "The supplier";
  const preview = body ? body.slice(0, 80) : "sent a file";
  for (const to of new Set([o.buyer_id, o.vendor_id])) if (to !== me.id) await notify(env, to, `New message on ${o.ref}`, `${label}: ${preview}`, o.id);
  return { ok: true };
}

export { getOrder };
