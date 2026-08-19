import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  actualTranscriptionMicros,
  DEFAULT_DAILY_CLIENT_AUDIO_SECONDS,
  DEFAULT_DAILY_SPEND_LIMIT_MICROS,
  ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE,
  estimateTranscriptionMicros,
  INFERENCE_TIMEOUT_MS,
  MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE,
  parsePositiveIntegerSetting,
  RESERVATION_EXPIRY_MS,
  TEXT_GENERATION_FLAT_MICROS,
  utcDay,
  WORST_CASE_BYTES_PER_SECOND,
  WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE,
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

test("a full 24 MB upload reserves a bounded worst-case amount for both models", () => {
  const estimate = estimateTranscriptionMicros(MAXIMUM_AUDIO_BYTES);
  const worstCaseMinutes = worstCaseAudioSeconds(MAXIMUM_AUDIO_BYTES) / 60;
  assert.equal(
    WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE,
    ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE + MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE,
    "non-English audio runs nova-3 and then whisper, so admission must price both",
  );
  assert.equal(estimate, Math.ceil(worstCaseMinutes * WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE));
  assert.ok(estimate < DEFAULT_DAILY_SPEND_LIMIT_MICROS, "one upload can never consume the whole daily budget");
  assert.ok(estimate > 200_000, "24 MB at 8 kbps is several hundred audio minutes");
});

test("actual spend is settled per model from returned duration in integer micro-dollars", () => {
  assert.equal(actualTranscriptionMicros(60, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE), ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE);
  assert.equal(actualTranscriptionMicros(90, MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE), Math.ceil(1.5 * MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE));
  assert.equal(actualTranscriptionMicros(0, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE), 0);
  assert.equal(actualTranscriptionMicros(Number.NaN, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE), 0);
  assert.equal(actualTranscriptionMicros(60, Number.NaN), 0);
  assert.ok(Number.isSafeInteger(actualTranscriptionMicros(3.33, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE)));
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
  const reservations = source.match(/\breserveSpendLogged\(env, request, \{/g) ?? [];
  const inferenceCalls = source.match(/env\.AI\.run\(/g) ?? [];
  // Enhancement, summary, and transcription each reserve once; the transcription
  // reservation prices BOTH models (nova-3 + whisper fallback) up front, so the
  // two transcription AI.run calls share one admission.
  assert.equal(reservations.length, 3, "enhancement, summary, and transcription each reserve spend");
  assert.equal(inferenceCalls.length, 4, "one text-enhancement, one summary, and two transcription models");
  // Every reservation still goes through the fail-closed ledger client: the
  // logging wrapper is the only direct reserveSpend caller.
  assert.equal((source.match(/\breserveSpend\(/g) ?? []).length, 1, "only the logging wrapper calls reserveSpend directly");
  assert.match(source, /const admission = await reserveSpend\(env, spend\);/);
  assert.match(source, /estimateMicros: estimateTranscriptionMicros\(declaredBytes\)/, "transcription admission must price the combined worst case");
  assert.match(source, /if \(!admission\.ok\) return admissionDenial\(admission\)/);
  assert.match(source, /releaseSpend\(env, admission\.id\)/);
  assert.match(source, /commitSpend\(env, admission\.id/);
  assert.match(source, /INTERNAL_CLIENT_KEY_HEADER/);
});

test("routing and fallback billing settle every model that actually ran", async () => {
  const index = await readFile(new URL("cloudflare-asr/src/index.ts", root), "utf8");
  // The routing decision itself: nova-3's result is used only when no
  // non-English language was detected; missing detection counts as English.
  assert.match(index, /const nonEnglishLanguage = detectedLanguages\.find\(\(tag\) => !isEnglishLanguageTag\(tag\)\)/);
  assert.match(index, /if \(english && nonEnglishLanguage === undefined\)/);
  // A completed nova-3 run is billed even when its output is routed away from...
  assert.match(index, /\+ \(englishBilled \? actualTranscriptionMicros\(settledSeconds, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE\) : 0\)/);
  // ...and settled rather than released when the whisper fallback then fails.
  assert.match(index, /if \(englishBilled\) \{\n\s*const billedSeconds = english\?\.durationSeconds \?\? estimatedSeconds;/);
  // Whisper's reported duration is bounded before it can null the response.
  assert.match(index, /boundedDurationSeconds\(result\.transcription_info\?\.duration\)/);
  // Buffering runs under the same deadline as inference, so a trickled upload
  // cannot pin the worker, and a mid-transfer disconnect resolves to null.
  assert.match(index, /bufferAudio\(request, mediaType, declaredBytes, deadline\)/);
});

test("buffering and admission run concurrently and a failed buffer releases the reservation", async () => {
  const index = await readFile(new URL("cloudflare-asr/src/index.ts", root), "utf8");
  // The reservation needs only declared bytes and the client key, both known
  // up front, so it does not wait for the body — and vice versa.
  assert.match(
    index,
    /const \[audioBytes, admission\] = await Promise\.all\(\[\s*bufferAudio\(request, mediaType, declaredBytes, deadline\),\s*reserveSpendLogged\(env, request, \{\s*estimateMicros: estimateTranscriptionMicros\(declaredBytes\),/,
    "bufferAudio and reserveSpend must run under one Promise.all",
  );
  // An admitted reservation whose upload then fails validation (415) must be
  // released in the background instead of squatting on daily headroom.
  assert.match(
    index,
    /if \(!audioBytes\) \{\s*if \(admission\.ok\) executionContext\.waitUntil\(releaseSpend\(env, admission\.id\)\);\s*return json\(\{ error: "The uploaded audio format is invalid" \}, \{ status: 415 \}\);/,
    "buffer failure with a successful admission must release the reservation via waitUntil",
  );
  // Paid inference still runs only behind an admitted reservation: the
  // admission gate sits before any transcription AI.run call.
  const admissionGate = index.indexOf("if (!admission.ok) return admissionDenial(admission);", index.indexOf("Promise.all"));
  const firstTranscriptionRun = index.indexOf("env.AI.run(ENGLISH_TRANSCRIPTION_MODEL_ID");
  assert.ok(admissionGate !== -1 && firstTranscriptionRun !== -1 && admissionGate < firstTranscriptionRun,
    "inference must remain gated on admission.ok");
});

test("admission clamps a single request's seconds to the daily client quota", async () => {
  // Worst-case byte pricing makes a 24 MB upload look like far more audio than
  // the whole daily quota; without the clamp every large upload would be denied.
  assert.ok(worstCaseAudioSeconds(MAXIMUM_AUDIO_BYTES) > DEFAULT_DAILY_CLIENT_AUDIO_SECONDS);
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  assert.match(ledger, /Math\.min\(request\.secondsEstimate, request\.clientSecondsLimit\)/);
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
  assert.match(config, /"DAILY_SPEND_LIMIT_MICROS": "10000000"/);
  assert.match(config, /"DAILY_CLIENT_AUDIO_SECONDS": "7200"/);
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  assert.doesNotMatch(ledger, /await[^\n]*\n[^\n]*sql\.exec[\s\S]{0,400}?await fetch/, "no external awaits between ledger reads and writes");
});

test("ledger client rows are pseudonymous, short-lived, and purged without traffic", async () => {
  const ledger = await readFile(new URL("cloudflare-asr/src/spendLedger.ts", root), "utf8");
  // Quota rows only matter for the current day; one extra day covers clock skew.
  assert.match(ledger, /CLIENT_USAGE_RETENTION_DAYS = 2/);
  assert.match(ledger, /DELETE FROM client_usage WHERE day < \?", utcDay\(now - CLIENT_USAGE_RETENTION_DAYS \* dayMs\)/);
  // An idle ledger must still purge: the alarm re-arms itself.
  assert.match(ledger, /async alarm\(\)/);
  assert.match(ledger, /setAlarm\(now \+ PURGE_ALARM_INTERVAL_MS\)/);
  assert.match(ledger, /blockConcurrencyWhile/);
});
