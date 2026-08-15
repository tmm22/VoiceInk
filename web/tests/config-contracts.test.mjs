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
  for (const binding of ["ASR", "AI_RATE_LIMITER", "IMPORT_RATE_LIMITER", "HISTORY_RATE_LIMITER"]) assert.match(config, new RegExp(`"${binding}"`));
});

test("the browser, public API, and private worker agree on the ASR model", async () => {
  const files = await Promise.all([source("app/page.tsx"), source("app/api/transcribe/route.ts"), source("cloudflare-asr/src/index.ts")]);
  assert.match(files[0], /whisper-large-v3-turbo/);
  assert.match(files[1], /\/v1\/transcriptions/);
  assert.match(files[2], /whisper-large-v3-turbo/);
  assert.match(files[2], /@cf\/openai\/whisper-large-v3-turbo/);
});

test("production never reintroduces demo transcripts or fail-open ASR", async () => {
  const [page, route, worker] = await Promise.all([source("app/page.tsx"), source("app/api/transcribe/route.ts"), source("cloudflare-asr/src/index.ts")]);
  assert.doesNotMatch(`${page}\n${route}`, /demoTranscript|mode:\s*"prototype"/);
  assert.match(worker, /!env\.ASR_API_KEY/);
  assert.match(route, /Transcription is unavailable/);
});
