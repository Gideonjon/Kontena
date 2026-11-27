/**
 * On-chain escrow integration test. Stellar is faked at the network layer: every transaction the backend
 * builds is decoded and checked (contract method, arguments, signer), so this runs offline.
 */
import { getPlatformProxy } from "wrangler";
import { Keypair, SorobanDataBuilder, TransactionBuilder, xdr, Address, scValToNative, Operation, Asset, Account, BASE_FEE, Networks } from "@stellar/stellar-base";
import * as o from "../src/lib/orders";
import { chainInfo, syncPendingChain } from "../src/lib/chain";
import { sponsor } from "../src/lib/stellar";
import { requirePasskeyIfEnrolled } from "../src/lib/passkeys";
import { hmacHex, uid } from "../src/lib/util";

const { env } = await getPlatformProxy<any>();
const op = Keypair.random();
const usdcIssuer = Keypair.random().publicKey(), ngnIssuer = Keypair.random().publicKey();
const CONTRACT = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC";
const E = {
  ...env, PLATFORM_FEE_PERCENT: "1.5", DEPOSIT_PERCENT: "30", USD_NGN: "1500", USD_GHS: "15", PAYSTACK_SECRET_KEY: "x", FOSSAPAY_API_KEY: "x",
  PLATFORM_FOSSA_CUSTOMER_ID: "c", PLATFORM_STELLAR_ADDRESS: "G" + "A".repeat(55), SITE_URL: "https://kontena.store", APP_URL: "https://kontena.store/app/#",
  ESCROW_CONTRACT_ID: CONTRACT, ESCROW_OPERATOR_SECRET: op.secret(), USDC_ASSET: `USDC:${usdcIssuer}`, NGN_ASSET: `NGN:${ngnIssuer}`, STELLAR_NETWORK: "testnet",
};
const db: D1Database = E.DB;
let fails = 0;
const eq = (n: string, a: unknown, b: unknown) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) fails++; console.log(ok ? "PASS" : "FAIL", n, ok ? "" : `got ${JSON.stringify(a)} want ${JSON.stringify(b)}`); };

// ---------- fake Stellar network ----------
type Sent = { kind: "invoke" | "path" | "bump"; method?: string; args?: unknown[]; signedByOperator: boolean };
const sent: Sent[] = [];
let failNext = "";
let seq = 100n;
const realFetch = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = String(input);
  if (url.includes("/accounts/")) return Response.json({ sequence: String(seq++) });
  if (url.includes("/paths/strict-receive")) return Response.json({ _embedded: { records: [{ source_amount: "15100.0000000", path: [{ asset_type: "native" }] }] } });
  if (url.includes("soroban-testnet")) {
    const body = JSON.parse(String(init!.body));
    if (body.method === "simulateTransaction") {
      const tx = TransactionBuilder.fromXDR(body.params.transaction, Networks.TESTNET) as any;
      const m = tx.operations[0].func.invokeContract().functionName().toString();
      if (failNext === m) { failNext = ""; return Response.json({ jsonrpc: "2.0", id: 1, result: { error: "HostError: simulated outage", latestLedger: 1 } }); }
      return Response.json({ jsonrpc: "2.0", id: 1, result: { latestLedger: 1, minResourceFee: "100", transactionData: new SorobanDataBuilder().build().toXDR("base64"), results: [{ auth: [], xdr: xdr.ScVal.scvVoid().toXDR("base64") }] } });
    }
    if (body.method === "sendTransaction") {
      const env_ = TransactionBuilder.fromXDR(body.params.transaction, Networks.TESTNET) as any;
      const inner = env_.innerTransaction ?? env_;
      const signed = env_.signatures.some((s: any) => op.verify(env_.hash(), s.signature()));
      const o0 = inner.operations[0];
      if (env_.innerTransaction) sent.push({ kind: "bump", signedByOperator: signed });
      else if (o0.type === "pathPaymentStrictReceive") sent.push({ kind: "path", args: [o0.sendAsset.code, o0.destAsset.code, o0.destAmount, o0.sendMax], signedByOperator: signed });
      else {
        const ic = o0.func.invokeContract();
        sent.push({ kind: "invoke", method: ic.functionName().toString(), args: ic.args().map((a: xdr.ScVal) => { const v = scValToNative(a); return typeof v === "bigint" ? v.toString() : v instanceof Uint8Array ? "bytes32" : v; }), signedByOperator: signed });
      }
      return Response.json({ jsonrpc: "2.0", id: 1, result: { status: "PENDING", hash: "ab".repeat(32).slice(0, 60) + String(sent.length).padStart(4, "0") } });
    }
    if (body.method === "getTransaction") return Response.json({ jsonrpc: "2.0", id: 1, result: { status: "SUCCESS" } });
  }
  if (url.includes("fossapay") || url.includes("paystack")) return Response.json({ status: true, data: {} });
  return realFetch(input as any, init);
}) as typeof fetch;
const origTimeout = globalThis.setTimeout;
(globalThis as any).setTimeout = (f: (...a: unknown[]) => void, ms?: number, ...a: unknown[]) => origTimeout(f, ms === 1000 ? 0 : ms, ...a); // skip the 1s confirmation polls

// ---------- fixtures ----------
const t = Math.floor(Date.now() / 1000);
const [buyer, vend, vend2, store, store2, prod, prod2] = [uid(), uid(), uid(), uid(), uid(), uid(), uid()];
const buyerAddr = Keypair.random().publicKey(), vendAddr = Keypair.random().publicKey();
await db.prepare("INSERT INTO users (id,email,role,country,stellar_address,created_at) VALUES (?,?,?,?,?,?)").bind(buyer, "b@t.co", "customer", "NG", buyerAddr, t).run();
await db.prepare("INSERT INTO users (id,email,role,stellar_address,created_at) VALUES (?,?,?,?,?)").bind(vend, "v@t.co", "vendor", vendAddr, t).run();
await db.prepare("INSERT INTO users (id,email,role,created_at) VALUES (?,?,?,?)").bind(vend2, "v2@t.co", "vendor", t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store, vend, "s" + store.slice(0, 6), "Onchain", t).run();
await db.prepare("INSERT INTO stores (id,owner_id,slug,name,created_at) VALUES (?,?,?,?,?)").bind(store2, vend2, "s" + store2.slice(0, 6), "NoWallet", t).run();
await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(prod, store, "Bags", 1000, 10, 14, t).run();
await db.prepare("INSERT INTO products (id,store_id,name,price_cents,min_qty,lead_days,created_at) VALUES (?,?,?,?,?,?,?)").bind(prod2, store2, "Cloth", 1000, 10, 14, t).run();
const pay = async (id: string, currency: string, funding: string, minor: number) => {
  await db.prepare("UPDATE orders SET funding=?, pay_currency=?, pay_amount_minor=? WHERE id=?").bind(funding, currency, minor, id).run();
  await o.markFunded(E, id, funding);
};
const G = (id: string) => o.getOrder(E, id).then((x) => x!);

// 1. naira order, full happy path
let ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 100 }] }); // $1,000 subtotal
await pay(ord.id, "NGN", "wallet", (ord.total_cents / 100) * 1500 * 100);
eq("path payment NGN -> USDC first", sent[0]?.kind === "path" ? [sent[0].args![0], sent[0].args![1], sent[0].args![2]] : null, ["NGN", "USDC", "1000.0000000"]);
eq("then fund() with $1,000 in stroops, 30% deposit", sent[1]?.method === "fund" ? [sent[1].args![1], sent[1].args![3], sent[1].args![5], sent[1].args![6]] : null, [op.publicKey(), vendAddr, "10000000000", 3000]);
eq("naira order refunds go to Kontena's NGN rail", sent[1]?.args![4], op.publicKey());
eq("operator signs and pays fees", sent.every((s) => s.signedByOperator), true);
eq("chain state funded", (await G(ord.id)).chain_state, "funded");
await o.vendorAccept(E, await G(ord.id));
eq("accept() on-chain", sent.at(-1)?.method, "accept");
eq("deposit NOT double-paid in app ledger", await o.availableCents(E, vend), 0);
await o.vendorReady(E, await G(ord.id), ["k"], "");
await o.inspectionResult(E, await G(ord.id), true, "");
eq("release() on-chain", sent.at(-1)?.method, "release");
eq("balance NOT double-paid in app ledger", await o.availableCents(E, vend), 0);
const info = await chainInfo(E, await G(ord.id));
eq("4 proof transactions", info?.txs.map((x) => x.step), ["convert", "fund", "accept", "release"]);
eq("explorer links", info?.txs[1].url.startsWith("https://stellar.expert/explorer/testnet/tx/"), true);
eq("contract link", info?.contractUrl, `https://stellar.expert/explorer/testnet/contract/${CONTRACT}`);

// 2. USDC order, failed inspection, with an RPC outage on accept that the cron repairs
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await pay(ord.id, "USDC", "usdc", 1);
eq("USDC refunds go straight to the buyer's wallet", sent.at(-1)?.args![4], buyerAddr);
failNext = "accept";
await o.vendorAccept(E, await G(ord.id));
eq("outage recorded, order still accepted", [(await G(ord.id)).status, (await G(ord.id)).chain_state, !!(await G(ord.id)).chain_error], ["accepted", "funded", true]);
await syncPendingChain(E);
eq("cron retried accept", [(await G(ord.id)).chain_state, (await G(ord.id)).chain_error], ["accepted", null]);
await o.vendorReady(E, await G(ord.id), ["k"], "");
await o.inspectionResult(E, await G(ord.id), false, "wrong colour");
eq("refund() on-chain", sent.at(-1)?.method, "refund");
const ev = await db.prepare("SELECT note FROM order_events WHERE order_id=? AND type='refund_sent'").bind(ord.id).first<{ note: string }>();
eq("buyer told the contract refunded", ev?.note.includes("escrow contract"), true);

// 3. missed accept deadline -> permissionless expire()
ord = await o.createOrder(E, buyer, { storeId: store, items: [{ productId: prod, qty: 10 }] });
await pay(ord.id, "USDC", "usdc", 1);
await db.prepare("UPDATE orders SET accept_by=1 WHERE id=?").bind(ord.id).run();
await o.sweepDeadlines(E);
eq("expire() on-chain", sent.at(-1)?.method, "expire");
eq("state refunded", (await G(ord.id)).chain_state, "refunded");

// 4. supplier without a Stellar wallet stays off-chain and is paid in-app as before
const before = sent.length;
ord = await o.createOrder(E, buyer, { storeId: store2, items: [{ productId: prod2, qty: 10 }] });
await pay(ord.id, "NGN", "wallet", 1);
await o.vendorAccept(E, await G(ord.id));
eq("no transactions", sent.length, before);
eq("marked offchain", (await G(ord.id)).chain_state, "offchain");
eq("deposit credited in-app", await o.availableCents(E, vend2), 3000);

// 5. fee sponsorship only for payments / escrow calls
const userKp = Keypair.random();
const mk = (opn: xdr.Operation) => { const tx = new TransactionBuilder(new Account(userKp.publicKey(), "1"), { fee: BASE_FEE, networkPassphrase: Networks.TESTNET }).addOperation(opn).setTimeout(60).build(); tx.sign(userKp); return tx.toXDR(); };
await sponsor(E, mk(Operation.payment({ destination: vendAddr, asset: new Asset("USDC", usdcIssuer), amount: "5" })));
eq("payment fee-bumped by Kontena", [sent.at(-1)?.kind, sent.at(-1)?.signedByOperator], ["bump", true]);
let threw = false; try { await sponsor(E, mk(Operation.setOptions({ homeDomain: "x.com" }))); } catch { threw = true; }
eq("other operations refused", threw, true);

// 6. passkey gate
await requirePasskeyIfEnrolled(E, buyer, undefined, "pay");
eq("no passkey -> no gate", true, true);
await db.prepare("INSERT INTO passkeys (id,user_id,public_key,created_at) VALUES ('cred1',?,'x',?)").bind(buyer, t).run();
threw = false; try { await requirePasskeyIfEnrolled(E, buyer, undefined, "pay"); } catch (e) { threw = String(e).includes("PASSKEY_REQUIRED"); }
eq("passkey user without confirmation blocked", threw, true);
const exp = t + 100, sig = await hmacHex("SHA-256", `pk:${E.PAYSTACK_SECRET_KEY}`, `${buyer}.${exp}`);
await requirePasskeyIfEnrolled(E, buyer, `${buyer}.${exp}.${sig}`, "pay");
eq("valid confirmation accepted", true, true);
threw = false; try { await requirePasskeyIfEnrolled(E, buyer, `${buyer}.${exp}.${"0".repeat(64)}`, "pay"); } catch { threw = true; }
eq("forged confirmation blocked", threw, true);

console.log(fails ? `${fails} FAILED` : "ALL PASSED");
process.exit(fails ? 1 : 0);
