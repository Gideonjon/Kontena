import { Hono } from "hono";
import type { App } from "./types";
import { fxRate, notFound } from "../lib/util";

export const pub = new Hono<App>();

pub.get("/health", (c) => c.json({ ok: true }));

pub.get("/fx", (c) => c.json({ USD_NGN: fxRate(c.env, "NGN"), USD_GHS: fxRate(c.env, "GHS"), spreadPercent: 1.5 }));

const storeCols = "s.id, s.slug, s.name, s.bio, s.country, s.city, s.logo_key, s.cover_key, s.verified";

pub.get("/stores", async (c) => {
  const q = (c.req.query("q") ?? "").trim();
  const country = c.req.query("country");
  const where = ["s.active=1"];
  const args: (string | number)[] = [];
  if (q) { where.push("(s.name LIKE ? OR s.bio LIKE ?)"); args.push(`%${q}%`, `%${q}%`); }
  if (country) { where.push("s.country=?"); args.push(country); }
  const { results } = await c.env.DB.prepare(
    `SELECT ${storeCols}, (SELECT COUNT(*) FROM products p WHERE p.store_id=s.id AND p.active=1) AS product_count
     FROM stores s WHERE ${where.join(" AND ")} ORDER BY s.verified DESC, s.created_at DESC LIMIT 50`,
  ).bind(...args).all();
  return c.json({ stores: results });
});

pub.get("/stores/:slug", async (c) => {
  const store = await c.env.DB.prepare(`SELECT ${storeCols} FROM stores s WHERE s.slug=? AND s.active=1`).bind(c.req.param("slug")).first();
  if (!store) throw notFound("Store not found");
  const { results: products } = await c.env.DB.prepare("SELECT id,name,description,price_cents,min_qty,lead_days,image_key FROM products WHERE store_id=? AND active=1 ORDER BY created_at DESC")
    .bind(store.id as string).all();
  const { results: pools } = await c.env.DB.prepare(
    `SELECT pl.id, pl.product_id, pl.target_qty, pl.ends_at,
       COALESCE((SELECT SUM(oi.qty) FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE o.pool_id=pl.id AND o.status!='cancelled' AND o.status!='refunded'),0) AS joined_qty,
       (SELECT COUNT(*) FROM orders o WHERE o.pool_id=pl.id AND o.status!='cancelled') AS members
     FROM pools pl WHERE pl.store_id=? AND pl.status='open' AND pl.ends_at>unixepoch()`,
  ).bind(store.id as string).all();
  return c.json({ store, products, pools });
});

pub.get("/media/*", async (c) => {
  const key = c.req.path.replace(/^\/media\//, "");
  const obj = await c.env.MEDIA.get(key);
  if (!obj) throw notFound();
  return new Response(obj.body, {
    headers: { "Content-Type": obj.httpMetadata?.contentType ?? "application/octet-stream", "Cache-Control": "public, max-age=31536000, immutable" },
  });
});

/** Share link: kontena.app/s/:slug. Crawlers get OG tags, people get sent to the app. */
pub.get("/s/:slug", async (c) => {
  const slug = c.req.param("slug");
  const s = await c.env.DB.prepare("SELECT name,bio,logo_key FROM stores WHERE slug=? AND active=1").bind(slug).first<{ name: string; bio: string; logo_key: string | null }>();
  if (!s) return c.redirect(c.env.SITE_URL, 302);
  const esc = (x: string) => x.replace(/[&<>"]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[m]!);
  const target = `${c.env.APP_URL}/s/${encodeURIComponent(slug)}`;
  const img = s.logo_key ? `${new URL(c.req.url).origin}/media/${s.logo_key}` : "";
  return c.html(`<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${esc(s.name)} on Kontena</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta property="og:title" content="${esc(s.name)} · Shop safely on Kontena"><meta property="og:description" content="${esc(s.bio || "Pay into escrow. Money is released only after your goods are inspected.")}">
<link rel="icon" href="${c.env.SITE_URL}/favicon.png"><link rel="apple-touch-icon" href="${c.env.SITE_URL}/icons/Icon-192.png"><meta name="theme-color" content="#FF5B14">
<meta property="og:image" content="${esc(img || `${c.env.SITE_URL}/icons/Icon-512.png`)}"><meta name="twitter:card" content="summary">
<meta http-equiv="refresh" content="0;url=${esc(target)}"></head><body><a href="${esc(target)}">Open ${esc(s.name)}</a></body></html>`);
});
