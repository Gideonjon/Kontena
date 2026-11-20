import { createRemoteJWKSet, jwtVerify } from "jose";
import type { MiddlewareHandler } from "hono";
import type { Env, User, Vars } from "./env";
import { HttpError, now } from "./util";

const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

/** Verifies a Firebase ID token and loads (or creates) the matching user row. */
export const requireAuth: MiddlewareHandler<{ Bindings: Env; Variables: Vars }> = async (c, next) => {
  const h = c.req.header("Authorization") ?? "";
  if (!h.startsWith("Bearer ")) throw new HttpError(401, "Missing token");
  let payload;
  try {
    ({ payload } = await jwtVerify(h.slice(7), JWKS, {
      issuer: `https://securetoken.google.com/${c.env.FIREBASE_PROJECT_ID}`,
      audience: c.env.FIREBASE_PROJECT_ID,
    }));
  } catch {
    throw new HttpError(401, "Invalid or expired token");
  }
  const id = payload.sub as string;
  let user = await c.env.DB.prepare("SELECT * FROM users WHERE id=?").bind(id).first<User>();
  if (!user) {
    const email = (payload.email as string | undefined) ?? "";
    await c.env.DB.prepare("INSERT INTO users (id,email,name,created_at) VALUES (?,?,?,?)")
      .bind(id, email, (payload.name as string | undefined) ?? "", now()).run();
    user = (await c.env.DB.prepare("SELECT * FROM users WHERE id=?").bind(id).first<User>())!;
  }
  c.set("user", user);
  await next();
};

export const isAdmin = (env: Env, u: User) =>
  u.role === "admin" || (env.ADMIN_UIDS ?? "").split(",").map((s) => s.trim()).includes(u.id);
