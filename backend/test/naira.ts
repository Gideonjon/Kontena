import { getPlatformProxy } from "wrangler";
import * as o from "../src/lib/orders";
import * as n from "../src/lib/naira";
import { uid } from "../src/lib/util";

const { env } = await getPlatformProxy<any>();
const E = { ...env, PLATFORM_FEE_PERCENT: "1.5", DEPOSIT_PERCENT: "30", USD_NGN: "1500", USD_GHS: "15", PAYSTACK_SECRET_KEY: "x", FOSSAPAY_API_KEY: "x", PLATFORM_FOSSA_CUSTOMER_ID: "c", PLATFORM_STELLAR_ADDRESS: "G" + "A".repeat(55) };
const db: D1Database = E.DB;
let fails = 0;
const eq = (name: string, a: unknown, b: unknown) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) fails++; console.log(ok ? "PASS" : "FAIL", name, ok ? "" : `got ${JSON.stringify(a)} want ${JSON.stringify(b)}`); };
const R1 = "ref-" + uid();
const t = Math.floor(Date.now() / 1000);
const [buyer, vend, store, prod] = [uid(), uid(), uid(), uid()];
for (const [id, role] of [[buyer, "customer"], [vend, "vendor"]]) await db.prepare("INSERT INTO users (id,email,role,created_at) VALUES (?,?,?,?)").bind(id, id + "@t.co", role, t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store, vend, "n" + store.slice(0, 6), "T", t).run();
await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(prod, store, "W", 1000, 1, 14, t).run();

// credits are idempotent
eq("credit once", await n.creditWallet(E, buyer, "topup", 50_000_000, R1, { silent: true }), true);
eq("credit twice is a no-op", await n.creditWallet(E, buyer, "topup", 50_000_000, R1, { silent: true }), false);
eq("balance", await n.walletBalance(E, buyer), 50_000_000);

// overdraw blocked
let threw = false; try { await n.debitWallet(E, buyer, "withdrawal", 90_000_000, "x1"); } catch { threw = true; }
eq("overdraw blocked", threw, true);
eq("balance untouched", await n.walletBalance(E, buyer), 50_000_000);

// pay an order from the wallet: $1000 + 1.5% fee at 1500 NGN/USD + 1.5% spread
let ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] }); // $100 + $1.50
const kobo = Math.ceil(ord.total_cents * 1500 * 1.015);
await o.startWalletPayment(E, ord, buyer, "NG");
eq("wallet debited", await n.walletBalance(E, buyer), 50_000_000 - kobo);
eq("order funded", (await o.getOrder(E, ord.id))!.status, "funded");
threw = false; try { await o.startWalletPayment(E, (await o.getOrder(E, ord.id))!, buyer, "NG"); } catch { threw = true; }
eq("cannot pay twice", threw, true);

// supplier misses the accept deadline -> full refund lands in the wallet
await db.prepare("UPDATE orders SET accept_by=? WHERE id=?").bind(t - 10, ord.id).run();
await o.sweepDeadlines(E);
eq("order refunded", (await o.getOrder(E, ord.id))!.status, "refunded");
eq("refund back in wallet", await n.walletBalance(E, buyer), 50_000_000);

// failed inspection refunds only the 70% balance, pro rata, into the wallet
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await o.startWalletPayment(E, ord, buyer, "NG");
await o.vendorAccept(E, (await o.getOrder(E, ord.id))!);
await o.vendorReady(E, (await o.getOrder(E, ord.id))!, ["k"], "");
const before = await n.walletBalance(E, buyer);
await o.inspectionResult(E, (await o.getOrder(E, ord.id))!, false, "bad");
const o2 = (await o.getOrder(E, ord.id))!;
eq("balance refund amount", (await n.walletBalance(E, buyer)) - before, Math.round((o2.pay_amount_minor! * o2.balance_cents) / o2.total_cents));

// card-paid NGN order refunds to wallet by default, to the card when the user opts out
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await db.prepare("UPDATE orders SET funding='paystack', pay_currency='NGN', pay_amount_minor=?, paystack_ref='P1' WHERE id=?").bind(1_500_000, ord.id).run();
await o.markFunded(E, ord.id, "t");
let b0 = await n.walletBalance(E, buyer);
await o.refundExternal(E, (await o.getOrder(E, ord.id))!, ord.total_cents);
eq("card order refunded to wallet", (await n.walletBalance(E, buyer)) - b0, 1_500_000);

// failed wallet withdrawal returns the money
const wid = uid(); await n.debitWallet(E, buyer, "withdrawal", 100_000, wid);
await db.prepare("INSERT INTO withdrawals (id,user_id,method,amount_cents,fiat_currency,fiat_minor,dest_json,status,created_at,updated_at) VALUES (?,?,'wallet_bank',0,'NGN',100000,'{}','processing',?,?)").bind(wid, buyer, t, t).run();
b0 = await n.walletBalance(E, buyer);
await o.finishWithdrawal(E, wid, false, "bank down"); await o.finishWithdrawal(E, wid, false, "again");
eq("failed withdrawal returned once", (await n.walletBalance(E, buyer)) - b0, 100_000);

const TR = "T-" + uid();
// transfers into a virtual account credit the owner
await db.prepare("INSERT INTO virtual_accounts (user_id,status,created_at) VALUES (?,'pending',?)").bind(buyer, t).run();
await n.storeAssignedAccount(E, { customerCode: "CUS_x", email: buyer + "@t.co" }, { account_number: "9900112233", account_name: "KONTENA/Test", bank: { name: "Test Bank" } });
eq("account stored", (await n.virtualAccount(E, buyer))?.account_number, "9900112233");
b0 = await n.walletBalance(E, buyer);
await n.creditFromTransfer(E, { customerCode: "CUS_x" }, 250_000, TR); await n.creditFromTransfer(E, { customerCode: "CUS_x" }, 250_000, TR);
eq("transfer credited once", (await n.walletBalance(E, buyer)) - b0, 250_000);

console.log(fails ? `${fails} FAILED` : "ALL PASSED");
process.exit(fails ? 1 : 0);
