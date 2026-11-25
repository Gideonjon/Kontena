-- Naira wallet. Amounts are integer kobo. A user's balance is SUM(amount_kobo).
CREATE TABLE wallet_entries (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL,            -- topup | transfer_in | order_payment | refund | withdrawal | withdrawal_reversal
  amount_kobo INTEGER NOT NULL,  -- positive = money in, negative = money out
  ref TEXT NOT NULL,             -- provider reference / order id / withdrawal id: makes every credit idempotent
  order_id TEXT,
  note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_wallet_user ON wallet_entries(user_id, created_at);
CREATE UNIQUE INDEX idx_wallet_once ON wallet_entries(kind, ref);

-- Paystack dedicated virtual account (a real NUBAN) per user.
CREATE TABLE virtual_accounts (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  customer_code TEXT,                       -- filled in by the assign webhook
  status TEXT NOT NULL DEFAULT 'pending',   -- pending | active | failed
  account_number TEXT,
  account_name TEXT,
  bank_name TEXT,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_va_customer ON virtual_accounts(customer_code);

-- Where refunds for Naira orders go: the Kontena wallet (instant) or back to the original card/bank.
ALTER TABLE users ADD COLUMN refund_to TEXT NOT NULL DEFAULT 'wallet';
