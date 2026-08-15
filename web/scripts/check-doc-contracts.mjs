import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

export function forbiddenDocumentationDrift(text) {
  return [
    /voiceink-asr\.[\w-]+\.workers\.dev/i,
    /PARAKEET_API_URL/,
    /Demo transcript returned/i,
    /public hostname exists for health checks/i,
  ].filter((pattern) => pattern.test(text)).map(String);
}

export async function checkDocumentationContracts() {
  const [readme, deployment, costs, agentGuide, config, asrConfig, contract, smoke] = await Promise.all([
    read("README.md"),
    read("docs/DEPLOYMENT.md"),
    read("docs/COSTS.md"),
    read("AGENTS.md"),
    read("wrangler.production.jsonc"),
    read("cloudflare-asr/wrangler.jsonc"),
    read("shared/transcriptionContract.ts"),
    read("tests/production-smoke.mjs"),
  ]);
  const docs = [readme, deployment, costs, agentGuide].join("\n");
  assert.deepEqual(forbiddenDocumentationDrift(`${docs}\n${smoke}`), [], "obsolete public/fallback architecture remains documented");
  for (const text of [readme, deployment, agentGuide]) {
    assert.match(text, /https:\/\/v\.paul\.im/, "canonical origin is missing");
    assert.match(text, /@cf\/openai\/whisper-large-v3-turbo/, "canonical transcription model is missing");
  }
  for (const binding of [
    "TRANSCRIPTION_RATE_LIMITER",
    "SUMMARY_RATE_LIMITER",
    "ENHANCEMENT_RATE_LIMITER",
    "IMPORT_RATE_LIMITER",
    "HISTORY_RATE_LIMITER",
  ]) assert.match(config, new RegExp(`"${binding}"`), `${binding} is missing`);
  assert.match(config, /"TRANSCRIPTION_RATE_LIMITER"[\s\S]*?"limit": 4/);
  assert.match(config, /"SUMMARY_RATE_LIMITER"[\s\S]*?"limit": 6/);
  assert.match(config, /"ENHANCEMENT_RATE_LIMITER"[\s\S]*?"limit": 6/);
  assert.match(config, /"IMPORT_RATE_LIMITER"[\s\S]*?"limit": 10/);
  assert.match(config, /"HISTORY_RATE_LIMITER"[\s\S]*?"limit": 30/);
  assert.match(config, /"workers_dev": false/);
  assert.match(asrConfig, /"workers_dev": false/);
  assert.match(asrConfig, /"preview_urls": false/);
  assert.match(asrConfig, /"SPEND_LEDGER"/, "spend-ledger durable object binding is missing");
  assert.match(asrConfig, /"new_sqlite_classes": \["SpendLedger"\]/, "spend-ledger migration is missing");
  assert.match(asrConfig, /"DAILY_SPEND_LIMIT_MICROS": "2000000"/, "daily spend ceiling drifted from documentation");
  assert.match(asrConfig, /"DAILY_CLIENT_AUDIO_SECONDS": "7200"/, "per-client audio quota drifted from documentation");
  assert.match(deployment, /TURNSTILE_SECRET_KEY/, "Turnstile secret setup is undocumented");
  assert.match(costs, /\$2\.00 per UTC day/, "spend ceiling is undocumented in costs");
  assert.match(contract, /MAXIMUM_AUDIO_BYTES = 24 \* 1024 \* 1024/);
  assert.match(docs, /24 MB/);
  assert.match(costs, /\$0\.00051 per audio minute/);
  assert.match(docs, /no-store|not enable response caching/i);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await checkDocumentationContracts();
  console.log("Documentation contracts passed.");
}
