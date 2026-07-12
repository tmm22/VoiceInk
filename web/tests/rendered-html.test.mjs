import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("ships the VoiceInk production interface instead of the starter preview", async () => {
  const [page, layout] = await Promise.all([source("app/page.tsx"), source("app/layout.tsx")]);
  assert.match(page, /Transcription Studio/i);
  assert.match(page, /History/);
  assert.match(page, /AI summary/i);
  assert.match(layout, /VoiceInk Web/);
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
  assert.match(transcribe, /AI_RATE_LIMITER/);
  assert.match(summarize, /AI_RATE_LIMITER/);
  assert.match(history, /HISTORY_RATE_LIMITER/);
  assert.match(importer, /IMPORT_RATE_LIMITER/);
  assert.match(security, /Too many requests/);
  assert.match(config, /"ratelimits"/);
  assert.match(asr, /!env\.ASR_API_KEY/);
  assert.doesNotMatch(transcribe, /mode:\s*"prototype"/);
});

test("emits a restrictive browser security policy", async () => {
  const proxy = await source("proxy.ts");
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
});
