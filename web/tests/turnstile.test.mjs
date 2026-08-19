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
  expectedHostname: "v.paul.im",
  expectedAction: "transcribe",
};

test("a successful siteverify response with matching action and hostname passes", async () => {
  const { fetcher, calls } = siteverifyStub({ success: true, action: "transcribe", hostname: "v.paul.im" });
  const result = await verifyTurnstileToken({ ...base, fetcher });
  assert.deepEqual(result, { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.response, "test-token");
  assert.equal("remoteip" in calls[0].body, false, "client IPs must never be sent to siteverify");
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

test("recording start warms turnstile while token acquisition stays at stop time", async () => {
  const [page, request, client] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("lib/transcriptionRequest.ts", root), "utf8"),
    readFile(new URL("lib/turnstileClient.ts", root), "utf8"),
  ]);
  assert.match(client, /export function warmTranscriptionChallenge/);
  const startBody = page.slice(page.indexOf("async function startRecording"), page.indexOf("function stopRecording"));
  assert.match(startBody, /warmTranscriptionChallenge\(\)/, "startRecording must warm the widget fire-and-forget");
  // Tokens are single-use: the transcription request still acquires a fresh
  // token at stop time, and the warm path never executes a challenge.
  assert.match(request, /acquireTranscriptionToken\(\)/);
  const warmBody = client.slice(
    client.indexOf("export function warmTranscriptionChallenge"),
    client.indexOf("export async function acquireTranscriptionToken"),
  );
  assert.doesNotMatch(warmBody, /\.execute\(/, "warming must never execute a challenge");
});

test("warming renders the widget once without executing; acquisition reuses it", async (t) => {
  process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY = "test-site-key";
  const rendered = [];
  const executed = [];
  const resets = [];
  let widgetParameters = null;
  const fakeTurnstile = {
    render(container, parameters) {
      rendered.push(container);
      widgetParameters = parameters;
      return "widget-1";
    },
    execute(id) {
      executed.push(id);
      widgetParameters.callback(`token-${executed.length}`);
    },
    reset(id) {
      resets.push(id);
    },
  };
  globalThis.window = {
    turnstile: fakeTurnstile,
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (id) => clearTimeout(id),
  };
  globalThis.document = {
    getElementById: () => null,
    createElement: () => ({ id: "", style: {} }),
    head: { appendChild: () => {} },
    body: { appendChild: () => {} },
  };
  t.after(() => {
    delete globalThis.window;
    delete globalThis.document;
    delete process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  });

  const { acquireTranscriptionToken, warmTranscriptionChallenge } = await import("../lib/turnstileClient.ts");
  warmTranscriptionChallenge();
  warmTranscriptionChallenge();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(rendered.length, 1, "warming renders the widget exactly once");
  assert.equal(executed.length, 0, "warming must never execute a challenge");

  const first = await acquireTranscriptionToken();
  assert.equal(first, "token-1");
  assert.equal(rendered.length, 1, "acquisition reuses the pre-warmed widget");
  assert.deepEqual(resets, [], "a never-used widget needs no reset");

  const second = await acquireTranscriptionToken();
  assert.equal(second, "token-2");
  assert.deepEqual(resets, ["widget-1"], "single-use tokens require a reset before re-execution");
  assert.equal(rendered.length, 1);
});
