import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const repositoryRoot = new URL("../../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");
const repositorySource = (path) => readFile(new URL(path, repositoryRoot), "utf8");

test("GitHub workflows use Node 24-compatible JavaScript actions", async () => {
  const workflows = await Promise.all([
    repositorySource(".github/workflows/upstream-sync.yml"),
    repositorySource(".github/workflows/web-regression.yml"),
  ]);
  const combined = workflows.join("\n");
  assert.doesNotMatch(combined, /actions\/(?:checkout|setup-node)@v[1-4]\b/);
  assert.match(combined, /actions\/checkout@v6/);
  assert.match(combined, /actions\/setup-node@v6/);
});

test("production configuration preserves required domains and bindings", async () => {
  const config = await source("wrangler.production.jsonc");
  assert.match(config, /"pattern": "v\.paul\.im"/);
  for (const binding of ["ASR", "TRANSCRIPTION_RATE_LIMITER", "SUMMARY_RATE_LIMITER", "ENHANCEMENT_RATE_LIMITER", "IMPORT_RATE_LIMITER", "HISTORY_RATE_LIMITER"]) assert.match(config, new RegExp(`"${binding}"`));
});

test("AI enhancement is routed through the private AI service with product presets", async () => {
  const [page, route, worker] = await Promise.all([
    source("app/page.tsx"),
    source("app/api/enhance/route.ts"),
    source("cloudflare-asr/src/index.ts"),
  ]);
  assert.match(page, /AIEnhancementPanel/);
  assert.match(route, /ENHANCEMENT_RATE_LIMITER/);
  assert.match(route, /\/v1\/enhancements/);
  assert.match(route, /!bindings\.ASR \|\| !apiKey/);
  assert.match(worker, /clean:/);
  assert.match(worker, /concise:/);
  assert.match(worker, /professional:/);
  assert.match(worker, /notes:/);
});

test("the browser, public API, and private worker agree on the ASR model", async () => {
  const files = await Promise.all([
    source("app/page.tsx"),
    source("app/api/transcribe/route.ts"),
    source("cloudflare-asr/src/index.ts"),
    source("shared/transcriptionContract.ts"),
  ]);
  assert.match(files[0], /TRANSCRIPTION_MODEL_NAME/);
  assert.match(files[1], /\/v1\/transcriptions/);
  assert.match(files[2], /TRANSCRIPTION_MODEL_ID/);
  assert.match(files[3], /whisper-large-v3-turbo/);
  assert.match(files[3], /@cf\/openai\/whisper-large-v3-turbo/);
});

test("transcription remains private, streamed, and separately rate limited", async () => {
  const [route, worker, webConfig, asrConfig] = await Promise.all([
    source("app/api/transcribe/route.ts"),
    source("cloudflare-asr/src/index.ts"),
    source("wrangler.production.jsonc"),
    source("cloudflare-asr/wrangler.jsonc"),
  ]);
  assert.match(route, /TRANSCRIPTION_RATE_LIMITER/);
  assert.match(route, /body: request\.body/);
  assert.match(route, /signal: request\.signal/);
  assert.doesNotMatch(route, /FormData|formData\(\)|PARAKEET_API_URL|fetch\(target/);
  assert.match(worker, /audio: \{ body: audioStream, contentType: mediaType \}/);
  assert.doesNotMatch(worker, /formData\(\)|function toBase64|audio\.arrayBuffer\(\)|\bbtoa\(/);
  for (const config of [webConfig, asrConfig]) {
    assert.match(config, /"enable_request_signal"/);
    assert.match(config, /"workers_dev": false/);
    assert.match(config, /"preview_urls": false/);
  }
});

test("production never reintroduces demo transcripts or fail-open ASR", async () => {
  const [page, route, worker] = await Promise.all([source("app/page.tsx"), source("app/api/transcribe/route.ts"), source("cloudflare-asr/src/index.ts")]);
  assert.doesNotMatch(`${page}\n${route}`, /demoTranscript|mode:\s*"prototype"/);
  assert.match(worker, /!env\.ASR_API_KEY/);
  assert.match(route, /Transcription is unavailable/);
});
