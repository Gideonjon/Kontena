-- Messages tab: pre-order conversations between a customer and a supplier, and read tracking for unread badges
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL REFERENCES stores(id),
  buyer_id TEXT NOT NULL REFERENCES users(id),
  vendor_id TEXT NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  UNIQUE (buyer_id, store_id)
);
CREATE INDEX conversations_vendor ON conversations(vendor_id);
CREATE TABLE inquiry_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id),
  sender_id TEXT NOT NULL REFERENCES users(id),
  body TEXT NOT NULL DEFAULT '',
  media_key TEXT,
  product_id TEXT,                       -- a product the message is about or shares
  created_at INTEGER NOT NULL
);
CREATE INDEX inquiry_messages_conv ON inquiry_messages(conversation_id, created_at);
-- the newest message (by rowid) each person has seen in a thread; later messages from the other side count as unread
CREATE TABLE message_reads (
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,                    -- order | inquiry
  ref_id TEXT NOT NULL,
  read_rowid INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, kind, ref_id)
);
