-- On-chain escrow (Soroban), Stellar proof links and passkeys

ALTER TABLE orders ADD COLUMN chain_state TEXT NOT NULL DEFAULT 'none';   -- none | funded | accepted | released | refunded | offchain
ALTER TABLE orders ADD COLUMN chain_error TEXT;

CREATE TABLE chain_txs (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  step TEXT NOT NULL,                 -- convert | fund | accept | release | refund | expire
  tx_hash TEXT NOT NULL,
  amount_cents INTEGER,
  note TEXT,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX chain_txs_step ON chain_txs(order_id, step);
CREATE INDEX orders_chain_pending ON orders(chain_state, status);

CREATE TABLE passkeys (
  id TEXT PRIMARY KEY,                -- credential id (base64url)
  user_id TEXT NOT NULL REFERENCES users(id),
  public_key TEXT NOT NULL,           -- base64url COSE key
  counter INTEGER NOT NULL DEFAULT 0,
  transports TEXT,
  label TEXT,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER
);
CREATE INDEX passkeys_user ON passkeys(user_id);

CREATE TABLE passkey_challenges (
  user_id TEXT PRIMARY KEY,
  challenge TEXT NOT NULL,
  kind TEXT NOT NULL,                 -- register | auth
  expires_at INTEGER NOT NULL
);
