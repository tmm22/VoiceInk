import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

// The Worker entry replaces the framework router: API dispatch by path and
// method, the nonce-stamped document, and asset fallthrough. HTMLRewriter
// exists only in the Workers runtime, so nonce stamping is verified against
// production by tests/production-smoke.mjs; everything else runs here.
register("./support/workers-loader.mjs", import.meta.url);
const { default: worker } = await import("../worker/index.ts");

const origin = "https://v.paul.im";
const assets = {
  requests: [],
  async fetch(request) {
    this.requests.push(new URL(request.url).pathname);
    return new URL(request.url).pathname === "/missing.js"
      ? new Response("Not found", { status: 404 })
      : new Response("asset", { headers: { "Cache-Control": "public, max-age=31536000, immutable" } });
  },
};
const call = (path, init) => worker.fetch(new Request(`${origin}${path}`, init), { ASSETS: assets });

function assertSecured(response, { api }) {
  assert.match(response.headers.get("content-security-policy") ?? "", /script-src 'nonce-[^']+' 'strict-dynamic'/);
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  if (api) {
    assert.equal(response.headers.get("cache-control"), "private, no-store, max-age=0, must-revalidate");
    assert.equal(response.headers.get("link"), null);
  } else {
    assert.match(response.headers.get("link") ?? "", /rel=preconnect/);
  }
}

test("unknown API paths are a bounded 404 with private API headers", async () => {
  const response = await call("/api/nope");
  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "Not found." });
  assertSecured(response, { api: true });
});

test("unsupported methods get 405 with an accurate Allow header, and OPTIONS lists the methods", async () => {
  const wrongMethod = await call("/api/summarize", { method: "PUT" });
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get("allow"), "POST, OPTIONS");
  assertSecured(wrongMethod, { api: true });
  const options = await call("/api/history", { method: "OPTIONS" });
  assert.equal(options.status, 204);
  assert.equal(options.headers.get("allow"), "GET, POST, PATCH, DELETE, HEAD, OPTIONS");
});

test("API requests reach their route handler, and HEAD runs GET without a body", async () => {
  // Cross-origin rejection is the first thing every costly route does, so a
  // 403 proves dispatch reached the real handler.
  const crossOrigin = await call("/api/summarize", {
    method: "POST",
    headers: { origin: "https://evil.example", "content-type": "application/json" },
    body: "{}",
  });
  assert.equal(crossOrigin.status, 403);
  assertSecured(crossOrigin, { api: true });
  const head = await call("/api/history", { method: "HEAD", headers: { origin: "https://evil.example" } });
  assert.equal(head.status, 403);
  assert.equal(await head.text(), "");
});

test("an unexpected handler throw becomes a bounded 500 that logs metadata only", async () => {
  const request = new Request(`${origin}/api/summarize`, { method: "POST" });
  Object.defineProperty(request, "headers", { get() { throw new TypeError("sensitive internal detail"); } });
  const logged = [];
  const originalError = console.error;
  console.error = (...args) => logged.push(args);
  try {
    const response = await worker.fetch(request, { ASSETS: assets });
    assert.equal(response.status, 500);
    const body = await response.text();
    assert.doesNotMatch(body, /sensitive internal detail/);
    assertSecured(response, { api: true });
  } finally {
    console.error = originalError;
  }
  assert.equal(logged.length, 1);
  assert.equal(logged[0][0], "voiceink_route_unhandled_error");
  assert.deepEqual(logged[0][1], { route: "/api/summarize", method: "POST", errorName: "TypeError" });
  assert.doesNotMatch(JSON.stringify(logged), /sensitive internal detail/);
});

test("the document only answers GET and HEAD, never cached", async () => {
  const post = await call("/", { method: "POST" });
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("allow"), "GET, HEAD");
  const head = await call("/", { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("cache-control"), "no-store, must-revalidate");
  assert.equal(await head.text(), "");
  assertSecured(head, { api: false });
});

test("other paths fall through to the assets layer with security headers", async () => {
  assets.requests.length = 0;
  const miss = await call("/missing.js");
  assert.equal(miss.status, 404);
  assertSecured(miss, { api: false });
  assert.deepEqual(assets.requests, ["/missing.js"]);
});
