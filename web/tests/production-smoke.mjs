import assert from "node:assert/strict";

const argumentIndex = process.argv.indexOf("--base-url");
const configuredBase = argumentIndex >= 0 ? process.argv[argumentIndex + 1] : undefined;
const base = (configuredBase ?? process.env.VOICEINK_PRODUCTION_URL ?? "https://v.paul.im").replace(/\/$/, "");
const noStore = /\bno-store\b/i;

const home = await fetch(base, { redirect: "error", cache: "no-store" });
assert.equal(home.status, 200);
assert.match(home.headers.get("content-security-policy") ?? "", /script-src 'nonce-/);
assert.doesNotMatch(home.headers.get("content-security-policy") ?? "", /script-src[^;]*\bhttps:\s+http:/);
assert.match(home.headers.get("strict-transport-security") ?? "", /max-age=31536000/);
assert.equal(home.headers.get("x-content-type-options"), "nosniff");
assert.match(home.headers.get("cache-control") ?? "", noStore);
const html = await home.text();
assert.match(html, /VoiceInk/);

const assetPath = html.match(/(?:href|src)="(\/_next\/static\/[^"]+)"/)?.[1];
assert.ok(assetPath, "A content-hashed production asset must be discoverable");
const asset = await fetch(`${base}${assetPath}`, { redirect: "error" });
assert.equal(asset.status, 200);
assert.match(asset.headers.get("cache-control") ?? "", /max-age=31536000/i);
assert.match(asset.headers.get("cache-control") ?? "", /immutable/i);
const publicMedia = await fetch(`${base}/og.png`, { redirect: "error" });
assert.equal(publicMedia.status, 200);
assert.match(publicMedia.headers.get("cache-control") ?? "", /max-age=3600/i);
assert.doesNotMatch(publicMedia.headers.get("cache-control") ?? "", /immutable/i);

for (const endpoint of ["summarize", "enhance"]) {
  const response = await fetch(`${base}/api/${endpoint}`, {
    method: "POST",
    headers: { origin: "https://example.invalid", "content-type": "application/json" },
    body: JSON.stringify({ text: "This request must not reach inference.", mode: "clean" }),
  });
  assert.equal(response.status, 403);
  assert.match(response.headers.get("cache-control") ?? "", noStore);
}

const anonymousHistory = await fetch(`${base}/api/history`, {
  headers: { origin: base, "x-voiceink-client-id": crypto.randomUUID() },
  cache: "no-store",
});
assert.equal(anonymousHistory.status, 200);
assert.match(anonymousHistory.headers.get("content-type") ?? "", /application\/json/i);
assert.match(anonymousHistory.headers.get("cache-control") ?? "", noStore);
const history = await anonymousHistory.json();
assert.deepEqual(history.items, []);
assert.equal(history.retentionDays, null);
assert.equal(history.nextCursor, null);

console.log(`Production smoke checks passed for ${base}`);
