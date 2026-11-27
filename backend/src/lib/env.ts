export interface Env {
  DB: D1Database;
  MEDIA: R2Bucket;
  PAYMENT_MODE: string;
  FIREBASE_PROJECT_ID: string;
  APP_URL: string;
  SITE_URL: string;
  DEPOSIT_PERCENT: string;
  PLATFORM_FEE_PERCENT: string;
  /** % taken from the supplier's proceeds when the balance is released. Default 0. */
  SELLER_COMMISSION_PERCENT?: string;
  /** % FX spread kept on fiat withdrawals */
  WITHDRAWAL_SPREAD_PERCENT?: string;
  USD_NGN: string;
  /** Paystack DVA provider slug: test-bank (test mode), wema-bank or titan-paystack (live) */
  PAYSTACK_DVA_BANK?: string;
  /** max Naira wallet balance a card top-up may reach (default 300000). Set per your licence / KYC tier. */
  WALLET_MAX_NGN?: string;
  USD_GHS: string;
  OFFRAMP_PROVIDER: string;
  YELLOWCARD_BASE: string;
  PAYSTACK_SECRET_KEY: string;
  FOSSAPAY_API_KEY: string;
  FOSSAPAY_WEBHOOK_SECRET: string;
  /** FossaPay customer id of the platform treasury (holds escrowed USDC) */
  PLATFORM_FOSSA_CUSTOMER_ID: string;
FOSSAPAY_WALLETS_ENABLED: string;  /** Stellar address of that treasury wallet */
  PLATFORM_STELLAR_ADDRESS: string;
  YELLOWCARD_API_KEY?: string;
  YELLOWCARD_SECRET?: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  /** comma separated Firebase UIDs allowed to run inspections */
  ADMIN_UIDS?: string;
  /** buyers may approve inspections themselves up to this many USD cents */
  INSPECTION_BUYER_MAX_CENTS?: string;
  /** proof the supplier must upload before inspection (defaults 3 photos, 1 video) */
  PROOF_MIN_PHOTOS?: string;
  PROOF_MIN_VIDEOS?: string;
  // ---- Stellar on-chain escrow (all optional: leave unset to keep escrow off-chain) ----
  /** testnet | public */
  STELLAR_NETWORK?: string;
  SOROBAN_RPC_URL?: string;
  HORIZON_URL?: string;
  /** C... id of the deployed kontena-escrow contract */
  ESCROW_CONTRACT_ID?: string;
  /** secret S... of the escrow operator: funds escrows, signs inspections, pays every network fee (wrangler secret) */
  ESCROW_OPERATOR_SECRET?: string;
  /** USDC asset as CODE:ISSUER (the contract's token) */
  USDC_ASSET?: string;
  /** NGN anchor asset as CODE:ISSUER. When set, naira orders are converted to USDC with a Stellar path payment */
  NGN_ASSET?: string;
  /** max slippage for NGN->USDC conversion, percent (default 2) */
  PATH_SLIPPAGE_PERCENT?: string;
  // ---- passkeys ----
  /** WebAuthn relying party id, e.g. kontena.store (must match the site the app runs on) */
  PASSKEY_RP_ID?: string;
  /** "required" makes a passkey confirmation mandatory for money actions once a user has a passkey (default) */
  PASSKEY_MODE?: string;
  /** HMAC secret for passkey confirmation tokens (wrangler secret; optional) */
  PASSKEY_SECRET?: string;
}

export type User = {
  id: string; email: string; name: string; phone: string; country: string; role: string;
  dob: string | null; address: string | null; city: string | null;
  fossa_customer_id: string | null; fossa_wallet_id: string | null; stellar_address: string | null;
  refund_to: string;
  created_at: number;
};

export type Vars = { user: User };
