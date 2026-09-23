import assert from "node:assert/strict";
import test from "node:test";
import { openAudioUpload } from "../cloudflare-asr/src/audioUpload.ts";
import { chunkedStream, wavBytes } from "./support/asr-fakes.mjs";

async function drain(stream) {
  const chunks = [];
  const reader = stream.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(...value);
  }
  return new Uint8Array(chunks);
}

test("an exact-length upload streams every byte, including the signature prefix", async () => {
  const bytes = wavBytes(100);
  const upload = await openAudioUpload(chunkedStream(bytes, 7), "audio/wav", 100, new AbortController().signal);
  assert.ok(upload);
  assert.deepEqual(await drain(upload.stream), bytes);
  assert.equal(upload.rejected(), false);
});

test("a tiny upload delivered in one chunk still validates its length", async () => {
  const bytes = wavBytes(16);
  const upload = await openAudioUpload(chunkedStream(bytes, 64), "audio/wav", 16, new AbortController().signal);
  assert.ok(upload);
  assert.deepEqual(await drain(upload.stream), bytes);
});

test("bodies longer or shorter than declared error mid-stream and are marked rejected", async () => {
  for (const declared of [40, 200]) {
    const upload = await openAudioUpload(chunkedStream(wavBytes(100), 16), "audio/wav", declared, new AbortController().signal);
    assert.ok(upload, `declared ${declared}`);
    await assert.rejects(drain(upload.stream));
    assert.equal(upload.rejected(), true);
  }
});

test("the stream never delivers more than the declared byte count", async () => {
  const upload = await openAudioUpload(chunkedStream(wavBytes(100), 16), "audio/wav", 40, new AbortController().signal);
  const reader = upload.stream.getReader();
  let delivered = 0;
  await assert.rejects((async () => {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return;
      delivered += value.byteLength;
    }
  })());
  assert.ok(delivered <= 40, `delivered ${delivered}`);
});

test("a signature mismatch, a short prefix, or an oversized prefix returns null", async () => {
  const signal = new AbortController().signal;
  assert.equal(await openAudioUpload(chunkedStream(new Uint8Array(64)), "audio/wav", 64, signal), null);
  assert.equal(await openAudioUpload(chunkedStream(wavBytes(64)), "audio/webm", 64, signal), null);
  assert.equal(await openAudioUpload(chunkedStream(wavBytes(12)), "audio/wav", 64, signal), null);
  assert.equal(await openAudioUpload(chunkedStream(wavBytes(64), 64), "audio/wav", 32, signal), null);
  assert.equal(await openAudioUpload(null, "audio/wav", 64, signal), null);
});

test("an abort errors the stream without marking the upload rejected", async () => {
  const controller = new AbortController();
  let sent = 0;
  const bytes = wavBytes(64);
  const body = new ReadableStream({
    async pull(stream) {
      if (sent >= 16) return new Promise(() => {});
      stream.enqueue(bytes.slice(0, 16));
      sent = 16;
    },
  });
  const upload = await openAudioUpload(body, "audio/wav", 64, controller.signal);
  const pending = drain(upload.stream);
  controller.abort(new Error("deadline"));
  await assert.rejects(pending, /deadline/);
  assert.equal(upload.rejected(), false);
});

test("a client that stalls before the signature bytes is released by the deadline", async () => {
  const controller = new AbortController();
  const body = new ReadableStream({
    start(stream) { stream.enqueue(new Uint8Array([0x52, 0x49])); },
    pull() { return new Promise(() => {}); },
  });
  const pending = openAudioUpload(body, "audio/wav", 64, controller.signal);
  controller.abort(new Error("deadline"));
  assert.equal(await pending, null);
});
