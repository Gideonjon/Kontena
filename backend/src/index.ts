import { Hono } from "hono";
import { cors } from "hono/cors";
import type { App } from "./routes/types";
import type { Env } from "./lib/env";
import { requireAuth } from "./lib/auth";
import { HttpError } from "./lib/util";
import { sweepDeadlines } from "./lib/orders";
import { pub } from "./routes/public";
import { me } from "./routes/me";
import { vendor } from "./routes/vendor";
import { orders, withdrawals } from "./routes/orders";
import { webhooks } from "./routes/webhooks";
import { admin } from "./routes/admin";
import { naira } from "./routes/naira";

const app = new Hono<App>();

app.use("*", cors({
  origin: (origin, c) => {
    const ok = [c.env.APP_URL, c.env.SITE_URL, "https://usekontena.web.app", "https://kontena.app", "https://kontena.store", "https://www.kontena.store", "http://localhost:8080", "http://localhost:5000"];
    return ok.includes(origin) || /^http:\/\/localhost:\d+$/.test(origin) ? origin : "";
  },
  allowHeaders: ["Authorization", "Content-Type"],
  allowMethods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
}));

app.route("/", pub);
app.route("/webhooks", webhooks);

const authed = new Hono<App>();
authed.use("*", requireAuth);
authed.route("/", me);
authed.route("/vendor", vendor);
authed.route("/orders", orders);
authed.route("/withdrawals", withdrawals);
authed.route("/admin", admin);
authed.route("/naira", naira);
app.route("/", authed);

app.onError((err, c) => {
  if (err instanceof HttpError) return c.json({ error: err.message }, err.status as 400);
  console.error(err);
  return c.json({ error: "Something went wrong. Please try again." }, 500);
});
app.notFound((c) => c.json({ error: "Not found" }, 404));

export default {
  fetch: app.fetch,
  scheduled: (_e: ScheduledController, env: Env, ctx: ExecutionContext) => { ctx.waitUntil(sweepDeadlines(env)); },
};
