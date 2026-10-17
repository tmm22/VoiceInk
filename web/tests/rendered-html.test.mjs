import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";
import { asrWorkerSource, historyRouteSource, studioSource } from "./support/sources.mjs";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("ships the VoiceInk production interface instead of the starter preview", async () => {
  const [page, layout, providers, clerkSession] = await Promise.all([
    studioSource(),
    source("app/layout.tsx"),
    source("app/providers.tsx"),
    source("lib/clerkSession.ts"),
  ]);
  assert.match(page, /Ready to record/);
  assert.match(page, /History/);
  assert.match(page, /Summarize/);
  assert.match(layout, /VoiceInk Web/);
  assert.match(providers, /start\(\{\s*publishableKey,\s*siteUrl,/);
  assert.match(providers, /onAuthChange: \(auth\) => publishAuth\(generation, auth\)/);
  assert.match(clerkSession, /signInForceRedirectUrl: siteUrl/);
  assert.match(clerkSession, /signUpForceRedirectUrl: siteUrl/);
  assert.doesNotMatch(`${page}\n${layout}`, /codex-preview|SkeletonPreview|Your site is taking shape/);
  await assert.rejects(access(new URL("app/_sites-preview", root)));
});

test("anonymous visitors never load Clerk and signed-in flows keep the verified bridge", async () => {
  const [providers, clerkScripts, clerkSession, accountAuth, accountControls, packageJson] = await Promise.all([
    source("app/providers.tsx"),
    source("lib/clerkScripts.ts"),
    source("lib/clerkSession.ts"),
    source("lib/accountAuth.ts"),
    source("app/account-controls.tsx"),
    source("package.json"),
  ]);
  // No Clerk framework SDK ships at all: the app drives Clerk's own pinned
  // browser scripts, and the loader module is only reached through a dynamic
  // import behind the session-hint gate or an explicit Sign in click.
  assert.doesNotMatch(packageJson, /"@clerk\//);
  for (const eager of [providers, clerkScripts, accountAuth, accountControls]) {
    assert.doesNotMatch(eager, /from "@clerk\//);
    assert.doesNotMatch(eager, /import \{[^}]*\} from "\.\.\/lib\/clerkSession"/);
  }
  assert.match(providers, /import type \{ ClerkController \} from "\.\.\/lib\/clerkSession"/);
  assert.match(providers, /startingRef\.current = import\("\.\.\/lib\/clerkSession"\)/);
  // The gate: start on a non-zero __client_uat session hint, checked after
  // hydration so SSR and the first client render stay anonymous, or on an
  // explicit Sign in click.
  assert.match(clerkScripts, /__client_uat/);
  assert.match(clerkScripts, /value !== "" && value !== "0"/);
  assert.match(providers, /if \(accountsConfigured && hasClerkSessionHint\(\)\) startClerk\(\);/);
  assert.match(providers, /requestSignIn/);
  // Consumers keep the fail-closed anonymous identity by default and after a
  // failed load, and the failure is logged rather than silent.
  assert.match(accountAuth, /identityKey: "anonymous"/);
  assert.match(accountAuth, /getConvexToken: async \(\) => null/);
  assert.match(providers, /createContext<AccountAuth>\(anonymousAuth\)/);
  assert.match(providers, /console\.error\("Clerk failed to load; continuing anonymously"/);
  assert.match(providers, /setAccountAuth\(anonymousAuth\)/);
  // The verified-identity contract for signed-in users, including the
  // aud === "convex" template selection, read at call time.
  assert.match(clerkSession, /lastActiveToken\?\.jwt\?\.claims\?\.aud === "convex"/);
  assert.match(clerkSession, /getToken\(\{ template: "convex" \}\)/);
  assert.match(clerkSession, /identityKey: sessionId \?\? "anonymous"/);
  // Tokens are bound to the session the identity was published for
  // (exercised in tests/clerk-session.test.mjs).
  assert.match(clerkSession, /if \(!current \|\| current\.id !== sessionId\) throw new AccountChangedError\(\);/);
  // Clerk loads with its UI bundle, and the app tree is never re-parented:
  // {children} sits at one fixed position under both providers.
  assert.match(clerkSession, /ui: \{ ClerkUI: window\.__internal_ClerkUICtor \}/);
  assert.match(providers, /<AccountAuthContext value=\{accountAuth\}>\{children\}<\/AccountAuthContext>/);
  assert.match(accountControls, /mountUserButton/);
});

test("session-hint warm start preloads pinned Clerk scripts and avoids a Sign in flash", async () => {
  const [providers, clerkScripts, clerkSession, accountControls] = await Promise.all([
    source("app/providers.tsx"),
    source("lib/clerkScripts.ts"),
    source("lib/clerkSession.ts"),
    source("app/account-controls.tsx"),
  ]);
  // Module-scope kickoff: browser-only, only when the hint says a session may
  // exist, and it warms the same loader chunk the gate imports.
  assert.match(
    providers,
    /typeof document !== "undefined" && accountsConfigured && clerkPublishableKey && hasClerkSessionHint\(\)/,
  );
  assert.match(providers, /void import\("\.\.\/lib\/clerkSession"\)/);
  assert.match(providers, /preloadClerkScripts\(clerkPublishableKey\)/);
  // Both scripts are pinned to exact versions; major-only URLs answer with an
  // uncacheable 307 on every visit.
  assert.match(clerkScripts, /CLERK_JS_VERSION = "\d+\.\d+\.\d+"/);
  assert.match(clerkScripts, /CLERK_UI_VERSION = "\d+\.\d+\.\d+"/);
  assert.match(clerkScripts, /npm\/@clerk\/clerk-js@\$\{CLERK_JS_VERSION\}\/dist\/clerk\.browser\.js/);
  assert.match(clerkScripts, /npm\/@clerk\/ui@\$\{CLERK_UI_VERSION\}\/dist\/ui\.browser\.js/);
  // Preconnect plus preloads that match the loader's crossorigin="anonymous"
  // script requests (a mismatch would double-fetch), and the loader's own
  // script tags. Both carry the page CSP nonce: under 'nonce-…'
  // 'strict-dynamic', an un-nonced as="script" preload is blocked.
  assert.match(clerkScripts, /rel = "preconnect"/);
  assert.match(clerkScripts, /rel = "preload"/);
  assert.match(clerkScripts, /as = "script"/);
  assert.match(clerkScripts, /preload\.crossOrigin = "anonymous"/);
  assert.match(clerkScripts, /if \(nonce\) preload\.nonce = nonce;/);
  assert.match(clerkScripts, /document\.querySelector<HTMLScriptElement>\("script\[nonce\]"\)\?\.nonce/);
  assert.match(clerkSession, /script\.crossOrigin = "anonymous"/);
  assert.match(clerkSession, /if \(nonce\) script\.nonce = nonce;/);
  // No Sign in flash: a layout effect moves the gate to "loading" before the
  // first paint when the hint is present, and the header shows Loading while
  // Clerk loads; a failed load falls back to the retryable Sign in button.
  assert.match(providers, /useLayoutEffect\(\(\) => \{\n\s+if \(accountsConfigured && hasClerkSessionHint\(\)\) startClerk\(\);/);
  assert.match(accountControls, /status === "loading"/);
  assert.match(accountControls, /<span>Loading<\/span>/);
  assert.match(accountControls, /<button onClick=\{requestSignIn\}>Sign in<\/button>/);
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

test("the production smoke suite verifies both pinned Clerk script URLs resolve", async () => {
  const smoke = await source("tests/production-smoke.mjs");
  assert.match(smoke, /clerkScriptUrls/);
  assert.match(smoke, /redirect: "error"/);
});

test("keeps costly production routes behind edge controls", async () => {
  const [transcribe, summarize, history, importer, security, config, asr] = await Promise.all([
    source("app/api/transcribe/route.ts"),
    source("app/api/summarize/route.ts"),
    historyRouteSource(),
    source("app/api/import/route.ts"),
    source("lib/server/requestSecurity.ts"),
    source("wrangler.production.jsonc"),
    asrWorkerSource(),
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
  assert.match(transcriptions, /if \(!isTranscriptionModelName\(args\.model\)\) throw new Error\("Unsupported transcription model\."\);/);
  // The allowlist itself (which includes nova-3) and the tag pattern come
  // from shared/transcriptionContract.ts; see transcription-contract.test.mjs.
  assert.match(transcriptions, /!isValidLanguageTag\(args\.detectedLanguage\)/);
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
