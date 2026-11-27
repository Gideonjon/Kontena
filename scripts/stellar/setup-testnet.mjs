// Creates everything the on-chain escrow needs on Stellar TESTNET and prints the Worker settings.
//   node scripts/stellar/setup-testnet.mjs            (run from the repo root; needs backend/node_modules)
// Keys are saved to scripts/stellar/.testnet-keys.json (gitignored). Re-running reuses them.
import { createRequire } from "node:module";
import fs from "node:fs";
const require = createRequire(new URL("../../backend/package.json", import.meta.url));
const { Keypair, Asset, Operation, TransactionBuilder, Horizon, LiquidityPoolAsset, getLiquidityPoolId, BASE_FEE, Networks } = require("@stellar/stellar-sdk");

const RATE = Number(process.env.USD_NGN ?? 1500);       // NGN per USD in the test pool
const KEYS = new URL("./.testnet-keys.json", import.meta.url);
const horizon = new Horizon.Server("https://horizon-testnet.stellar.org");
const keys = fs.existsSync(KEYS) ? JSON.parse(fs.readFileSync(KEYS, "utf8")) : {};
for (const k of ["issuer", "operator", "maker", "demoSeller", "demoBuyer"]) keys[k] ??= Keypair.random().secret();
fs.writeFileSync(KEYS, JSON.stringify(keys, null, 2));
const kp = Object.fromEntries(Object.entries(keys).map(([k, s]) => [k, Keypair.fromSecret(s)]));

const USDC = new Asset("USDC", kp.issuer.publicKey());   // TESTNET stand-in. On mainnet use Circle's USDC.
const NGN = new Asset("NGN", kp.issuer.publicKey());     // TESTNET stand-in for a licensed NGN anchor asset.

async function fund(k) {
  try { await horizon.loadAccount(k.publicKey()); return; } catch {}
  const r = await fetch(`https://friendbot.stellar.org?addr=${k.publicKey()}`);
  if (!r.ok) throw new Error(`friendbot failed for ${k.publicKey()}: ${r.status}`);
}
async function submit(src, ops, signers = [src]) {
  const acct = await horizon.loadAccount(src.publicKey());
  const b = new TransactionBuilder(acct, { fee: String(Number(BASE_FEE) * 10), networkPassphrase: Networks.TESTNET });
  ops.forEach((o) => b.addOperation(o));
  const tx = b.setTimeout(120).build();
  signers.forEach((s) => tx.sign(s));
  try { return (await horizon.submitTransaction(tx)).hash; }
  catch (e) { throw new Error(JSON.stringify(e?.response?.data?.extras?.result_codes ?? e.message)); }
}
const has = async (k, a) => (await horizon.loadAccount(k.publicKey())).balances.some((b) => b.asset_code === a.getCode() && b.asset_issuer === a.getIssuer());

console.log("1/5 funding accounts with friendbot");
for (const k of Object.values(kp)) await fund(k);

console.log("2/5 trustlines for USDC and NGN");
for (const name of ["operator", "maker", "demoSeller", "demoBuyer"]) {
  const k = kp[name], ops = [];
  if (!(await has(k, USDC))) ops.push(Operation.changeTrust({ asset: USDC }));
  if (!(await has(k, NGN))) ops.push(Operation.changeTrust({ asset: NGN }));
  if (ops.length) await submit(k, ops);
}

console.log("3/5 minting test money");
await submit(kp.issuer, [
  Operation.payment({ destination: kp.maker.publicKey(), asset: USDC, amount: "1000000" }),
  Operation.payment({ destination: kp.maker.publicKey(), asset: NGN, amount: String(1000000 * RATE) }),
  Operation.payment({ destination: kp.operator.publicKey(), asset: NGN, amount: "50000000" }),   // ₦50m float for conversions
  Operation.payment({ destination: kp.operator.publicKey(), asset: USDC, amount: "20000" }),     // $20k float for USDC-paid orders
  Operation.payment({ destination: kp.demoBuyer.publicKey(), asset: USDC, amount: "5000" }),
]);

console.log(`4/5 NGN/USDC liquidity pool at ₦${RATE} per $1`);
const lpAsset = new LiquidityPoolAsset(NGN, USDC, 30);
const poolId = getLiquidityPoolId("constant_product", lpAsset.getLiquidityPoolParameters()).toString("hex");
const makerAcct = await horizon.loadAccount(kp.maker.publicKey());
const ops = [];
if (!makerAcct.balances.some((b) => b.liquidity_pool_id === poolId)) ops.push(Operation.changeTrust({ asset: lpAsset }));
const p = RATE.toFixed(7);
ops.push(Operation.liquidityPoolDeposit({ liquidityPoolId: poolId, maxAmountA: String(1000000 * RATE), maxAmountB: "1000000", minPrice: (RATE * 0.99).toFixed(7), maxPrice: (RATE * 1.01).toFixed(7) }));
await submit(kp.maker, ops).catch((e) => console.log("   pool already funded or price moved:", e.message));

console.log("5/5 done\n");
const out = {
  USDC_ASSET: `USDC:${kp.issuer.publicKey()}`, NGN_ASSET: `NGN:${kp.issuer.publicKey()}`,
  OPERATOR_PUBLIC: kp.operator.publicKey(), OPERATOR_SECRET: kp.operator.secret(),
  DEMO_SELLER: kp.demoSeller.publicKey(), DEMO_BUYER: kp.demoBuyer.publicKey(), POOL: poolId,
};
fs.writeFileSync(new URL("./.testnet-out.json", import.meta.url), JSON.stringify(out, null, 2));
console.log(JSON.stringify({ ...out, OPERATOR_SECRET: "(saved in scripts/stellar/.testnet-keys.json)" }, null, 2));
