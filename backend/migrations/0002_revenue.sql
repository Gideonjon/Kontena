-- Platform revenue ledger (USD cents). Recognised only when money can no longer be refunded.
CREATE TABLE platform_revenue (
  id TEXT PRIMARY KEY,
  order_id TEXT,
  withdrawal_id TEXT,
  kind TEXT NOT NULL,            -- protection_fee | seller_commission | withdrawal_spread
  amount_cents INTEGER NOT NULL, -- negative = reversal
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_rev_order_once ON platform_revenue(order_id, kind) WHERE order_id IS NOT NULL;
CREATE UNIQUE INDEX idx_rev_wd_once ON platform_revenue(withdrawal_id, kind) WHERE withdrawal_id IS NOT NULL;
