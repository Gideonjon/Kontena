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
}

export type User = {
  id: string; email: string; name: string; phone: string; country: string; role: string;
  dob: string | null; address: string | null; city: string | null;
  fossa_customer_id: string | null; fossa_wallet_id: string | null; stellar_address: string | null;
  created_at: number;
};

export type Vars = { user: User };
