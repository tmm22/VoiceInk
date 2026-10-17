// Pinned Clerk script locations, shared by the eager session-hint warm start
// (app/providers.tsx) and the lazy loader (lib/clerkSession.ts). Kept free of
// any Clerk SDK import so the eagerly loaded bundle stays tiny.
//
// Clerk Core 3 splits the browser SDK into a headless core (clerk-js, which
// sets window.Clerk) and a UI bundle (@clerk/ui, which sets
// window.__internal_ClerkUICtor). Major-only CDN URLs answer every visit with
// an uncacheable 307 redirect, so both are pinned to exact, mutually
// compatible versions. tests/production-smoke.mjs checks both URLs resolve.
export const CLERK_JS_VERSION = "6.39.0";
export const CLERK_UI_VERSION = "1.40.0";

export const clerkPublishableKey = process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

// A publishable key is "pk_<env>_" + base64("<frontend-api-host>$").
export function frontendApiFromKey(publishableKey: string): string | null {
  const encoded = publishableKey.split("_")[2];
  if (!encoded) return null;
  try {
    const decoded = atob(encoded);
    return decoded.endsWith("$") ? decoded.slice(0, -1) : null;
  } catch {
    return null;
  }
}

export function clerkScriptUrls(publishableKey: string) {
  const host = frontendApiFromKey(publishableKey);
  return host ? clerkScriptUrlsFor(`https://${host}`) : null;
}

export function clerkScriptUrlsFor(origin: string) {
  return {
    origin,
    js: `${origin}/npm/@clerk/clerk-js@${CLERK_JS_VERSION}/dist/clerk.browser.js`,
    ui: `${origin}/npm/@clerk/ui@${CLERK_UI_VERSION}/dist/ui.browser.js`,
  };
}

// Scripts are admitted by the per-request CSP nonce under 'strict-dynamic'.
// Copy it from any nonced script: the nonce IDL property stays readable to
// same-origin scripts even though browsers hide the content attribute.
export function pageNonce(): string | undefined {
  return document.querySelector<HTMLScriptElement>("script[nonce]")?.nonce || undefined;
}

// Warm start for a likely-signed-in visit: connect to Clerk and fetch both
// pinned scripts while the app hydrates. The preloads match the
// crossorigin="anonymous" script requests the loader makes (a mismatch would
// double-fetch), and carry the nonce because as="script" preloads are checked
// against script-src, where 'strict-dynamic' trust does not reach them.
export function preloadClerkScripts(publishableKey: string) {
  const urls = clerkScriptUrls(publishableKey);
  if (!urls) return;
  const nonce = pageNonce();
  const preconnect = document.createElement("link");
  preconnect.rel = "preconnect";
  preconnect.href = urls.origin;
  document.head.appendChild(preconnect);
  for (const href of [urls.js, urls.ui]) {
    const preload = document.createElement("link");
    preload.rel = "preload";
    preload.as = "script";
    preload.crossOrigin = "anonymous";
    if (nonce) preload.nonce = nonce;
    preload.href = href;
    document.head.appendChild(preload);
  }
}

// Clerk keeps a client-readable session hint in the __client_uat cookie
// ("updated at"; suffixed with an instance hash when several Clerk apps share
// a registrable domain). A non-zero value means a session may exist, so Clerk
// must load and verify it; absent or "0" means signed out and clerk-js is
// never loaded. SSR-safe: without a document it reports false.
export function hasClerkSessionHint(): boolean {
  if (typeof document === "undefined") return false;
  return document.cookie.split(";").some((pair) => {
    const separator = pair.indexOf("=");
    if (separator === -1) return false;
    const name = pair.slice(0, separator).trim();
    if (name !== "__client_uat" && !name.startsWith("__client_uat_")) return false;
    const value = pair.slice(separator + 1).trim();
    return value !== "" && value !== "0";
  });
}
