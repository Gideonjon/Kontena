-- Order chat (buyer, supplier and Kontena inspector) with photo/video attachments
CREATE TABLE order_messages (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  sender_id TEXT NOT NULL REFERENCES users(id),
  body TEXT NOT NULL DEFAULT '',
  media_key TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX order_messages_order ON order_messages(order_id, created_at);
