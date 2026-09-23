import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import {
  fakeAsrEnv,
  novaResult,
  transcriptionRequest,
  wavBytes,
  whisperResult,
} from "./support/asr-fakes.mjs";

register("./support/workers-loader.mjs", import.meta.url);
const { default: worker } = await import("../cloudflare-asr/src/index.ts");

const NOVA = "@cf/deepgram/nova-3";
const WHISPER = "@cf/openai/whisper-large-v3-turbo";

async function transcribe(fake, options) {
  const response = await worker.fetch(transcriptionRequest(options), fake.env, fake.executionContext);
  await fake.settled();
  return { response, body: await response.json() };
}

test("English detected by nova-3 returns nova-3 output and settles one model", async () => {
  const fake = fakeAsrEnv({ models: { [NOVA]: () => novaResult({ languages: ["en-us"] }) } });
  const { response, body } = await transcribe(fake);
  assert.equal(response.status, 200);
  assert.deepEqual(body, { text: "Hello there.", model: "nova-3", durationSeconds: 3, detectedLanguage: "en-us" });
  assert.deepEqual(fake.calls.map((call) => call.model), [NOVA]);
  assert.equal(fake.calls[0].bytesRead, 64, "the model reads the complete upload");
  assert.deepEqual(fake.ledger.map((entry) => entry.op), ["reserve", "commit"]);
  assert.equal(fake.ledger[1].micros, Math.ceil((3 / 60) * 5_200));
});

test("non-English detected by nova-3 re-routes to whisper and settles both models", async () => {
  const fake = fakeAsrEnv({
    models: {
      [NOVA]: () => novaResult({ transcript: "ola", languages: ["es"] }),
      [WHISPER]: () => whisperResult(),
    },
  });
  const { response, body } = await transcribe(fake);
  assert.equal(response.status, 200);
  assert.equal(body.model, "whisper-large-v3-turbo");
  assert.equal(body.text, "Hola a todos.");
  assert.equal(body.detectedLanguage, "es");
  assert.deepEqual(fake.calls.map((call) => call.model), [NOVA, WHISPER]);
  assert.equal(fake.calls[1].bytesRead, 64, "whisper receives the same complete audio");
  const commit = fake.ledger.find((entry) => entry.op === "commit");
  assert.equal(commit.micros, Math.ceil((3 / 60) * 510) + Math.ceil((3 / 60) * 5_200));
});

test("missing language detection deliberately counts as English", async () => {
  const fake = fakeAsrEnv({ models: { [NOVA]: () => novaResult({ languages: null }) } });
  const { response, body } = await transcribe(fake);
  assert.equal(response.status, 200);
  assert.equal(body.model, "nova-3");
  assert.equal(body.detectedLanguage, undefined);
  assert.deepEqual(fake.calls.map((call) => call.model), [NOVA]);
});

test("a nova-3 failure falls back to whisper and bills only whisper", async () => {
  const fake = fakeAsrEnv({
    models: {
      [NOVA]: () => { throw new Error("nova unavailable"); },
      [WHISPER]: () => whisperResult({ text: "Fallback transcript." }),
    },
  });
  const { response, body } = await transcribe(fake);
  assert.equal(response.status, 200);
  assert.equal(body.model, "whisper-large-v3-turbo");
  assert.deepEqual(fake.calls.map((call) => call.model), [NOVA, WHISPER]);
  const commit = fake.ledger.find((entry) => entry.op === "commit");
  assert.equal(commit.micros, Math.ceil((3 / 60) * 510));
});

test("a whisper failure after nova-3 ran still settles the nova-3 spend", async () => {
  const fake = fakeAsrEnv({
    models: {
      [NOVA]: () => novaResult({ languages: ["fr"] }),
      [WHISPER]: () => { throw new Error("whisper unavailable"); },
    },
  });
  const { response } = await transcribe(fake);
  assert.equal(response.status, 502);
  assert.deepEqual(fake.ledger.map((entry) => entry.op), ["reserve", "commit"]);
});

test("both models failing releases the reservation and never fabricates text", async () => {
  const fake = fakeAsrEnv({
    models: {
      [NOVA]: () => { throw new Error("nova unavailable"); },
      [WHISPER]: () => { throw new Error("whisper unavailable"); },
    },
  });
  const { response, body } = await transcribe(fake);
  assert.equal(response.status, 502);
  assert.equal(body.text, undefined);
  assert.deepEqual(fake.ledger.map((entry) => entry.op), ["reserve", "release"]);
});

test("unauthorized and mislabelled uploads never reach a model", async () => {
  const cases = [
    { options: { authorization: "Bearer wrong" }, status: 401 },
    { options: { bytes: new Uint8Array(64) }, status: 415 },
    { options: { contentType: "text/plain" }, status: 415 },
    { options: { declaredBytes: 0 }, status: 400 },
    { options: { bytes: wavBytes(12), declaredBytes: 64 }, status: 415 },
  ];
  for (const { options, status } of cases) {
    const fake = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
    const { response } = await transcribe(fake, options);
    assert.equal(response.status, status, JSON.stringify(options));
    assert.equal(fake.calls.length, 0, JSON.stringify(options));
    assert.equal(fake.ledger.some((entry) => entry.op === "commit"), false);
    if (fake.ledger.some((entry) => entry.op === "reserve")) {
      assert.ok(fake.ledger.some((entry) => entry.op === "release"), "an admitted but invalid upload is released");
    }
  }
});

test("an upload longer or shorter than declared fails mid-stream without a transcript or settled spend", async () => {
  for (const declaredBytes of [32, 128]) {
    const fake = fakeAsrEnv({
      models: { [NOVA]: () => novaResult(), [WHISPER]: () => whisperResult() },
    });
    const { response, body } = await transcribe(fake, { declaredBytes });
    assert.equal(response.status, 415, `declared ${declaredBytes}`);
    assert.equal(body.text, undefined);
    assert.deepEqual(fake.calls.map((call) => call.model), [NOVA], "the fallback never runs on a rejected upload");
    assert.ok(fake.calls[0].bytesRead <= declaredBytes, "no more than the priced byte count is delivered");
    assert.deepEqual(fake.ledger.map((entry) => entry.op), ["reserve", "release"]);
  }
});

test("a model that ignores its stream error still cannot return a transcript for a mis-sized upload", async () => {
  for (const declaredBytes of [32, 128]) {
    const fake = fakeAsrEnv({ swallowStreamErrors: true, models: { [NOVA]: () => novaResult() } });
    const { response, body } = await transcribe(fake, { declaredBytes });
    assert.equal(response.status, 415, `declared ${declaredBytes}`);
    assert.equal(body.text, undefined);
    assert.deepEqual(fake.ledger.map((entry) => entry.op), ["reserve", "commit"], "the model that ran is still settled");
  }
});

test("inference starts while the upload is still arriving", async () => {
  let releaseRest;
  const rest = new Promise((resolve) => { releaseRest = resolve; });
  const bytes = wavBytes(64);
  let sent = 0;
  const body = new ReadableStream({
    async pull(controller) {
      if (sent === 16) await rest;
      if (sent >= bytes.byteLength) return controller.close();
      controller.enqueue(bytes.slice(sent, sent + 16));
      sent += 16;
    },
  });
  const fake = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
  const originalRun = fake.env.AI.run;
  fake.env.AI.run = (...args) => {
    assert.equal(sent, 16, "the model is called before the rest of the upload arrives");
    releaseRest();
    return originalRun(...args);
  };
  const request = new Request("https://asr.internal/v1/transcriptions", {
    method: "POST",
    headers: {
      authorization: "Bearer test-asr-key",
      "content-type": "audio/wav",
      "x-voiceink-body-length": "64",
    },
    body,
    duplex: "half",
  });
  const response = await worker.fetch(request, fake.env, fake.executionContext);
  assert.equal(response.status, 200);
  assert.equal(fake.calls[0].bytesRead, 64);
});

test("a confident non-English hint transcribes once with whisper at whisper's price", async () => {
  const fake = fakeAsrEnv({
    models: {
      [NOVA]: () => { throw new Error("nova must not run for a hinted request"); },
      [WHISPER]: () => whisperResult({ language: "de" }),
    },
  });
  const { response, body } = await transcribe(fake, { headers: { "x-voiceink-language-hint": "de-DE" } });
  assert.equal(response.status, 200);
  assert.equal(body.model, "whisper-large-v3-turbo");
  assert.equal(body.detectedLanguage, "de");
  assert.deepEqual(fake.calls.map((call) => call.model), [WHISPER]);
  assert.equal(fake.calls[0].bytesRead, 64);
  const reserve = fake.ledger.find((entry) => entry.op === "reserve");
  const unhinted = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
  await transcribe(unhinted);
  assert.ok(reserve.request.estimateMicros < unhinted.ledger[0].request.estimateMicros, "only whisper is priced");
  const commit = fake.ledger.find((entry) => entry.op === "commit");
  assert.equal(commit.micros, Math.ceil((3 / 60) * 510));
});

test("English or malformed hints keep the nova-3-first route", async () => {
  for (const hint of ["en-GB", "EN", "not a tag", "x"]) {
    const fake = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
    const { body } = await transcribe(fake, { headers: { "x-voiceink-language-hint": hint } });
    assert.equal(body.model, "nova-3", hint);
    assert.deepEqual(fake.calls.map((call) => call.model), [NOVA]);
  }
});

test("a ledger denial blocks inference", async () => {
  for (const [reason, status] of [["budget", 429], ["client", 429], ["unavailable", 503]]) {
    const fake = fakeAsrEnv({ admission: { ok: false, reason }, models: { [NOVA]: () => novaResult() } });
    const { response } = await transcribe(fake, { bytes: wavBytes(48) });
    assert.equal(response.status, status);
    assert.equal(fake.calls.length, 0);
  }
});

test("a missing or failing ledger binding denies inference as unavailable", async () => {
  const missing = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
  delete missing.env.SPEND_LEDGER;
  const throwing = fakeAsrEnv({ models: { [NOVA]: () => novaResult() } });
  throwing.env.SPEND_LEDGER = { idFromName: (name) => name, get: () => ({ reserve: async () => { throw new Error("ledger down"); } }) };
  for (const fake of [missing, throwing]) {
    const { response } = await transcribe(fake, { bytes: wavBytes(48) });
    assert.equal(response.status, 503);
    assert.equal(fake.calls.length, 0);
  }
});

test("a model that stops reading early cannot return a transcript for an unvalidated upload", async () => {
  for (const [models, name] of [
    [{ [NOVA]: () => novaResult() }, "nova-3"],
    [{ [NOVA]: () => { throw new Error("nova down"); }, [WHISPER]: () => whisperResult() }, "whisper"],
  ]) {
    const fake = fakeAsrEnv({ readLimit: 16, models });
    const { response, body } = await transcribe(fake, { declaredBytes: 128 });
    assert.equal(response.status, 415, name);
    assert.equal(body.text, undefined);
    assert.equal(fake.ledger.at(-1).op, "commit", "the model that ran is settled");
  }
});
