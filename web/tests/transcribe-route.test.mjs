import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import { allowStreamedRequestBodies, wavBytes } from "./support/asr-fakes.mjs";

allowStreamedRequestBodies();

register("./support/workers-loader.mjs", import.meta.url);
const { env } = await import("cloudflare:workers");
const { POST } = await import("../app/api/transcribe/route.ts");

const origin = "https://v.paul.im";

function installBindings({ asr, rateLimited = false } = {}) {
  const forwarded = [];
  env.TRANSCRIPTION_RATE_LIMITER = { limit: async () => ({ success: !rateLimited }) };
  env.ASR = asr === null ? undefined : {
    async fetch(request) {
      const bytes = new Uint8Array(await request.arrayBuffer());
      forwarded.push({ request, bytes });
      return asr ? asr(request) : Response.json({ text: "Hello.", model: "nova-3" });
    },
  };
  process.env.PARAKEET_API_KEY = "web-to-asr-key";
  process.env.HISTORY_ENCRYPTION_KEY = "pseudonym-secret";
  delete process.env.TURNSTILE_SECRET_KEY;
  return forwarded;
}

function upload({ bytes = wavBytes(), headers = {} } = {}) {
  return new Request(`${origin}/api/transcribe`, {
    method: "POST",
    headers: {
      origin,
      "content-type": "audio/wav",
      "content-length": String(bytes.byteLength),
      "cf-connecting-ip": "203.0.113.9",
      ...headers,
    },
    body: bytes,
  });
}

test("the route pipes the raw audio to the private ASR binding with internal headers", async () => {
  const forwarded = installBindings();
  const response = await POST(upload());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: "Hello.", model: "nova-3" });
  assert.equal(forwarded.length, 1);
  const [{ request, bytes }] = forwarded;
  assert.equal(new URL(request.url).pathname, "/v1/transcriptions");
  assert.equal(request.headers.get("authorization"), "Bearer web-to-asr-key");
  assert.equal(request.headers.get("content-type"), "audio/wav");
  assert.equal(request.headers.get("x-voiceink-body-length"), "64");
  assert.ok(request.headers.get("x-voiceink-client-key"), "a pseudonymous client key is forwarded");
  assert.notEqual(request.headers.get("x-voiceink-client-key"), "203.0.113.9", "the raw IP is never forwarded");
  assert.deepEqual(bytes, wavBytes());
});

test("the route rejects cross-origin, unsupported, oversized, and rate-limited uploads before the ASR hop", async () => {
  const cases = [
    { request: () => upload({ headers: { origin: "https://evil.example" } }), status: 403 },
    { request: () => upload({ headers: { "content-type": "text/plain" } }), status: 415 },
    { request: () => upload({ headers: { "content-length": String(25 * 1024 * 1024) } }), status: 413 },
    { request: () => upload(), status: 429, rateLimited: true },
  ];
  for (const { request, status, rateLimited } of cases) {
    const forwarded = installBindings({ rateLimited });
    const response = await POST(request());
    assert.equal(response.status, status);
    assert.equal(forwarded.length, 0);
  }
});

test("the route fails closed when the ASR binding or its credential is missing", async () => {
  installBindings({ asr: null });
  assert.equal((await POST(upload())).status, 503);
  installBindings();
  delete process.env.PARAKEET_API_KEY;
  assert.equal((await POST(upload())).status, 503);
});

test("ASR failures map to bounded errors and never leak the upstream body", async () => {
  const cases = [
    { asr: () => Response.json({ error: "secret detail" }, { status: 500 }), status: 502 },
    { asr: () => Response.json({ error: "busy" }, { status: 429 }), status: 429 },
    { asr: () => Response.json({ error: "bad" }, { status: 415 }), status: 415 },
    { asr: () => new Response("<html>", { headers: { "content-type": "text/html" } }), status: 502 },
    { asr: () => Response.json({ text: "", model: "nova-3" }), status: 502 },
    { asr: () => { throw new Error("binding down"); }, status: 502 },
  ];
  for (const { asr, status } of cases) {
    installBindings({ asr });
    const response = await POST(upload());
    assert.equal(response.status, status);
    const body = await response.text();
    assert.doesNotMatch(body, /secret detail|binding down|html/);
  }
});
