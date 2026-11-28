/** Messages tab: customer-to-supplier conversations before any order, one inbox across them and order chats, and unread tracking. */
import type { Env, User } from "./env";
import { bad, forbidden, notFound, now, uid } from "./util";
import { notify } from "./fcm";
import { isVideoKey } from "./messages";

type Conv = { id: string; store_id: string; buyer_id: string; vendor_id: string; created_at: number };

/** Finds or opens the conversation between this customer and a store. One thread per customer per store. */
export async function startConversation(env: Env, me: User, storeId: string): Promise<string> {
  const store = await env.DB.prepare("SELECT id,owner_id FROM stores WHERE id=? AND active=1").bind(storeId).first<{ id: string; owner_id: string }>();
  if (!store) throw notFound("Store not found");
  if (store.owner_id === me.id) throw bad("This is your own store");
  await env.DB.prepare("INSERT OR IGNORE INTO conversations (id,store_id,buyer_id,vendor_id,created_at) VALUES (?,?,?,?,?)")
    .bind(uid(), store.id, me.id, store.owner_id, now()).run();
  const row = await env.DB.prepare("SELECT id FROM conversations WHERE buyer_id=? AND store_id=?").bind(me.id, store.id).first<{ id: string }>();
  return row!.id;
}

export async function getConversation(env: Env, id: string, me: User): Promise<Conv> {
  const c = await env.DB.prepare("SELECT * FROM conversations WHERE id=?").bind(id).first<Conv>();
  if (!c) throw notFound("Conversation not found");
  if (c.buyer_id !== me.id && c.vendor_id !== me.id) throw forbidden();
  return c;
}

/** Marks a thread as read up to its newest message. */
export async function markRead(env: Env, me: User, kind: "order" | "inquiry", refId: string) {
  const [table, col] = kind === "order" ? ["order_messages", "order_id"] : ["inquiry_messages", "conversation_id"];
  await env.DB.prepare(
    `INSERT INTO message_reads (user_id,kind,ref_id,read_rowid) VALUES (?1,?2,?3,(SELECT COALESCE(MAX(rowid),0) FROM ${table} WHERE ${col}=?3))
     ON CONFLICT(user_id,kind,ref_id) DO UPDATE SET read_rowid=excluded.read_rowid`,
  ).bind(me.id, kind, refId).run();
}

export async function listInquiry(env: Env, c: Conv, me: User) {
  const { results } = await env.DB.prepare(
    `SELECT m.id,m.sender_id,m.body,m.media_key,m.created_at, p.id AS pid, p.name AS pname, p.price_cents AS pprice, p.image_key AS pimg
     FROM inquiry_messages m LEFT JOIN products p ON p.id=m.product_id
     WHERE m.conversation_id=? ORDER BY m.created_at, m.rowid LIMIT 300`,
  ).bind(c.id).all<{ id: string; sender_id: string; body: string; media_key: string | null; created_at: number; pid: string | null; pname: string | null; pprice: number | null; pimg: string | null }>();
  const store = await env.DB.prepare("SELECT id,slug,name,logo_key,verified FROM stores WHERE id=?").bind(c.store_id).first();
  const buyer = await env.DB.prepare("SELECT name FROM users WHERE id=?").bind(c.buyer_id).first<{ name: string }>();
  await markRead(env, me, "inquiry", c.id);
  return {
    conversation: { id: c.id, store, buyerName: buyer?.name ?? "", iAmBuyer: c.buyer_id === me.id },
    messages: results.map((m) => ({
      id: m.id, body: m.body, mediaKey: m.media_key, isVideo: !!m.media_key && isVideoKey(m.media_key), at: m.created_at,
      role: m.sender_id === c.buyer_id ? "buyer" : "supplier", mine: m.sender_id === me.id,
      product: m.pid ? { id: m.pid, name: m.pname, price_cents: m.pprice, image_key: m.pimg } : null,
    })),
  };
}

export async function postInquiry(env: Env, c: Conv, me: User, a: { body?: string; mediaKey?: string; productId?: string }) {
  const body = (a.body ?? "").trim().slice(0, 2000);
  const mediaKey = a.mediaKey || null;
  let productId: string | null = null;
  if (a.productId) {
    const p = await env.DB.prepare("SELECT id FROM products WHERE id=? AND store_id=? AND active=1").bind(a.productId, c.store_id).first<{ id: string }>();
    if (!p) throw bad("That product is not in this store");
    productId = p.id;
  }
  if (!body && !mediaKey && !productId) throw bad("Write a message or attach a photo, video or product");
  if (mediaKey && !mediaKey.startsWith(`${me.id}/`)) throw bad("You can only attach files you uploaded");
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM inquiry_messages WHERE sender_id=? AND created_at>?").bind(me.id, now() - 60).first<{ n: number }>();
  if ((recent?.n ?? 0) >= 20) throw bad("You're sending messages too fast. Wait a moment and try again.");
  await env.DB.prepare("INSERT INTO inquiry_messages (id,conversation_id,sender_id,body,media_key,product_id,created_at) VALUES (?,?,?,?,?,?,?)")
    .bind(uid(), c.id, me.id, body, mediaKey, productId, now()).run();
  const iAmBuyer = c.buyer_id === me.id;
  const store = await env.DB.prepare("SELECT name FROM stores WHERE id=?").bind(c.store_id).first<{ name: string }>();
  const preview = body ? body.slice(0, 80) : mediaKey ? (isVideoKey(mediaKey) ? "Sent a video" : "Sent a photo") : "Shared a product";
  await notify(env, iAmBuyer ? c.vendor_id : c.buyer_id, iAmBuyer ? `New enquiry for ${store?.name ?? "your store"}` : `${store?.name ?? "A supplier"} replied`, `${iAmBuyer ? (me.name || "A customer") + ": " : ""}${preview}`);
  await markRead(env, me, "inquiry", c.id);
  return { ok: true };
}

const lastPreview = (body: string, media: string | null, product: string | null) =>
  body ? body.slice(0, 80) : media ? (isVideoKey(media) ? "Sent a video" : "Sent a photo") : product ? "Shared a product" : "";

/** Every conversation the person is in, order chats and enquiries together, newest first, with unread counts. */
export async function inboxList(env: Env, me: User) {
  const [orderRows, inquiryRows] = await Promise.all([
    env.DB.prepare(
      `SELECT o.id, o.ref, o.status, o.buyer_id, s.name AS store_name, s.logo_key, bu.name AS buyer_name,
         m.body, m.media_key, m.created_at AS last_at, m.sender_id,
         (SELECT COUNT(*) FROM order_messages x WHERE x.order_id=o.id AND x.sender_id!=?1
            AND x.rowid > COALESCE((SELECT read_rowid FROM message_reads r WHERE r.user_id=?1 AND r.kind='order' AND r.ref_id=o.id),0)) AS unread
       FROM orders o JOIN stores s ON s.id=o.store_id JOIN users bu ON bu.id=o.buyer_id
       JOIN order_messages m ON m.rowid=(SELECT MAX(rowid) FROM order_messages WHERE order_id=o.id)
       WHERE o.buyer_id=?1 OR o.vendor_id=?1 ORDER BY last_at DESC LIMIT 100`,
    ).bind(me.id).all<{ id: string; ref: string; status: string; buyer_id: string; store_name: string; logo_key: string | null; buyer_name: string; body: string; media_key: string | null; last_at: number; sender_id: string; unread: number }>(),
    env.DB.prepare(
      `SELECT c.id, c.buyer_id, s.name AS store_name, s.slug, s.logo_key, bu.name AS buyer_name,
         m.body, m.media_key, m.product_id, m.created_at AS last_at, m.sender_id,
         (SELECT COUNT(*) FROM inquiry_messages x WHERE x.conversation_id=c.id AND x.sender_id!=?1
            AND x.rowid > COALESCE((SELECT read_rowid FROM message_reads r WHERE r.user_id=?1 AND r.kind='inquiry' AND r.ref_id=c.id),0)) AS unread
       FROM conversations c JOIN stores s ON s.id=c.store_id JOIN users bu ON bu.id=c.buyer_id
       JOIN inquiry_messages m ON m.rowid=(SELECT MAX(rowid) FROM inquiry_messages WHERE conversation_id=c.id)
       WHERE c.buyer_id=?1 OR c.vendor_id=?1 ORDER BY last_at DESC LIMIT 100`,
    ).bind(me.id).all<{ id: string; buyer_id: string; store_name: string; slug: string; logo_key: string | null; buyer_name: string; body: string; media_key: string | null; product_id: string | null; last_at: number; sender_id: string; unread: number }>(),
  ]);
  const threads = [
    ...orderRows.results.map((r) => ({
      kind: "order" as const, id: r.id, title: r.buyer_id === me.id ? r.store_name : r.buyer_name || "Customer", subtitle: `Order ${r.ref}`,
      logoKey: r.buyer_id === me.id ? r.logo_key : null, slug: null as string | null, preview: lastPreview(r.body, r.media_key, null), at: r.last_at, unread: r.unread, mine: r.sender_id === me.id,
    })),
    ...inquiryRows.results.map((r) => ({
      kind: "inquiry" as const, id: r.id, title: r.buyer_id === me.id ? r.store_name : r.buyer_name || "Customer", subtitle: "Enquiry",
      logoKey: r.buyer_id === me.id ? r.logo_key : null, slug: r.slug as string | null, preview: lastPreview(r.body, r.media_key, r.product_id), at: r.last_at, unread: r.unread, mine: r.sender_id === me.id,
    })),
  ].sort((a, b) => b.at - a.at);
  return { threads, unread: threads.reduce((n, t) => n + t.unread, 0) };
}

/** Cheap count for the tab badge. */
export async function unreadTotal(env: Env, me: User): Promise<number> {
  const [a, b] = await Promise.all([
    env.DB.prepare(
      `SELECT COUNT(*) AS n FROM order_messages x JOIN orders o ON o.id=x.order_id
       WHERE (o.buyer_id=?1 OR o.vendor_id=?1) AND x.sender_id!=?1
         AND x.rowid > COALESCE((SELECT read_rowid FROM message_reads r WHERE r.user_id=?1 AND r.kind='order' AND r.ref_id=o.id),0)`,
    ).bind(me.id).first<{ n: number }>(),
    env.DB.prepare(
      `SELECT COUNT(*) AS n FROM inquiry_messages x JOIN conversations c ON c.id=x.conversation_id
       WHERE (c.buyer_id=?1 OR c.vendor_id=?1) AND x.sender_id!=?1
         AND x.rowid > COALESCE((SELECT read_rowid FROM message_reads r WHERE r.user_id=?1 AND r.kind='inquiry' AND r.ref_id=c.id),0)`,
    ).bind(me.id).first<{ n: number }>(),
  ]);
  return (a?.n ?? 0) + (b?.n ?? 0);
}
