import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("ships the VoiceInk production interface instead of the starter preview", async () => {
  const [page, layout, clerkSubtree] = await Promise.all([
    source("app/page.tsx"),
    source("app/layout.tsx"),
    source("app/clerk-subtree.tsx"),
  ]);
  assert.match(page, /Ready to record/);
  assert.match(page, /History/);
  assert.match(page, /Summarize/);
  assert.match(layout, /VoiceInk Web/);
  assert.match(clerkSubtree, /signInForceRedirectUrl=\{siteUrl\}/);
  assert.match(clerkSubtree, /signUpForceRedirectUrl=\{siteUrl\}/);
  assert.doesNotMatch(`${page}\n${layout}`, /codex-preview|SkeletonPreview|Your site is taking shape/);
  await assert.rejects(access(new URL("app/_sites-preview", root)));
});

test("anonymous visitors never load the Clerk SDK and signed-in flows keep the verified bridge", async () => {
  const [providers, clerkSubtree] = await Promise.all([
    source("app/providers.tsx"),
    source("app/clerk-subtree.tsx"),
  ]);
  // The eagerly hydrated module must not import Clerk statically; the whole
  // Clerk subtree loads through one lazy chunk behind the session-hint gate.
  assert.doesNotMatch(providers, /from "@clerk\//);
  assert.match(providers, /lazy\(/);
  assert.match(providers, /import\("\.\/clerk-subtree"\)/);
  // The gate: mount on a non-zero __client_uat session hint, checked in an
  // effect so SSR and the first client render stay anonymous, or on an
  // explicit Sign in click.
  assert.match(providers, /__client_uat/);
  assert.match(providers, /value !== "" && value !== "0"/);
  assert.match(providers, /useEffect/);
  assert.match(providers, /requestSignIn/);
  // Anonymous consumers keep the fail-closed anonymous identity by default.
  assert.match(providers, /identityKey: "anonymous"/);
  assert.match(providers, /getConvexToken: async \(\) => null/);
  // The moved bridge preserves the verified-identity contract for signed-in
  // users, including the aud === "convex" template selection.
  assert.match(clerkSubtree, /sessionClaims\?\.aud === "convex"/);
  assert.match(clerkSubtree, /getToken\(\{ template: "convex" \}\)/);
  assert.match(clerkSubtree, /identityKey: sessionId \?\? "anonymous"/);
  // The Clerk-backed controls (which call useAuth) live only in the lazy
  // subtree module, never in the always-hydrated providers module.
  assert.doesNotMatch(providers, /useAuth\(\)/);
  assert.match(clerkSubtree, /export function ClerkAccountControls/);
  // Opening the gate must never remount the app: {children} keeps one fixed
  // tree position while the Clerk machinery mounts as a childless sibling
  // that lifts the verified identity up via state and portals the account
  // controls into their header host.
  assert.match(providers, /AccountAuthContext\.Provider value=\{accountAuth\}>\{children\}<\/AccountAuthContext\.Provider>/);
  assert.match(providers, /onAuthChange=\{setAccountAuth\}/);
  assert.doesNotMatch(providers, /<ClerkSubtree[^>]*>\s*\{children\}/);
  assert.match(clerkSubtree, /createPortal\(<ClerkAccountControls \/>, controlsHost\)/);
  // The error boundary wraps only the Clerk sibling (an app crash must still
  // reach Next.js error handling) and the fallback to anonymous auth is
  // logged, never silent.
  assert.match(providers, /console\.error\("Clerk subtree failed/);
  assert.match(providers, /setAccountAuth\(anonymousAuth\)/);
});

test("session-hint warm start preloads clerk-js and avoids a Sign in flash", async () => {
  const [providers, clerkSubtree] = await Promise.all([
    source("app/providers.tsx"),
    source("app/clerk-subtree.tsx"),
  ]);
  // Module-scope kickoff: browser-only, only when the __client_uat hint says
  // a session may exist, and it warms the same lazy chunk the gate mounts.
  assert.match(providers, /export function hasClerkSessionHint/);
  assert.match(
    providers,
    /typeof document !== "undefined" && accountsConfigured && hasClerkSessionHint\(\)/,
  );
  assert.match(providers, /void import\("\.\/clerk-subtree"\)/);
  // Preconnect plus a pinned clerk-js preload that matches the
  // crossorigin="anonymous" script request loadClerkJsScript makes — an
  // attribute mismatch would silently double-fetch the script.
  assert.match(providers, /rel = "preconnect"/);
  assert.match(providers, /CLERK_FRONTEND_API = "https:\/\/clerk\.paul\.im"/);
  assert.match(providers, /rel = "preload"/);
  assert.match(providers, /as = "script"/);
  assert.match(providers, /crossOrigin = "anonymous"/);
  assert.match(providers, /npm\/@clerk\/clerk-js@\$\{CLERK_JS_VERSION\}\/dist\/clerk\.browser\.js/);
  // The as="script" preload must carry the page CSP nonce: under the proxy's
  // 'nonce-…' 'strict-dynamic' script-src, an un-nonced link preload is
  // blocked ('strict-dynamic' trust does not extend to link preloads and the
  // host allowlist is ignored). The nonce is copied from a nonced script's
  // readable nonce IDL property.
  assert.match(providers, /document\.querySelector<HTMLScriptElement>\("script\[nonce\]"\)\?\.nonce/);
  assert.match(providers, /if \(nonce\) preload\.nonce = nonce;/);
  // The version pin is deliberately duplicated (importing it from the subtree
  // would statically link the Clerk chunk into the eager module and defeat
  // the lazy gate); the two copies must never drift apart. The subtree copy
  // is separately asserted against the installed @clerk packages.
  const providersPin = providers.match(/CLERK_JS_VERSION = "([0-9.]+)"/)?.[1];
  const subtreePin = clerkSubtree.match(/CLERK_JS_VERSION = "([0-9.]+)"/)?.[1];
  assert.ok(providersPin, "providers.tsx must pin an exact clerk-js version");
  assert.equal(
    providersPin,
    subtreePin,
    "the providers.tsx clerk-js pin must match app/clerk-subtree.tsx",
  );
  // No Sign in flash: with the hint present (and Clerk not failed) the header
  // renders the same Loading placeholder ClerkAccountControls starts with.
  // The hint is read through useSyncExternalStore with a false server
  // snapshot so the hydration render still matches the anonymous SSR markup,
  // and a Clerk load failure falls back to the retryable Sign in button.
  assert.match(
    providers,
    /useSyncExternalStore\(subscribeToNothing, hasClerkSessionHint, noServerHint\)/,
  );
  assert.match(providers, /const noServerHint = \(\) => false/);
  assert.match(providers, /sessionHint && !clerkFailed/);
  assert.match(providers, /<span>Loading<\/span>/);
});

test("immutable cache rule covers the path vinext actually emits assets under", async () => {
  const headers = await source("public/_headers");
  // vinext 0.2.x writes hashed chunks/css to dist/client/_next/static/; a rule
  // scoped to a stale path would silently deploy every chunk uncached.
  assert.match(headers, /^\/_next\/static\/\*\n\s+Cache-Control: public, max-age=31536000, immutable/m);
  const { readdir } = await import("node:fs/promises");
  const chunkDir = new URL("dist/client/_next/static/chunks/", root);
  const chunks = await readdir(chunkDir).catch(() => []);
  assert.ok(chunks.some((f) => f.endsWith(".js")), "expected built chunks under dist/client/_next/static/chunks");
});

test("pins clerk-js to the exact version the installed Clerk SDK resolves", async () => {
  const clerkSubtree = await source("app/clerk-subtree.tsx");
  assert.match(clerkSubtree, /__internal_clerkJSVersion: CLERK_JS_VERSION/);
  assert.match(clerkSubtree, /\{\.\.\.clerkScriptPin\}/);
  const pin = clerkSubtree.match(/CLERK_JS_VERSION = "([0-9.]+)"/)?.[1];
  assert.ok(pin, "the clerk-js pin must be an exact x.y.z version");
  const selector = await source("node_modules/@clerk/shared/dist/versionSelector.mjs");
  const resolved = selector.match(/packageVersion = "([0-9.]+)"/)?.[1];
  assert.equal(pin, resolved, "the clerk-js pin must match the version the installed @clerk packages resolve to");
});

test("keeps costly production routes behind edge controls", async () => {
  const [transcribe, summarize, history, importer, security, config, asr] = await Promise.all([
    source("app/api/transcribe/route.ts"),
    source("app/api/summarize/route.ts"),
    source("app/api/history/route.ts"),
    source("app/api/import/route.ts"),
    source("lib/server/requestSecurity.ts"),
    source("wrangler.production.jsonc"),
    source("cloudflare-asr/src/index.ts"),
  ]);
  for (const route of [transcribe, summarize, history, importer]) assert.match(route, /rejectCrossOrigin/);
  assert.match(transcribe, /TRANSCRIPTION_RATE_LIMITER/);
  assert.match(summarize, /SUMMARY_RATE_LIMITER/);
  assert.match(history, /HISTORY_RATE_LIMITER/);
  assert.match(importer, /IMPORT_RATE_LIMITER/);
  assert.match(security, /Too many requests/);
  assert.match(config, /"ratelimits"/);
  assert.match(asr, /!env\.ASR_API_KEY/);
  assert.doesNotMatch(transcribe, /mode:\s*"prototype"/);
});

test("emits a restrictive browser security policy", async () => {
  const [proxy, config] = await Promise.all([
    source("proxy.ts"),
    source("wrangler.production.jsonc"),
  ]);
  for (const header of [
    "Content-Security-Policy",
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "Referrer-Policy",
    "Permissions-Policy",
    "X-Frame-Options",
  ]) assert.match(proxy, new RegExp(header));
  assert.match(proxy, /frame-ancestors 'none'/);
  assert.match(proxy, /object-src 'none'/);
  assert.match(proxy, /https:\/\/clerk\.paul\.im/);
  assert.match(proxy, /https:\/\/accounts\.paul\.im/);
  assert.match(proxy, /frame-src[^;]*https:\/\/challenges\.cloudflare\.com/);
  assert.match(proxy, /script-src[^;]*https:\/\/challenges\.cloudflare\.com/);
  // The browser reaches Convex only through the brokered /api/history routes,
  // so the page CSP must not reopen a direct channel to convex.cloud.
  assert.doesNotMatch(proxy, /convex\.cloud/);
  // Document responses warm the third-party connections early via a Link
  // header: Clerk FAPI (crossorigin, matching clerk-js's anonymous fetch) and
  // the Turnstile challenge origin. Preconnect only — a script preload in a
  // Link header would be rejected by the per-request CSP nonce.
  assert.match(proxy, /<https:\/\/clerk\.paul\.im>; rel=preconnect; crossorigin/);
  assert.match(proxy, /<https:\/\/challenges\.cloudflare\.com>; rel=preconnect/);
  assert.doesNotMatch(proxy, /rel=preload/);
  // The Link header is appended only on the non-/api branch.
  assert.match(proxy, /\} else \{\s*response\.headers\.append\("Link", documentLinkHeader\);\s*\}/);
  assert.match(config, /"workers_dev": false/);
  assert.match(config, /"pattern": "v\.paul\.im"/);
});

test("enforces origin and declared body-size boundaries behaviorally", async () => {
  const { rejectCrossOrigin, rejectOversizedRequest } = await import("../lib/server/requestValidation.ts");
  const allowed = new Request("https://v.paul.im/api/summarize", { headers: { origin: "https://v.paul.im", "content-length": "100" } });
  assert.equal(rejectCrossOrigin(allowed), null);
  assert.equal(rejectOversizedRequest(allowed, 100), null);
  const crossOrigin = rejectCrossOrigin(new Request("https://v.paul.im/api/summarize", { headers: { origin: "https://evil.example" } }));
  assert.equal(crossOrigin?.status, 403);
  const oversized = rejectOversizedRequest(new Request("https://v.paul.im/api/summarize", { headers: { "content-length": "101" } }), 100);
  assert.equal(oversized?.status, 413);
});

test("brokers Convex access and enforces quotas and race-safe retention", async () => {
  const [transcriptions, retention, cleanup, client, ownerStats] = await Promise.all([
    source("convex/transcriptions.ts"),
    source("convex/retention.ts"),
    source("convex/cleanup.ts"),
    source("lib/convex.ts"),
    source("convex/ownerStats.ts"),
  ]);
  assert.match(transcriptions, /requireServiceSecret\(args\.serviceSecret\)/);
  // English-path saves use model "nova-3"; regressing to a whisper-only check
  // would silently break every English history save with the suite green.
  assert.match(transcriptions, /args\.model !== "nova-3" && args\.model !== "whisper-large-v3-turbo"/);
  assert.match(transcriptions, /args\.detectedLanguage\.length > 35 \|\| !\/\^\[a-z\]\{2,3\}\(-\[a-z0-9\]\{2,8\}\)\*\$\/i\.test\(args\.detectedLanguage\)/);
  assert.match(transcriptions, /detectedLanguage: args\.detectedLanguage\.toLowerCase\(\)/);
  assert.match(transcriptions, /item\.detectedLanguage \? \{ detectedLanguage: item\.detectedLanguage \}/);
  // Quotas now read the per-owner aggregate but keep the same limits and
  // messages: 50 items, 10,000,000 stored characters, 10 writes per minute.
  // (The former "100 per day" check was unreachable — it needed a count of 100
  // from a read bounded at 51 rows — and is deliberately absent.)
  assert.match(transcriptions, /Account history limit reached/);
  assert.match(transcriptions, /Account storage limit reached/);
  assert.match(transcriptions, /Transcription write limit reached/);
  assert.match(transcriptions, /stats\.itemCount >= ownerItemLimit/);
  assert.match(transcriptions, /stats\.storedChars \+ text\.length > ownerStoredCharsLimit/);
  assert.match(transcriptions, /recent\.length >= 10 && recent\[9\]\.createdAt > createdAt - 60_000/);
  assert.match(ownerStats, /export const ownerItemLimit = 50;/);
  assert.match(ownerStats, /export const ownerStoredCharsLimit = 10_000_000;/);
  assert.match(transcriptions, /by_owner_operation/);
  assert.match(transcriptions, /by_client_operation/);
  assert.match(transcriptions, /Operation identifier was already used for different content/);
  assert.match(retention, /serviceSecret/);
  assert.match(cleanup, /setting\.updatedAt !== revision/);
  assert.match(cleanup, /internal\.cleanup\.deleteExpiredTranscriptions/);
  assert.doesNotMatch(client, /client\.mutation/);
  assert.doesNotMatch(client, /client\.query/);
});

test("user-selected imports always bypass shared subrequest caches", async () => {
  const route = await source("app/api/import/route.ts");
  assert.match(route, /fetch\(url,[\s\S]*?cache: "no-store"/);
  assert.doesNotMatch(route, /caches\.default|cache\.put\(/);
});
