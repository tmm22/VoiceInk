import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  boundedDurationSeconds,
  confidentNonEnglishLanguageHint,
  ENGLISH_TRANSCRIPTION_MODEL_NAME,
  hasMatchingAudioSignature,
  isEnglishLanguageTag,
  isSupportedAudioMediaType,
  isValidLanguageTag,
  MAXIMUM_TRANSCRIPT_CHARACTERS,
  MULTILINGUAL_TRANSCRIPTION_MODEL_NAME,
  parseLanguageHint,
  parseTranscriptionResponse,
} from "../shared/transcriptionContract.ts";
import { extractDeepgramTranscription } from "../cloudflare-asr/src/deepgram.ts";
import {
  jsonNoStore,
  readBoundedJson,
  validateDeclaredBodySize,
  validateMultipartContentType,
} from "../lib/server/requestValidation.ts";
import { asrWorkerSource } from "./support/sources.mjs";

function request(headers = {}) {
  return new Request("https://v.paul.im/api/transcribe", { method: "POST", headers });
}

test("strict declared body sizes reject missing, malformed, empty, and oversized uploads", () => {
  assert.equal(validateDeclaredBodySize(request(), 100).ok, false);
  for (const value of ["", "0", "-1", "1.5", "NaN"]) {
    const result = validateDeclaredBodySize(request({ "content-length": value }), 100);
    assert.equal(result.ok, false, value);
    if (!result.ok) assert.equal(result.response.status, 400, value);
  }
  const oversized = validateDeclaredBodySize(request({ "content-length": "101" }), 100);
  assert.equal(oversized.ok, false);
  if (!oversized.ok) assert.equal(oversized.response.status, 413);
  assert.deepEqual(validateDeclaredBodySize(request({ "content-length": "100" }), 100), { ok: true, bytes: 100 });
});

test("multipart validation requires a bounded boundary parameter", () => {
  for (const contentType of [
    "application/json",
    "multipart/form-data",
    "multipart/form-data; boundary=",
    `multipart/form-data; boundary=${"a".repeat(71)}`,
  ]) {
    const result = validateMultipartContentType(request({ "content-type": contentType }));
    assert.equal(result.ok, false, contentType);
    if (!result.ok) assert.equal(result.response.status, 415);
  }
  const valid = validateMultipartContentType(request({ "content-type": "multipart/form-data; boundary=----voiceink" }));
  assert.deepEqual(valid, { ok: true, contentType: "multipart/form-data; boundary=----voiceink" });
});

test("private JSON responses disable caching and MIME sniffing", () => {
  const response = jsonNoStore({ ok: true });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("pragma"), "no-cache");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});

test("bounded JSON rejects wrong types, lying lengths, and actual overflow before parsing", async () => {
  const makeJson = (body, length = new TextEncoder().encode(body).byteLength, contentType = "application/json") => new Request(
    "https://v.paul.im/api/history",
    { method: "POST", headers: { "content-type": contentType, "content-length": String(length) }, body },
  );
  const valid = await readBoundedJson(makeJson('{"ok":true}'), 20);
  assert.equal(valid.ok, true);
  const wrongType = await readBoundedJson(makeJson("{}", 2, "text/plain"), 20);
  assert.equal(wrongType.ok, false);
  if (!wrongType.ok) assert.equal(wrongType.response.status, 415);
  const lying = await readBoundedJson(makeJson('{"ok":true}', 2), 20);
  assert.equal(lying.ok, false);
  if (!lying.ok) assert.equal(lying.response.status, 400);
  const overflow = await readBoundedJson(makeJson('{"value":"too large"}', 5), 10);
  assert.equal(overflow.ok, false);
  if (!overflow.ok) assert.equal(overflow.response.status, 413);
});

test("audio media types require matching container signatures", () => {
  const bytes = (value) => new TextEncoder().encode(value);
  assert.equal(isSupportedAudioMediaType("audio/webm;codecs=opus"), true);
  assert.equal(isSupportedAudioMediaType("text/plain"), false);
  assert.equal(hasMatchingAudioSignature("audio/webm", new Uint8Array([0x1a, 0x45, 0xdf, 0xa3])), true);
  assert.equal(hasMatchingAudioSignature("audio/ogg", bytes("OggS")), true);
  assert.equal(hasMatchingAudioSignature("audio/flac", bytes("fLaC")), true);
  assert.equal(hasMatchingAudioSignature("audio/wav", bytes("RIFF0000WAVE")), true);
  assert.equal(hasMatchingAudioSignature("audio/mpeg", bytes("ID3")), true);
  assert.equal(hasMatchingAudioSignature("audio/webm", bytes("not audio")), false);
});

test("transcription responses require bounded nonempty text and a canonical model", () => {
  assert.deepEqual(parseTranscriptionResponse({ text: "  hello  ", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME, durationSeconds: 1.5, segments: [{ start: 0.1, end: 1.4, text: " hello " }] }), {
    text: "hello",
    model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME,
    durationSeconds: 1.5,
    segments: [{ start: 0.1, end: 1.4, text: "hello" }],
  });
  assert.deepEqual(parseTranscriptionResponse({ text: "Hello there.", model: ENGLISH_TRANSCRIPTION_MODEL_NAME, durationSeconds: 2, detectedLanguage: "EN-us" }), {
    text: "Hello there.",
    model: ENGLISH_TRANSCRIPTION_MODEL_NAME,
    durationSeconds: 2,
    detectedLanguage: "en-us",
  });
  for (const candidate of [
    null,
    { text: "", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME },
    { text: "hello", model: "other" },
    { text: "hello", model: "@cf/deepgram/nova-3" },
    { text: "x".repeat(MAXIMUM_TRANSCRIPT_CHARACTERS + 1), model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME },
    { text: "hello", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME, durationSeconds: Number.NaN },
    { text: "hello", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME, durationSeconds: -1 },
    { text: "hello", model: ENGLISH_TRANSCRIPTION_MODEL_NAME, detectedLanguage: "" },
    { text: "hello", model: ENGLISH_TRANSCRIPTION_MODEL_NAME, detectedLanguage: "english language" },
    { text: "hello", model: ENGLISH_TRANSCRIPTION_MODEL_NAME, detectedLanguage: "a".repeat(36) },
    { text: "hello", model: ENGLISH_TRANSCRIPTION_MODEL_NAME, detectedLanguage: 3 },
    { text: "hello", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME, segments: [{ start: 2, end: 1, text: "bad" }] },
    { text: "hello", model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME, segments: [{ start: 1, end: 2, text: "later" }, { start: 0, end: 1, text: "earlier" }] },
  ]) assert.equal(parseTranscriptionResponse(candidate), null);
});

test("absurd provider durations are dropped instead of rejecting the transcript", () => {
  assert.equal(boundedDurationSeconds(4.2), 4.2);
  for (const value of [Number.NaN, -1, 0, Number.POSITIVE_INFINITY, 21_601, "4.2", null, undefined]) {
    assert.equal(boundedDurationSeconds(value), undefined, String(value));
  }
});

test("language tags are validated and routed to English strictly", () => {
  for (const tag of ["en", "en-US", "es", "es-419", "zh-hans", "pt-BR"]) assert.equal(isValidLanguageTag(tag), true, tag);
  for (const tag of ["", "e", "english language", "en_US", "-en", "a".repeat(36), 7, null]) assert.equal(isValidLanguageTag(tag), false, String(tag));
  for (const tag of ["en", "en-US", "EN", "en-GB"]) assert.equal(isEnglishLanguageTag(tag), true, tag);
  for (const tag of ["es", "eng", "de", "enx"]) assert.equal(isEnglishLanguageTag(tag), false, tag);
});

test("Deepgram responses yield bounded transcript, languages, and duration", () => {
  // Live Workers AI nova-3 shape: languages array on the alternative.
  const live = extractDeepgramTranscription({
    metadata: { duration: 12.4 },
    results: { channels: [{ alternatives: [{ transcript: " Hello, world. ", languages: ["EN"], words: [{ word: "hello", start: 0.2, end: 0.8 }] }] }] },
  });
  assert.deepEqual(live, { text: "Hello, world.", detectedLanguages: ["en"], durationSeconds: 12.4 });

  // Code-switched audio reports every spoken language, deduplicated.
  const mixed = extractDeepgramTranscription({
    results: { channels: [{ alternatives: [{ transcript: "Hola. Hello.", languages: ["es", "en", "es"] }] }] },
  });
  assert.deepEqual(mixed?.detectedLanguages, ["es", "en"]);

  // Deepgram's single-language shape stays supported as a fallback.
  const fallbackShape = extractDeepgramTranscription({
    results: { channels: [{ alternatives: [{ transcript: "Hola.", words: [{ word: "hola", start: 0.1, end: 1.9 }] }], detected_language: "es" }] },
  });
  assert.deepEqual(fallbackShape, { text: "Hola.", detectedLanguages: ["es"], durationSeconds: 1.9 });

  // The paragraphs feature returns newline-broken text on a sibling field; it
  // must win over the flat transcript, and fall back cleanly when absent.
  const withParagraphs = extractDeepgramTranscription({
    results: { channels: [{ alternatives: [{ transcript: "One. Two.", paragraphs: { transcript: " One.\n\nTwo. " } }] }] },
  });
  assert.equal(withParagraphs?.text, "One.\n\nTwo.");
  const emptyParagraphs = extractDeepgramTranscription({
    results: { channels: [{ alternatives: [{ transcript: "One. Two.", paragraphs: { transcript: "  " } }] }] },
  });
  assert.equal(emptyParagraphs?.text, "One. Two.");

  for (const candidate of [
    null,
    {},
    { results: {} },
    { results: { channels: [] } },
    { results: { channels: [{ alternatives: [] }] } },
    { results: { channels: [{ alternatives: [{ transcript: "   " }] }] } },
    { results: { channels: [{ alternatives: [{ transcript: 42 }] }] } },
  ]) assert.equal(extractDeepgramTranscription(candidate), null, JSON.stringify(candidate));

  const badMetadata = extractDeepgramTranscription({
    metadata: { duration: -3 },
    results: { channels: [{ detected_language: "not a language tag!", alternatives: [{ transcript: "ok", languages: ["totally invalid tag"] }] }] },
  });
  assert.deepEqual(badMetadata, { text: "ok", detectedLanguages: [] });
});

test("Workers AI calls omit runtime-broken request tags", async () => {
  const source = await asrWorkerSource();
  assert.doesNotMatch(source, /\btags\s*:/, "Cloudflare currently counts tag-string characters as tags and rejects these calls");
});

test("a language hint is confident only when no preferred language is English", () => {
  assert.equal(confidentNonEnglishLanguageHint(["de-DE", "fr"]), "de-de");
  assert.equal(confidentNonEnglishLanguageHint(["es-419"]), "es-419");
  assert.equal(confidentNonEnglishLanguageHint(["de-DE", "en-US"]), null, "English anywhere keeps nova-3 first");
  assert.equal(confidentNonEnglishLanguageHint(["en"]), null);
  const many = Array.from({ length: 20 }, (_, index) => (index === 19 ? "en-GB" : "de"));
  assert.equal(confidentNonEnglishLanguageHint(many), null, "English late in a long list still counts");
  assert.equal(confidentNonEnglishLanguageHint([]), null);
  assert.equal(confidentNonEnglishLanguageHint(["", 42, "not a tag"]), null);
  assert.equal(parseLanguageHint("ja"), "ja");
  assert.equal(parseLanguageHint("en-AU"), null);
  assert.equal(parseLanguageHint("ja; drop table"), null);
  assert.equal(parseLanguageHint(null), null);
});

test("Convex validates history rows with the shared contract, not an inlined copy", async () => {
  const transcriptions = await readFile(new URL("../convex/transcriptions.ts", import.meta.url), "utf8");
  assert.match(transcriptions, /from "\.\.\/shared\/transcriptionContract"/);
  assert.match(transcriptions, /isTranscriptionModelName\(args\.model\)/);
  assert.match(transcriptions, /isValidLanguageTag\(args\.detectedLanguage\)/);
  assert.match(transcriptions, /args\.durationSeconds > MAXIMUM_TRANSCRIPTION_DURATION_SECONDS/);
  assert.match(transcriptions, /segment\.end > MAXIMUM_TRANSCRIPTION_DURATION_SECONDS/);
  assert.doesNotMatch(transcriptions, /"nova-3"|"whisper-large-v3-turbo"|21_600|\[a-z\]\{2,3\}/, "no drifting copies of contract constants");
});
