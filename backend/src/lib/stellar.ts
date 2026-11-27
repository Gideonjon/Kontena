/**
 * Stellar layer: the on-chain escrow contract, NGN -> USDC path payments and fee sponsorship.
 *
 * Every transaction here is built and signed by Kontena's escrow operator key and Kontena pays the
 * network fee, so buyers and suppliers never need XLM or a seed phrase. Network calls use plain
 * fetch (Soroban RPC JSON-RPC and Horizon REST) so this runs inside a Cloudflare Worker.
 */
import { Buffer } from "node:buffer";
import {
  Address, Asset, BASE_FEE, Contract, Keypair, Operation, TransactionBuilder, nativeToScVal, xdr, Account, FeeBumpTransaction,
  type Transaction,
} from "@stellar/stellar-base";
import { assembleTransaction, parseRawSimulation, type Api } from "@stellar/stellar-sdk/minimal/rpc";
import type { Env } from "./env";

export type ChainStep = "convert" | "fund" | "accept" | "release" | "refund" | "expire" | "sponsor";

export const chainEnabled = (env: Env) => !!(env.ESCROW_CONTRACT_ID && env.ESCROW_OPERATOR_SECRET && env.USDC_ASSET);

const isMainnet = (env: Env) => (env.STELLAR_NETWORK ?? "testnet") === "public";
export const passphrase = (env: Env) => (isMainnet(env) ? "Public Global Stellar Network ; September 2015" : "Test SDF Network ; September 2015");
const rpcUrl = (env: Env) => env.SOROBAN_RPC_URL ?? (isMainnet(env) ? "https://mainnet.sorobanrpc.com" : "https://soroban-testnet.stellar.org");
const horizonUrl = (env: Env) => env.HORIZON_URL ?? (isMainnet(env) ? "https://horizon.stellar.org" : "https://horizon-testnet.stellar.org");

/** Public block explorer links shown in the app. */
export const explorerTx = (env: Env, hash: string) => `https://stellar.expert/explorer/${isMainnet(env) ? "public" : "testnet"}/tx/${hash}`;
export const explorerContract = (env: Env) =>
  env.ESCROW_CONTRACT_ID ? `https://stellar.expert/explorer/${isMainnet(env) ? "public" : "testnet"}/contract/${env.ESCROW_CONTRACT_ID}` : null;

const operator = (env: Env) => Keypair.fromSecret(env.ESCROW_OPERATOR_SECRET!);
export const operatorAddress = (env: Env) => operator(env).publicKey();

/** "CODE:ISSUER" -> Asset ("XLM" -> native) */
export function parseAsset(s: string): Asset {
  if (s === "XLM" || s === "native") return Asset.native();
  const [code, issuer] = s.split(":");
  return new Asset(code, issuer);
}

/** USD cents -> USDC stroops (7 decimals) */
export const centsToStroops = (cents: number) => BigInt(Math.round(cents)) * 100_000n;
const amountStr = (stroops: bigint) => {
  const s = stroops.toString().padStart(8, "0");
  return `${s.slice(0, -7)}.${s.slice(-7)}`.replace(/\.?0+$/, "") || "0";
};

/** Order ids become the contract's 32-byte keys. */
export async function orderKey(orderId: string): Promise<Buffer> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`kontena:${orderId}`));
  return Buffer.from(d);
}

// ---------------- transport ----------------

async function rpcCall<T>(env: Env, method: string, params: unknown): Promise<T> {
  const r = await fetch(rpcUrl(env), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  const j = (await r.json()) as { result?: T; error?: { message: string } };
  if (j.error) throw new Error(`Stellar RPC ${method}: ${j.error.message}`);
  return j.result as T;
}

async function loadAccount(env: Env, pub: string): Promise<Account> {
  const r = await fetch(`${horizonUrl(env)}/accounts/${pub}`);
  if (!r.ok) throw new Error(`Stellar account ${pub.slice(0, 6)}… not found (${r.status}). Fund it first.`);
  const j = (await r.json()) as { sequence: string };
  return new Account(pub, j.sequence);
}

async function submitAndWait(env: Env, tx: Transaction | FeeBumpTransaction): Promise<string> {
  const sent = await rpcCall<{ status: string; hash: string; errorResultXdr?: string }>(env, "sendTransaction", { transaction: tx.toXDR() });
  if (sent.status === "ERROR") throw new Error(`Stellar rejected the transaction: ${sent.errorResultXdr ?? "unknown error"}`);
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 1000));
    const got = await rpcCall<{ status: string; resultXdr?: string }>(env, "getTransaction", { hash: sent.hash });
    if (got.status === "SUCCESS") return sent.hash;
    if (got.status === "FAILED") throw new Error(`Stellar transaction failed: ${got.resultXdr ?? sent.hash}`);
  }
  throw new Error(`Stellar transaction ${sent.hash} not confirmed in time`);
}

/** Simulates, assembles (footprint, resource fees, auth), signs with the operator and submits a contract call. */
async function invoke(env: Env, method: string, args: xdr.ScVal[]): Promise<string> {
  const kp = operator(env);
  const acct = await loadAccount(env, kp.publicKey());
  const tx = new TransactionBuilder(acct, { fee: String(Number(BASE_FEE) * 100), networkPassphrase: passphrase(env) })
    .addOperation(new Contract(env.ESCROW_CONTRACT_ID!).call(method, ...args))
    .setTimeout(60).build();
  const raw = await rpcCall<Api.RawSimulateTransactionResponse>(env, "simulateTransaction", { transaction: tx.toXDR() });
  if (raw.error) throw new Error(`Escrow ${method} would fail: ${raw.error}`);
  const ready = assembleTransaction(tx, parseRawSimulation(raw)).build();
  ready.sign(kp);
  return submitAndWait(env, ready);
}

const addr = (s: string) => new Address(s).toScVal();
const i128 = (n: bigint) => nativeToScVal(n, { type: "i128" });
const u64 = (n: number | bigint) => nativeToScVal(BigInt(n), { type: "u64" });
const u32 = (n: number) => nativeToScVal(n, { type: "u32" });
const bytes32 = (b: Buffer) => xdr.ScVal.scvBytes(b);

// ---------------- escrow contract ----------------

export async function escrowFund(env: Env, a: { orderId: string; buyer: string; seller: string; refundTo: string; amountCents: number; depositPct: number; acceptBy: number; leadDays: number }) {
  const op = operatorAddress(env);
  return invoke(env, "fund", [
    bytes32(await orderKey(a.orderId)), addr(op), addr(a.buyer), addr(a.seller), addr(a.refundTo),
    i128(centsToStroops(a.amountCents)), u32(Math.round(a.depositPct * 100)), u64(a.acceptBy), u64(a.leadDays * 86400),
  ]);
}
export const escrowAccept = async (env: Env, orderId: string) => invoke(env, "accept", [bytes32(await orderKey(orderId)), addr(operatorAddress(env))]);
export const escrowRelease = async (env: Env, orderId: string) => invoke(env, "release", [bytes32(await orderKey(orderId)), addr(operatorAddress(env))]);
export const escrowRefund = async (env: Env, orderId: string) => invoke(env, "refund", [bytes32(await orderKey(orderId))]);
export const escrowExpire = async (env: Env, orderId: string) => invoke(env, "expire", [bytes32(await orderKey(orderId))]);

// ---------------- NGN -> USDC through Stellar's exchange ----------------

/**
 * Converts naira to exactly `usdCents` of USDC with a path payment (strict receive) on Stellar's built-in
 * exchange. The operator holds NGN from an anchor (a licensed NGN issuer on mainnet, Kontena's test asset on
 * testnet). Returns the tx hash and the naira actually spent.
 */
export async function convertNgnToUsdc(env: Env, usdCents: number, maxNairaKobo: number): Promise<{ hash: string; nairaSpent: string; path: string[] }> {
  if (!env.NGN_ASSET) throw new Error("NGN_ASSET not configured");
  const kp = operator(env);
  const ngnA = parseAsset(env.NGN_ASSET), usdc = parseAsset(env.USDC_ASSET!);
  const dest = amountStr(centsToStroops(usdCents));
  const q = new URLSearchParams({ source_assets: env.NGN_ASSET.includes(":") ? `${ngnA.getCode()}:${ngnA.getIssuer()}` : "native", destination_amount: dest });
  if (usdc.isNative()) q.set("destination_asset_type", "native");
  else { q.set("destination_asset_type", usdc.getCode().length <= 4 ? "credit_alphanum4" : "credit_alphanum12"); q.set("destination_asset_code", usdc.getCode()); q.set("destination_asset_issuer", usdc.getIssuer()); }
  const pr = await fetch(`${horizonUrl(env)}/paths/strict-receive?${q}`);
  const pj = (await pr.json()) as { _embedded?: { records: { source_amount: string; path: { asset_type: string; asset_code?: string; asset_issuer?: string }[] }[] } };
  const best = pj._embedded?.records?.sort((a, b) => Number(a.source_amount) - Number(b.source_amount))[0];
  if (!best) throw new Error("No NGN→USDC route on the Stellar exchange right now");
  const maxNaira = maxNairaKobo / 100;
  if (Number(best.source_amount) > maxNaira) throw new Error(`Exchange rate moved: needs ₦${best.source_amount}, max ₦${maxNaira.toFixed(2)}`);
  const path = best.path.map((p) => (p.asset_type === "native" ? Asset.native() : new Asset(p.asset_code!, p.asset_issuer!)));
  const acct = await loadAccount(env, kp.publicKey());
  const tx = new TransactionBuilder(acct, { fee: BASE_FEE, networkPassphrase: passphrase(env) })
    .addOperation(Operation.pathPaymentStrictReceive({ sendAsset: ngnA, sendMax: maxNaira.toFixed(7), destination: kp.publicKey(), destAsset: usdc, destAmount: dest, path }))
    .setTimeout(60).build();
  tx.sign(kp);
  const hash = await submitAndWait(env, tx);
  return { hash, nairaSpent: best.source_amount, path: [ngnA.getCode(), ...path.map((p) => p.getCode()), usdc.getCode()] };
}

// ---------------- fee sponsorship ----------------

/**
 * Wraps a transaction a user signed (for example from their own wallet) in a fee-bump paid by Kontena,
 * so users never need XLM for network fees. Only plain payments and Kontena escrow calls are sponsored.
 */
export async function sponsor(env: Env, innerXdr: string): Promise<string> {
  const inner = TransactionBuilder.fromXDR(innerXdr, passphrase(env));
  if (inner instanceof FeeBumpTransaction) throw new Error("Already fee-bumped");
  const allowed = inner.operations.every((o) =>
    o.type === "payment" || o.type === "pathPaymentStrictSend" || o.type === "pathPaymentStrictReceive" || o.type === "changeTrust" ||
    (o.type === "invokeHostFunction" && o.func.switch().name === "hostFunctionTypeInvokeContract" &&
      Address.fromScAddress(o.func.invokeContract().contractAddress()).toString() === env.ESCROW_CONTRACT_ID));
  if (!allowed || inner.operations.length > 3) throw new Error("Kontena only pays fees for payments and escrow calls");
  const kp = operator(env);
  const bump = TransactionBuilder.buildFeeBumpTransaction(kp, String(Number(BASE_FEE) * 10), inner, passphrase(env));
  bump.sign(kp);
  return submitAndWait(env, bump);
}
