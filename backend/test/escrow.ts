import { getPlatformProxy } from "wrangler";
import * as o from "../src/lib/orders";
import { uid } from "../src/lib/util";

const { env } = await getPlatformProxy<any>();
const E = { ...env, PLATFORM_FEE_PERCENT: "1.5", DEPOSIT_PERCENT: "30", USD_NGN: "1500", USD_GHS: "15", PAYSTACK_SECRET_KEY: "x", FOSSAPAY_API_KEY: "x", PLATFORM_FOSSA_CUSTOMER_ID: "c", PLATFORM_STELLAR_ADDRESS: "G" + "A".repeat(55) };
const db: D1Database = E.DB;
let fails = 0;
const eq = (n: string, a: unknown, b: unknown) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) fails++; console.log(ok ? "PASS" : "FAIL", n, ok ? "" : `got ${JSON.stringify(a)} want ${JSON.stringify(b)}`); };

const t = Math.floor(Date.now() / 1000);
const [buyer, vend, store, prod] = [uid(), uid(), uid(), uid()];
for (const [id, role] of [[buyer, "customer"], [vend, "vendor"]]) await db.prepare("INSERT INTO users (id,email,role,created_at) VALUES (?,?,?,?)").bind(id, id + "@t.co", role, t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store, vend, "s" + store.slice(0, 6), "Test", t).run();
await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(prod, store, "Widgets", 1000, 10, 14, t).run();

// happy path
let ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 100 }] });
eq("subtotal", ord.subtotal_cents, 100000);
eq("fee 1.5%", ord.fee_cents, 1500);
eq("deposit 30%", ord.deposit_cents, 30000);
eq("balance 70%", ord.balance_cents, 70000);
await o.markFunded(E, ord.id, "test"); await o.markFunded(E, ord.id, "test again");
eq("funded once", (await o.getOrder(E, ord.id))!.status, "funded");
await o.vendorAccept(E, (await o.getOrder(E, ord.id))!);
eq("deposit credited", await o.availableCents(E, vend), 30000);
eq("balance locked", await o.lockedCents(E, vend), 70000);
let threw = false; try { await o.vendorAccept(E, (await o.getOrder(E, ord.id))!); } catch { threw = true; }
eq("double accept blocked", threw, true);
await o.vendorReady(E, (await o.getOrder(E, ord.id))!, ["k1"], "ready");
await o.inspectionResult(E, (await o.getOrder(E, ord.id))!, true, "");
eq("balance released", await o.availableCents(E, vend), 100000);
threw = false; try { await o.inspectionResult(E, (await o.getOrder(E, ord.id))!, true, ""); } catch { threw = true; }
eq("double release blocked", await o.availableCents(E, vend), 100000);
await o.confirmDelivery(E, (await o.getOrder(E, ord.id))!);
eq("delivered", (await o.getOrder(E, ord.id))!.status, "delivered");

// withdraw guards (provider calls fail offline, funds must be reversed)
try { await o.withdraw(E, vend, { method: "usdc", amountCents: 200000, address: "G" + "A".repeat(55) }); } catch (e) { /* expected */ }
eq("overdraw blocked", await o.availableCents(E, vend), 100000);
try { await o.withdraw(E, vend, { method: "usdc", amountCents: 50000, address: "G" + "A".repeat(55) }); } catch (e) { /* provider offline */ }
eq("failed withdrawal reversed", await o.availableCents(E, vend), 100000);

// failed inspection: vendor keeps deposit only
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await o.markFunded(E, ord.id, "t"); await o.vendorAccept(E, (await o.getOrder(E, ord.id))!);
await o.vendorReady(E, (await o.getOrder(E, ord.id))!, ["k"], "");
await o.inspectionResult(E, (await o.getOrder(E, ord.id))!, false, "damaged");
eq("failed -> refunded", (await o.getOrder(E, ord.id))!.status, "refunded");
eq("vendor keeps deposit only", await o.availableCents(E, vend), 100000 + 3000);

// missed accept deadline
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await o.markFunded(E, ord.id, "t");
await db.prepare("UPDATE orders SET accept_by=1 WHERE id=?").bind(ord.id).run();
await o.sweepDeadlines(E);
eq("accept deadline -> refunded", (await o.getOrder(E, ord.id))!.status, "refunded");

// min qty
threw = false; try { await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 3 }] }); } catch { threw = true; }
eq("min qty enforced", threw, true);
// revenue
const rev = async (k: string) => (await db.prepare("SELECT COALESCE(SUM(amount_cents),0) s FROM platform_revenue WHERE kind=?").bind(k).first<{ s: number }>())!.s;
eq("protection fee booked at accept (2 orders accepted)", await rev("protection_fee"), 1500 + 150);
eq("no commission by default", await rev("seller_commission"), 0);
const E2 = { ...E, SELLER_COMMISSION_PERCENT: "2" };
ord = await o.createOrder(E2, buyer, { storeId: store, items: [{ productId: prod, qty: 100 }] });
await o.markFunded(E2, ord.id, "t"); await o.vendorAccept(E2, (await o.getOrder(E2, ord.id))!);
const before = await o.availableCents(E2, vend);
await o.vendorReady(E2, (await o.getOrder(E2, ord.id))!, ["k"], "");
await o.inspectionResult(E2, (await o.getOrder(E2, ord.id))!, true, "");
eq("2% commission booked", await rev("seller_commission"), 2000);
eq("supplier receives balance minus commission", (await o.availableCents(E2, vend)) - before, 70000 - 2000);
eq("fee only recognised once per order", await rev("protection_fee"), 1500 + 150 + 1500);
console.log(fails ? `${fails} FAILED` : "ALL PASSED");
process.exit(fails ? 1 : 0);
