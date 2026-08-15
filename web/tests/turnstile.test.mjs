import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { verifyTurnstileToken } from "../lib/server/turnstile.ts";

const root = new URL("../", import.meta.url);

function siteverifyStub(body, { status = 200 } = {}) {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, body: JSON.parse(init.body) });
    const payload = typeof body === "function" ? body(calls.length) : body;
    return new Response(JSON.stringify(payload), { status });
  };
  return { fetcher, calls };
}

const base = {
  token: "test-token",
  secret: "test-secret",
  remoteIp: "203.0.113.7",
  expectedHostname: "v.paul.im",
  expectedAction: "transcribe",
};

test("a successful siteverify response with matching action and hostname passes", async () => {
  const { fetcher, calls } = siteverifyStub({ success: true, action: "transcribe", hostname: "v.paul.im" });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.deepEqual(result, { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.response, "test-token");
  assert.equal(calls[0].body.remoteip, "203.0.113.7");
  assert.ok(calls[0].body.idempotency_key);
});

test("missing or oversized tokens are rejected without calling siteverify", async () => {
  const { fetcher, calls } = siteverifyStub({ success: true });
  const missing = await verifyTurnstileToken({ ...base, token: null, fetcher });
  assert.equal(missing.ok, false);
  assert.equal(missing.status, 403);
  const oversized = await verifyTurnstileToken({ ...base, token: "x".repeat(3000), fetcher });
  assert.equal(oversized.ok, false);
  assert.equal(calls.length, 0);
});

test("action and hostname mismatches fail even when siteverify succeeds", async () => {
  const wrongAction = siteverifyStub({ success: true, action: "login", hostname: "v.paul.im" });
  const actionResult = await verifyTurnstileToken({ ...base, fetcher: wrongAction.fetcher });
  assert.equal(actionResult.ok, false);
  assert.equal(actionResult.status, 403);
  const wrongHost = siteverifyStub({ success: true, action: "transcribe", hostname: "evil.example.net" });
  const hostResult = await verifyTurnstileToken({ ...base, fetcher: wrongHost.fetcher });
  assert.equal(hostResult.ok, false);
});

test("an absent action or hostname is rejected, never silently accepted", async () => {
  const noAction = siteverifyStub({ success: true, hostname: "v.paul.im" });
  assert.equal((await verifyTurnstileToken({ ...base, fetcher: noAction.fetcher })).ok, false);
  const noHost = siteverifyStub({ success: true, action: "transcribe" });
  assert.equal((await verifyTurnstileToken({ ...base, fetcher: noHost.fetcher })).ok, false);
});

test("the documented test-key hostname is accepted so dev uses the production code path", async () => {
  const { fetcher } = siteverifyStub({ success: true, action: "transcribe", hostname: "example.com" });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.deepEqual(result, { ok: true });
});

test("expired or replayed tokens are a retryable client failure", async () => {
  const { fetcher } = siteverifyStub({ success: false, "error-codes": ["timeout-or-duplicate"] });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.equal(result.ok, false);
  assert.equal(result.status, 403);
});

test("configuration errors fail closed as unavailable", async () => {
  const { fetcher } = siteverifyStub({ success: false, "error-codes": ["invalid-input-secret"] });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.equal(result.ok, false);
  assert.equal(result.status, 503);
});

test("a transient internal error is retried once with the same idempotency key", async () => {
  const { fetcher, calls } = siteverifyStub((attempt) => attempt === 1
    ? { success: false, "error-codes": ["internal-error"] }
    : { success: true, action: "transcribe", hostname: "v.paul.im" });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.deepEqual(result, { ok: true });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].body.idempotency_key, calls[1].body.idempotency_key);
});

test("an unreachable siteverify endpoint fails closed", async () => {
  const fetcher = async () => { throw new Error("network down"); };
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.equal(result.ok, false);
  assert.equal(result.status, 503);
});

test("the transcribe route enforces turnstile whenever the secret is configured", async () => {
  const route = await readFile(new URL("app/api/transcribe/route.ts", root), "utf8");
  assert.match(route, /process\.env\.TURNSTILE_SECRET_KEY/);
  assert.match(route, /verifyTurnstileToken\(/);
  assert.match(route, /TURNSTILE_TOKEN_HEADER/);
  assert.match(route, /expectedAction: "transcribe"/);
  const routeOrder = route.indexOf("TURNSTILE_SECRET_KEY");
  const upstreamCall = route.indexOf("bindings.ASR.fetch");
  assert.ok(routeOrder !== -1 && routeOrder < upstreamCall, "verification must run before audio is streamed upstream");
});

test("never log or echo the turnstile token or secret", async () => {
  const source = await readFile(new URL("lib/server/turnstile.ts", root), "utf8");
  assert.doesNotMatch(source, /console\./);
});
