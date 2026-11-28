/** Enquiries, inbox and unread counts. Run: rm -rf .wrangler && npx wrangler d1 migrations apply kontena --local && npx tsx test/inbox.ts */
import { getPlatformProxy } from "wrangler";
import * as o from "../src/lib/orders";
import { postMessage } from "../src/lib/messages";
import { getConversation, inboxList, listInquiry, markRead, postInquiry, startConversation, unreadTotal } from "../src/lib/inbox";
import { uid } from "../src/lib/util";

const { env } = await getPlatformProxy<any>();
const E = { ...env, PLATFORM_FEE_PERCENT: "1.5", DEPOSIT_PERCENT: "30", USD_NGN: "1500", USD_GHS: "15", PAYSTACK_SECRET_KEY: "x", FOSSAPAY_API_KEY: "x" };
const db: D1Database = E.DB;
let fails = 0;
const eq = (n: string, a: unknown, b: unknown) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) fails++; console.log(ok ? "PASS" : "FAIL", n, ok ? "" : `got ${JSON.stringify(a)} want ${JSON.stringify(b)}`); };
const rejects = async (f: () => Promise<unknown>) => { try { await f(); return false; } catch { return true; } };

const t = Math.floor(Date.now() / 1000);
const [buyer, vend, other, store, prod, prod2, otherStore, otherProd] = [uid(), uid(), uid(), uid(), uid(), uid(), uid(), uid()];
for (const [id, role, name] of [[buyer, "customer", "Ada"], [vend, "vendor", "Vee"], [other, "vendor", "Oz"]] as const)
  await db.prepare("INSERT INTO users (id,email,name,role,created_at) VALUES (?,?,?,?,?)").bind(id, id + "@t.co", name, role, t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store, vend, "s" + store.slice(0, 6), "Lagos Bags", t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(otherStore, other, "s" + otherStore.slice(0, 6), "Other", t).run();
for (const [id, s, n] of [[prod, store, "Bags"], [prod2, store, "Shoes"], [otherProd, otherStore, "Hats"]])
  await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(id, s, n, 1000, 1, 14, t).run();
const U = async (id: string) => (await db.prepare("SELECT * FROM users WHERE id=?").bind(id).first<any>())!;
const [B, V, X] = [await U(buyer), await U(vend), await U(other)];

// opening a conversation
const c1 = await startConversation(E, B, store);
eq("same customer + store gives the same thread", await startConversation(E, B, store), c1);
eq("cannot message your own store", await rejects(() => startConversation(E, V, store)), true);
eq("unknown store refused", await rejects(() => startConversation(E, B, uid())), true);
const conv = await getConversation(E, c1, B);
eq("a stranger cannot open the thread", await rejects(() => getConversation(E, c1, X)), true);
eq("the supplier can", (await getConversation(E, c1, V)).id, c1);

// enquiry chat, with a product card and a video from the supplier
await postInquiry(E, conv, B, { body: "  Do you have 50 of these in black?  ", productId: prod });
await postInquiry(E, conv, V, { body: "Yes. Here is a video.", mediaKey: `${vend}/${uid()}.mp4` });
await postInquiry(E, conv, V, { productId: prod2 });
const asBuyer = await listInquiry(E, conv, B);
eq("3 messages with roles", asBuyer.messages.map((m) => m.role), ["buyer", "supplier", "supplier"]);
eq("body trimmed, product card attached", [asBuyer.messages[0].body, asBuyer.messages[0].product?.name], ["Do you have 50 of these in black?", "Bags"]);
eq("video recognised, own flag", [asBuyer.messages[1].isVideo, asBuyer.messages[0].mine, asBuyer.messages[1].mine], [true, true, false]);
eq("product-only message accepted", asBuyer.messages[2].product?.name, "Shoes");
eq("header names the store", (asBuyer.conversation.store as any).name, "Lagos Bags");
eq("cannot share another store's product", await rejects(() => postInquiry(E, conv, B, { productId: otherProd })), true);
eq("cannot attach someone else's file", await rejects(() => postInquiry(E, conv, B, { body: "x", mediaKey: `${vend}/x.jpg` })), true);
eq("empty message refused", await rejects(() => postInquiry(E, conv, B, { body: "  " })), true);
const n = await db.prepare("SELECT user_id FROM notifications WHERE user_id IN (?,?)").bind(buyer, vend).all<{ user_id: string }>();
eq("other side notified, not the sender", [n.results.some((r) => r.user_id === vend), n.results.some((r) => r.user_id === buyer)], [true, true]);

// unread + inbox: the buyer read the thread above, then the supplier wrote again
await postInquiry(E, conv, V, { body: "Any other colour?" });
eq("buyer has 1 unread", await unreadTotal(E, B), 1);
eq("supplier has none (replying marks the thread read)", await unreadTotal(E, V), 0);

// an order chat in the same inbox
const order = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 2 }] });
await postMessage(E, order, V, { body: "Order confirmed." });
await postMessage(E, order, V, { body: "Packing tomorrow." });
eq("buyer unread now 3 (1 enquiry + 2 order)", await unreadTotal(E, B), 3);
const inbB = await inboxList(E, B);
eq("buyer inbox: two threads, order first (newest)", inbB.threads.map((x) => [x.kind, x.unread]), [["order", 2], ["inquiry", 1]]);
eq("buyer sees the store name, vendor sees the customer", [inbB.threads[1].title, (await inboxList(E, V)).threads[1].title], ["Lagos Bags", "Ada"]);
eq("previews", [inbB.threads[0].preview, inbB.threads[1].preview], ["Packing tomorrow.", "Any other colour?"]);
eq("total matches", inbB.unread, 3);
await markRead(E, B, "order", order.id);
eq("marking the order thread read drops 2", await unreadTotal(E, B), 1);
await listInquiry(E, conv, B);
eq("opening the enquiry clears the rest", await unreadTotal(E, B), 0);
await postMessage(E, order, B, { body: "Thanks!" });
const inbV = await inboxList(E, V);
eq("supplier gets the buyer's reply as unread, own messages never count", [inbV.threads[0].unread, inbV.threads[0].mine], [1, false]);
eq("a stranger's inbox is empty", (await inboxList(E, X)).threads.length, 0);

// spam guard
let blocked = false;
for (let i = 0; i < 25; i++) { try { await postInquiry(E, conv, B, { body: "spam " + i }); } catch { blocked = true; break; } }
eq("more than 20 messages a minute is refused", blocked, true);

console.log(fails ? `${fails} FAILED` : "ALL PASSED");
process.exit(fails ? 1 : 0);
