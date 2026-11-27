import { Hono } from "hono";
import type { App } from "./types";
import { bad, forbidden, notFound, now, slugify, uid } from "../lib/util";
import { getOrder, vendorAccept, vendorReady } from "../lib/orders";
import { checkProof } from "../lib/messages";

export const vendor = new Hono<App>();

async function myStore(c: { env: App["Bindings"]; get: (k: "user") => App["Variables"]["user"] }) {
  const s = await c.env.DB.prepare("SELECT * FROM stores WHERE owner_id=?").bind(c.get("user").id).first<{ id: string; slug: string }>();
  if (!s) throw notFound("Create your store first");
  return s;
}

vendor.post("/store", async (c) => {
  const u = c.get("user");
  const b = await c.req.json<{ name: string; bio?: string; city?: string; logoKey?: string; coverKey?: string; slug?: string }>();
  if (!b.name?.trim()) throw bad("Store name required");
  if (await c.env.DB.prepare("SELECT 1 FROM stores WHERE owner_id=?").bind(u.id).first()) throw bad("You already have a store");
  const base = slugify(b.slug || b.name);
  let slug = base;
  for (let i = 2; await c.env.DB.prepare("SELECT 1 FROM stores WHERE slug=?").bind(slug).first(); i++) slug = `${base}-${i}`;
  const id = uid();
  await c.env.DB.batch([
    c.env.DB.prepare("INSERT INTO stores (id,owner_id,slug,name,bio,country,city,logo_key,cover_key,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
      .bind(id, u.id, slug, b.name.trim(), b.bio ?? "", u.country, b.city ?? u.city ?? "", b.logoKey ?? null, b.coverKey ?? null, now()),
    c.env.DB.prepare("UPDATE users SET role='vendor' WHERE id=? AND role!='admin'").bind(u.id),
  ]);
  return c.json({ id, slug, link: `${c.env.SITE_URL}/s/${slug}` });
});

vendor.get("/store", async (c) => {
  const s = await myStore(c);
  const full = await c.env.DB.prepare("SELECT id,slug,name,bio,country,city,logo_key,cover_key,verified FROM stores WHERE id=?").bind(s.id).first();
  const { results: products } = await c.env.DB.prepare("SELECT * FROM products WHERE store_id=? ORDER BY created_at DESC").bind(s.id).all();
  return c.json({ store: full, link: `${c.env.SITE_URL}/s/${s.slug}`, products });
});

vendor.patch("/store", async (c) => {
  const s = await myStore(c);
  const b = await c.req.json<{ name?: string; bio?: string; city?: string; logoKey?: string; coverKey?: string }>();
  await c.env.DB.prepare("UPDATE stores SET name=COALESCE(?,name), bio=COALESCE(?,bio), city=COALESCE(?,city), logo_key=COALESCE(?,logo_key), cover_key=COALESCE(?,cover_key) WHERE id=?")
    .bind(b.name ?? null, b.bio ?? null, b.city ?? null, b.logoKey ?? null, b.coverKey ?? null, s.id).run();
  return c.json({ ok: true });
});

type ProductBody = { name: string; description?: string; priceUsd: number; minQty?: number; leadDays?: number; imageKey?: string; active?: boolean };

vendor.post("/products", async (c) => {
  const s = await myStore(c);
  const b = await c.req.json<ProductBody>();
  if (!b.name?.trim() || !(b.priceUsd > 0)) throw bad("Name and a price above $0 are required");
  const id = uid();
  await c.env.DB.prepare("INSERT INTO products (id,store_id,name,description,price_cents,min_qty,lead_days,image_key,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
    .bind(id, s.id, b.name.trim(), b.description ?? "", Math.round(b.priceUsd * 100), Math.max(1, b.minQty ?? 1), Math.max(1, b.leadDays ?? 21), b.imageKey ?? null, now()).run();
  return c.json({ id });
});

vendor.patch("/products/:id", async (c) => {
  const s = await myStore(c);
  const b = await c.req.json<Partial<ProductBody>>();
  const r = await c.env.DB.prepare(
    "UPDATE products SET name=COALESCE(?,name), description=COALESCE(?,description), price_cents=COALESCE(?,price_cents), min_qty=COALESCE(?,min_qty), lead_days=COALESCE(?,lead_days), image_key=COALESCE(?,image_key), active=COALESCE(?,active) WHERE id=? AND store_id=?",
  ).bind(b.name ?? null, b.description ?? null, b.priceUsd ? Math.round(b.priceUsd * 100) : null, b.minQty ?? null, b.leadDays ?? null, b.imageKey ?? null, b.active === undefined ? null : b.active ? 1 : 0, c.req.param("id"), s.id).run();
  if (!(r.meta.changes ?? 0)) throw notFound();
  return c.json({ ok: true });
});

vendor.post("/pools", async (c) => {
  const s = await myStore(c);
  const b = await c.req.json<{ productId: string; targetQty: number; days?: number }>();
  const p = await c.env.DB.prepare("SELECT 1 FROM products WHERE id=? AND store_id=?").bind(b.productId, s.id).first();
  if (!p) throw notFound("Product not found");
  if (!(b.targetQty > 1)) throw bad("Target quantity must be above 1");
  const id = uid();
  await c.env.DB.prepare("INSERT INTO pools (id,product_id,store_id,target_qty,ends_at,created_at) VALUES (?,?,?,?,?,?)")
    .bind(id, b.productId, s.id, b.targetQty, now() + (b.days ?? 14) * 86400, now()).run();
  return c.json({ id });
});

vendor.get("/orders", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT o.*, u.name AS buyer_name,
       (SELECT GROUP_CONCAT(oi.qty || '× ' || oi.name, ', ') FROM order_items oi WHERE oi.order_id=o.id) AS summary
     FROM orders o JOIN users u ON u.id=o.buyer_id
     WHERE o.vendor_id=? AND o.status!='awaiting_payment' ORDER BY o.created_at DESC LIMIT 100`,
  ).bind(c.get("user").id).all();
  return c.json({ orders: results });
});

async function mine(c: Parameters<typeof myStore>[0] & { req: { param: (k: string) => string } }) {
  const o = await getOrder(c.env, c.req.param("id"));
  if (!o) throw notFound();
  if (o.vendor_id !== c.get("user").id) throw forbidden();
  return o;
}

vendor.post("/orders/:id/accept", async (c) => { await vendorAccept(c.env, await mine(c)); return c.json({ ok: true }); });

vendor.post("/orders/:id/ready", async (c) => {
  const b = await c.req.json<{ proofKeys: string[]; note?: string }>();
  const o = await mine(c);
  checkProof(c.env, b.proofKeys ?? []);
  await vendorReady(c.env, o, b.proofKeys ?? [], b.note ?? "");
  return c.json({ ok: true });
});
