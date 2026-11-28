import { Hono } from "hono";
import type { App } from "./types";
import { getConversation, inboxList, listInquiry, postInquiry, startConversation, unreadTotal } from "../lib/inbox";

export const inbox = new Hono<App>();

inbox.get("/", async (c) => c.json(await inboxList(c.env, c.get("user"))));
inbox.get("/unread", async (c) => c.json({ unread: await unreadTotal(c.env, c.get("user")) }));

/** A customer opens (or reopens) a conversation with a store. */
inbox.post("/start", async (c) => {
  const b = await c.req.json<{ storeId: string }>();
  return c.json({ id: await startConversation(c.env, c.get("user"), b.storeId) });
});

inbox.get("/inquiries/:id", async (c) => c.json(await listInquiry(c.env, await getConversation(c.env, c.req.param("id"), c.get("user")), c.get("user"))));
inbox.post("/inquiries/:id/messages", async (c) => {
  const b = await c.req.json<{ body?: string; mediaKey?: string; productId?: string }>();
  return c.json(await postInquiry(c.env, await getConversation(c.env, c.req.param("id"), c.get("user")), c.get("user"), b));
});
