/** Proof rules (photos + video) and order chat. Run: rm -rf .wrangler && npx wrangler d1 migrations apply kontena --local && npx tsx test/messages.ts */
import { getPlatformProxy } from "wrangler";
import * as o from "../src/lib/orders";
import { checkProof, listMessages, postMessage } from "../src/lib/messages";
import { uid } from "../src/lib/util";

const { env } = await getPlatformProxy<any>();
const E = { ...env, PLATFORM_FEE_PERCENT: "1.5", DEPOSIT_PERCENT: "30", USD_NGN: "1500", USD_GHS: "15", PAYSTACK_SECRET_KEY: "x", FOSSAPAY_API_KEY: "x", ADMIN_UIDS: "admin1" };
const db: D1Database = E.DB;
let fails = 0;
const eq = (n: string, a: unknown, b: unknown) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) fails++; console.log(ok ? "PASS" : "FAIL", n, ok ? "" : `got ${JSON.stringify(a)} want ${JSON.stringify(b)}`); };
const throws = (f: () => unknown) => { try { f(); return false; } catch { return true; } };

// proof rules: default 3 photos + 1 video
eq("2 photos + video refused", throws(() => checkProof(E, ["a.jpg", "b.jpg", "c.mp4"])), true);
eq("3 photos, no video refused", throws(() => checkProof(E, ["a.jpg", "b.jpg", "c.png"])), true);
eq("3 photos + video accepted", throws(() => checkProof(E, ["a.jpg", "b.jpg", "c.webp", "d.mov"])), false);
eq("rules are configurable", throws(() => checkProof({ ...E, PROOF_MIN_PHOTOS: "1", PROOF_MIN_VIDEOS: "0" }, ["a.jpg"])), false);

// chat
const t = Math.floor(Date.now() / 1000);
const [buyer, vend, stranger, store, prod] = [uid(), uid(), uid(), uid(), uid()];
for (const [id, role] of [[buyer, "customer"], [vend, "vendor"], [stranger, "customer"], ["admin1", "admin"]] as const)
  await db.prepare("INSERT INTO users (id,email,role,created_at) VALUES (?,?,?,?)").bind(id, id + "@t.co", role, t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store, vend, "s" + store.slice(0, 6), "S", t).run();
await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(prod, store, "Bags", 1000, 1, 14, t).run();
const order = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 2 }] });
const U = async (id: string) => (await db.prepare("SELECT * FROM users WHERE id=?").bind(id).first<any>())!;
const [B, V, A] = [await U(buyer), await U(vend), await U("admin1")];

await postMessage(E, order, B, { body: "  When will it ship?  " });
await postMessage(E, order, V, { body: "Friday.", mediaKey: `${vend}/${uid()}.mp4` });
await postMessage(E, order, A, { body: "Inspector here." });
const asBuyer = await listMessages(E, order, B);
eq("3 messages in order", asBuyer.map((m) => m.role), ["buyer", "supplier", "kontena"]);
eq("body trimmed, own message flagged", [asBuyer[0].body, asBuyer[0].mine, asBuyer[1].mine], ["When will it ship?", true, false]);
eq("video attachment recognised", [asBuyer[1].isVideo, asBuyer[0].isVideo], [true, false]);
let threw = false; try { await postMessage(E, order, B, { body: "x", mediaKey: `${vend}/other.jpg` }); } catch { threw = true; }
eq("cannot attach someone else's file", threw, true);
threw = false; try { await postMessage(E, order, B, { body: "   " }); } catch { threw = true; }
eq("empty message refused", threw, true);
const n = await db.prepare("SELECT user_id, title FROM notifications WHERE order_id=? ORDER BY created_at, rowid").bind(order.id).all<{ user_id: string }>();
eq("other parties notified, never the sender", n.results.filter((r) => r.user_id === buyer).length > 0 && n.results.filter((r) => r.user_id === vend).length > 0, true);

console.log(fails ? `${fails} FAILED` : "ALL PASSED");
process.exit(fails ? 1 : 0);
