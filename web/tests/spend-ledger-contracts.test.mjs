import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  actualTranscriptionMicros,
  DEFAULT_DAILY_CLIENT_AUDIO_SECONDS,
  DEFAULT_DAILY_SPEND_LIMIT_MICROS,
  estimateTranscriptionMicros,
  INFERENCE_TIMEOUT_MS,
  parsePositiveIntegerSetting,
  RESERVATION_EXPIRY_MS,
  TEXT_GENERATION_FLAT_MICROS,
  TRANSCRIPTION_MICROS_PER_MINUTE,
  utcDay,
  WORST_CASE_BYTES_PER_SECOND,
  worstCaseAudioSeconds,
} from "../cloudflare-asr/src/budget.ts";
import { MAXIMUM_AUDIO_BYTES } from "../shared/transcriptionContract.ts";

const root = new URL("../", import.meta.url);

test("worst-case pricing assumes the lowest plausible bitrate", () => {
  assert.equal(worstCaseAudioSeconds(WORST_CASE_BYTES_PER_SECOND * 90), 90);
  assert.equal(worstCaseAudioSeconds(1), 1);
  assert.equal(worstCaseAudioSeconds(0), 0);
  assert.equal(worstCaseAudioSeconds(-5), 0);
  assert.equal(worstCaseAudioSeconds(Number.NaN), 0);
  // The floor must sit below real Opus voice (~6 kbps = 750 B/s) so a reservation
  // always upper-bounds the file's true duration and cost.
  assert.ok(WORST_CASE_BYTES_PER_SECOND <= 750);
});

test("inference is bounded below the reservation-expiry window", () => {
  assert.ok(INFERENCE_TIMEOUT_MS < RESERVATION_EXPIRY_MS,
    "a live request must always settle before its reservation can be swept");
});

test("committed spend is clamped to the reserved amount so the ceiling is a true upper bound", async () => {
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  assert.match(ledger, /Math\.min\(reservation\.amount_micros, Math\.max\(0, Math\.round\(actualMicros\)\)\)/);
  assert.match(ledger, /Math\.min\(reservation\.seconds_estimate, Math\.max\(0, Math\.round\(actualSeconds\)\)\)/);
  const index = await readFile(new URL("cloudflare-asr/src/index.ts", root), "utf8");
  assert.match(index, /AbortSignal\.any\(\[request\.signal, AbortSignal\.timeout\(INFERENCE_TIMEOUT_MS\)\]\)/);
});

test("per-client pending seconds are scoped to the reservation day", async () => {
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  assert.match(ledger, /SUM\(seconds_estimate\) AS total FROM reservations WHERE client_key = \? AND day = \?/);
});

test("a full 24 MB upload reserves a bounded worst-case amount", () => {
  const estimate = estimateTranscriptionMicros(MAXIMUM_AUDIO_BYTES);
  const worstCaseMinutes = worstCaseAudioSeconds(MAXIMUM_AUDIO_BYTES) / 60;
  assert.equal(estimate, Math.ceil(worstCaseMinutes * TRANSCRIPTION_MICROS_PER_MINUTE));
  assert.ok(estimate < DEFAULT_DAILY_SPEND_LIMIT_MICROS, "one upload can never consume the whole daily budget");
  assert.ok(estimate > 200_000, "24 MB at 8 kbps is several hundred audio minutes");
});

test("actual spend is settled from returned duration in integer micro-dollars", () => {
  assert.equal(actualTranscriptionMicros(60), TRANSCRIPTION_MICROS_PER_MINUTE);
  assert.equal(actualTranscriptionMicros(90), Math.ceil(1.5 * TRANSCRIPTION_MICROS_PER_MINUTE));
  assert.equal(actualTranscriptionMicros(0), 0);
  assert.equal(actualTranscriptionMicros(Number.NaN), 0);
  assert.ok(Number.isSafeInteger(actualTranscriptionMicros(3.33)));
});

test("environment settings fall back to safe defaults instead of unlimited", () => {
  assert.equal(parsePositiveIntegerSetting(undefined, 5), 5);
  assert.equal(parsePositiveIntegerSetting("", 5), 5);
  assert.equal(parsePositiveIntegerSetting("0", 5), 5);
  assert.equal(parsePositiveIntegerSetting("-1", 5), 5);
  assert.equal(parsePositiveIntegerSetting("abc", 5), 5);
  assert.equal(parsePositiveIntegerSetting("2000000", 5), 2_000_000);
  assert.ok(DEFAULT_DAILY_SPEND_LIMIT_MICROS > 0);
  assert.ok(DEFAULT_DAILY_CLIENT_AUDIO_SECONDS > 0);
  assert.ok(TEXT_GENERATION_FLAT_MICROS > 0);
});

test("ledger days key by UTC date", () => {
  assert.equal(utcDay(Date.UTC(2026, 7, 15, 23, 59, 59)), "2026-08-15");
  assert.equal(utcDay(Date.UTC(2026, 7, 16, 0, 0, 1)), "2026-08-16");
});

test("the ASR worker admits inference only through the spend ledger", async () => {
  const source = await readFile(new URL("cloudflare-asr/src/index.ts", root), "utf8");
  const reservations = source.match(/await reserveSpend\(/g) ?? [];
  const inferenceCalls = source.match(/env\.AI\.run\(/g) ?? [];
  assert.equal(reservations.length, inferenceCalls.length, "every AI.run call needs a reservation");
  assert.match(source, /if \(!admission\.ok\) return admissionDenial\(admission\)/);
  assert.match(source, /releaseSpend\(env, admission\.id\)/);
  assert.match(source, /commitSpend\(env, admission\.id/);
  assert.match(source, /INTERNAL_CLIENT_KEY_HEADER/);
});

test("ledger failures deny paid inference instead of allowing it", async () => {
  const source = await readFile(new URL("cloudflare-asr/src/ledgerClient.ts", root), "utf8");
  assert.match(source, /if \(!stub\) return \{ ok: false, reason: "unavailable" \}/);
  assert.match(source, /catch \{\s*return \{ ok: false, reason: "unavailable" \}/);
  assert.match(source, /LEDGER_CALL_TIMEOUT_MS = 3_000/);
});

test("the spend ledger is configured as a SQLite durable object", async () => {
  const config = await readFile(new URL("cloudflare-asr/wrangler.jsonc", root), "utf8");
  assert.match(config, /"SPEND_LEDGER"/);
  assert.match(config, /"class_name": "SpendLedger"/);
  assert.match(config, /"new_sqlite_classes": \["SpendLedger"\]/);
  assert.match(config, /"DAILY_SPEND_LIMIT_MICROS": "2000000"/);
  assert.match(config, /"DAILY_CLIENT_AUDIO_SECONDS": "7200"/);
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  assert.doesNotMatch(ledger, /await[^\n]*\n[^\n]*sql\.exec[\s\S]{0,400}?await fetch/, "no external awaits between ledger reads and writes");
});
