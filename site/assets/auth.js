import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword,
  signInWithPopup, GoogleAuthProvider, sendPasswordResetEmail, getAdditionalUserInfo,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";

const cfg = window.KONTENA;
const $ = (id) => document.getElementById(id);
const mode = document.body.dataset.mode; // "login" | "signup"
const params = new URLSearchParams(location.search);
const next = params.get("next");
const nextOk = next && /^\/(s|order)\/[\w-]+$/.test(next) ? next : null;

const views = { form: $("v-form"), roles: $("v-roles"), busy: $("v-busy") };
function show(v) { for (const k in views) views[k].hidden = k !== v; }
function say(el, msg, kind = "err") { el.textContent = msg || ""; el.hidden = !msg; el.className = kind; }
function setBusy(b) { $("go").disabled = b; $("google").disabled = b; $("go").dataset.busy = b ? "1" : ""; $("go-label").hidden = b; $("go-spin").hidden = !b; }

const ERR = {
  "auth/invalid-credential": "That email and password don't match.",
  "auth/invalid-email": "Enter a valid email address.",
  "auth/user-not-found": "No account with that email. Create one instead.",
  "auth/wrong-password": "That email and password don't match.",
  "auth/email-already-in-use": "That email already has an account. Log in instead.",
  "auth/weak-password": "Use a password of at least 6 characters.",
  "auth/too-many-requests": "Too many attempts. Wait a minute and try again.",
  "auth/network-request-failed": "No connection. Check your internet and try again.",
  "auth/popup-blocked": "Your browser blocked the Google window. Allow pop-ups and try again.",
};
const human = (e) => ERR[e?.code] || (e?.code === "auth/popup-closed-by-user" || e?.code === "auth/cancelled-popup-request" ? "" : e?.message && !e.code ? e.message : "Something went wrong. Please try again.");

if (!cfg || cfg.firebase.apiKey === "REPLACE_ME") {
  say($("err"), "Sign-in is not set up yet. Add the Firebase web config in assets/config.js.");
  $("go").disabled = true; $("google").disabled = true;
  throw new Error("Firebase config missing");
}

const app = initializeApp(cfg.firebase);
const auth = getAuth(app);

async function api(path, method = "GET", body) {
  const token = await auth.currentUser.getIdToken();
  const r = await fetch(cfg.apiUrl + path, {
    method,
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.error || "Something went wrong. Please try again.");
  return d;
}

// The Flutter web app (served at /app) reads its saved side from localStorage under flutter.<key> as JSON.
const storedMode = () => { try { const v = JSON.parse(localStorage.getItem("flutter.mode")); return v === "customer" || v === "vendor" ? v : null; } catch { return null; } };
const saveMode = (m) => { try { localStorage.setItem("flutter.mode", JSON.stringify(m)); } catch {} };

let me = null;
function enter(side) {
  saveMode(side);
  const hash = nextOk ? nextOk : side === "vendor" ? (me?.store ? "/v/home" : "/v/setup") : "/c/explore";
  location.replace("/app/#" + hash);
}

async function afterAuth() {
  show("busy");
  try {
    me = await api("/me");
    const m = storedMode();
    if (m) return enter(m);
    show("roles");
  } catch (e) {
    show("form"); say($("err"), human(e) || e.message);
  }
}

async function profileFor(user, country) {
  try { await api("/me", "PATCH", { name: (user.displayName || $("name")?.value || "").trim(), country }); } catch {}
}
const country = () => (document.querySelector("input[name=country]:checked")?.value) || "NG";

$("form").addEventListener("submit", async (e) => {
  e.preventDefault(); say($("err"), ""); say($("note"), "", "ok");
  const email = $("email").value.trim(), pass = $("pass").value;
  if (!email || !pass) return say($("err"), "Enter your email and password.");
  if (mode === "signup" && !$("name").value.trim()) return say($("err"), "Enter your full name.");
  setBusy(true);
  try {
    if (mode === "signup") {
      await createUserWithEmailAndPassword(auth, email, pass);
      await api("/me", "PATCH", { name: $("name").value.trim(), country: country() });
      me = await api("/me"); show("roles");
    } else {
      await signInWithEmailAndPassword(auth, email, pass);
      await afterAuth();
    }
  } catch (err) { say($("err"), human(err)); }
  setBusy(false);
});

$("google").addEventListener("click", async () => {
  say($("err"), ""); setBusy(true);
  try {
    const cred = await signInWithPopup(auth, new GoogleAuthProvider());
    if (getAdditionalUserInfo(cred)?.isNewUser) {
      await api("/me", "PATCH", { name: cred.user.displayName || "", country: country() });
      me = await api("/me"); show("roles");
    } else await afterAuth();
  } catch (err) { say($("err"), human(err)); }
  setBusy(false);
});

$("forgot")?.addEventListener("click", async () => {
  say($("err"), ""); say($("note"), "", "ok");
  const email = $("email").value.trim();
  if (!email) return say($("err"), "Type your email above first, then tap Forgot password.");
  try { await sendPasswordResetEmail(auth, email); say($("note"), "Check your inbox for a reset link.", "ok"); }
  catch (err) { say($("err"), human(err)); }
});

document.querySelectorAll("[data-role]").forEach((b) => b.addEventListener("click", async () => {
  const role = b.dataset.role;
  document.querySelectorAll("[data-role]").forEach((x) => (x.disabled = true));
  try { await api("/me", "PATCH", { role }); enter(role); }
  catch (err) { say($("rerr"), err.message); document.querySelectorAll("[data-role]").forEach((x) => (x.disabled = false)); }
}));

$("signout")?.addEventListener("click", async () => { await auth.signOut(); show("form"); });

// Already signed in on this browser: skip the form.
let first = true;
onAuthStateChanged(auth, (u) => { if (first) { first = false; if (u) afterAuth(); } });
