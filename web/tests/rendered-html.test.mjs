import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("ships the VoiceInk production interface instead of the starter preview", async () => {
  const [page, layout, providers] = await Promise.all([
    source("app/page.tsx"),
    source("app/layout.tsx"),
    source("app/providers.tsx"),
  ]);
  assert.match(page, /Ready to record/);
  assert.match(page, /History/);
  assert.match(page, /Summarize/);
  assert.match(layout, /VoiceInk Web/);
  assert.match(providers, /signInForceRedirectUrl=\{siteUrl\}/);
  assert.match(providers, /signUpForceRedirectUrl=\{siteUrl\}/);
  assert.doesNotMatch(`${page}\n${layout}`, /codex-preview|SkeletonPreview|Your site is taking shape/);
  await assert.rejects(access(new URL("app/_sites-preview", root)));
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
  const [transcriptions, retention, cleanup, client] = await Promise.all([
    source("convex/transcriptions.ts"),
    source("convex/retention.ts"),
    source("convex/cleanup.ts"),
    source("lib/convex.ts"),
  ]);
  assert.match(transcriptions, /requireServiceSecret\(args\.serviceSecret\)/);
  // English-path saves use model "nova-3"; regressing to a whisper-only check
  // would silently break every English history save with the suite green.
  assert.match(transcriptions, /args\.model !== "nova-3" && args\.model !== "whisper-large-v3-turbo"/);
  assert.match(transcriptions, /args\.detectedLanguage\.length > 35 \|\| !\/\^\[a-z\]\{2,3\}\(-\[a-z0-9\]\{2,8\}\)\*\$\/i\.test\(args\.detectedLanguage\)/);
  assert.match(transcriptions, /detectedLanguage: args\.detectedLanguage\.toLowerCase\(\)/);
  assert.match(transcriptions, /item\.detectedLanguage \? \{ detectedLanguage: item\.detectedLanguage \}/);
  assert.match(transcriptions, /Daily transcription limit reached/);
  assert.match(transcriptions, /Account storage limit reached/);
  assert.match(transcriptions, /history\.length >= 50/);
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
