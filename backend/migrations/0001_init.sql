-- Kontena schema. All money is stored as integer USD cents.
CREATE TABLE users (
  id TEXT PRIMARY KEY,                 -- Firebase UID
  email TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT 'NG',  -- NG | GH
  role TEXT NOT NULL DEFAULT 'customer', -- customer | vendor | admin
  dob TEXT, address TEXT, city TEXT,
  fossa_customer_id TEXT,
  fossa_wallet_id TEXT,
  stellar_address TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE payout_accounts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL,                  -- bank | momo
  currency TEXT NOT NULL,              -- NGN | GHS
  bank_code TEXT NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_name TEXT NOT NULL,
  paystack_recipient TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE stores (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL UNIQUE REFERENCES users(id),
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT 'NG',
  city TEXT NOT NULL DEFAULT '',
  logo_key TEXT,
  cover_key TEXT,
  verified INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL REFERENCES stores(id),
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  price_cents INTEGER NOT NULL,        -- per unit, USD
  min_qty INTEGER NOT NULL DEFAULT 1,
  lead_days INTEGER NOT NULL DEFAULT 21,
  image_key TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_products_store ON products(store_id);
CREATE TABLE pools (                    -- group buys
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  store_id TEXT NOT NULL REFERENCES stores(id),
  target_qty INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open', -- open | filled | closed
  created_at INTEGER NOT NULL
);
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  ref TEXT NOT NULL UNIQUE,            -- KT-XXXXXX
  store_id TEXT NOT NULL REFERENCES stores(id),
  buyer_id TEXT NOT NULL REFERENCES users(id),
  vendor_id TEXT NOT NULL REFERENCES users(id),
  pool_id TEXT REFERENCES pools(id),
  status TEXT NOT NULL,                -- awaiting_payment | funded | accepted | inspection | shipped | delivered | refunded | cancelled
  subtotal_cents INTEGER NOT NULL,
  fee_cents INTEGER NOT NULL,
  total_cents INTEGER NOT NULL,        -- subtotal + fee, what the buyer pays
  deposit_cents INTEGER NOT NULL,
  balance_cents INTEGER NOT NULL,
  funding TEXT,                        -- paystack | usdc
  pay_currency TEXT,                   -- NGN | GHS | USDC
  pay_amount_minor INTEGER,
  paystack_ref TEXT,
  fossa_ref TEXT,
  accept_by INTEGER NOT NULL,
  ship_by INTEGER,
  lead_days INTEGER NOT NULL,
  proof_keys TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_orders_buyer ON orders(buyer_id);
CREATE INDEX idx_orders_vendor ON orders(vendor_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE TABLE order_items (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  product_id TEXT NOT NULL,
  name TEXT NOT NULL,
  unit_cents INTEGER NOT NULL,
  qty INTEGER NOT NULL
);
CREATE TABLE order_events (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  type TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_events_order ON order_events(order_id);
CREATE TABLE ledger (                   -- vendor-side balances. Positive = owed to user.
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  order_id TEXT,
  kind TEXT NOT NULL,                  -- deposit_release | balance_release | withdrawal | withdrawal_reversal
  amount_cents INTEGER NOT NULL,
  ref TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_ledger_user ON ledger(user_id);
CREATE UNIQUE INDEX idx_ledger_once ON ledger(order_id, kind) WHERE order_id IS NOT NULL;
CREATE TABLE withdrawals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  method TEXT NOT NULL,                -- bank | momo | offramp | usdc
  amount_cents INTEGER NOT NULL,
  fiat_currency TEXT,
  fiat_minor INTEGER,
  dest_json TEXT NOT NULL,
  status TEXT NOT NULL,                -- pending | processing | completed | failed
  provider_ref TEXT,
  error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  order_id TEXT,
  read INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_notif_user ON notifications(user_id, created_at);
CREATE TABLE device_tokens (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  platform TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE TABLE webhook_events (           -- idempotency for provider webhooks
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
