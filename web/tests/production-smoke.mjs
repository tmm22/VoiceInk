import assert from "node:assert/strict";
import { clerkScriptUrlsFor } from "../lib/clerkScripts.ts";

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
// The shell is prerendered, so the interface is in the HTML before any script.
assert.match(html, /Ready to record/);
// Every script and module preload must carry this response's CSP nonce, or
// the page cannot boot under 'strict-dynamic'. This exercises the Worker's
// HTMLRewriter stamping in the real runtime.
const cspNonce = home.headers.get("content-security-policy")?.match(/'nonce-([^']+)'/)?.[1];
const scriptTags = html.match(/<script\b[^>]*>/g) ?? [];
assert.ok(scriptTags.length > 0, "The document must load its application script");
for (const tag of [...scriptTags, ...(html.match(/<link\b[^>]*rel="modulepreload"[^>]*>/g) ?? [])]) {
  assert.equal(tag.match(/\bnonce="([^"]+)"/)?.[1], cspNonce, `${tag} must carry the response's CSP nonce`);
}

const assetPath = html.match(/(?:href|src)="(\/assets\/[^"]+)"/)?.[1];
assert.ok(assetPath, "A content-hashed production asset must be discoverable");
const asset = await fetch(`${base}${assetPath}`, { redirect: "error" });
assert.equal(asset.status, 200);
assert.match(asset.headers.get("cache-control") ?? "", /max-age=31536000/i);
assert.match(asset.headers.get("cache-control") ?? "", /immutable/i);
// Both pinned Clerk scripts must resolve directly: a redirect would mean the
// pin no longer exists on Clerk's CDN (or was replaced by a moving tag), and
// signed-in visits would fail or lose caching. The Clerk origin comes from the
// document's preconnect Link header, so no publishable key is needed here.
const clerkOrigin = home.headers.get("link")?.match(/<(https:\/\/clerk\.[^>]+)>/)?.[1];
assert.ok(clerkOrigin, "The document must preconnect to the Clerk frontend API");
const clerkScripts = clerkScriptUrlsFor(clerkOrigin);
for (const scriptUrl of [clerkScripts.js, clerkScripts.ui]) {
  const script = await fetch(scriptUrl, { redirect: "error" });
  assert.equal(script.status, 200, `${scriptUrl} must resolve without a redirect`);
  assert.match(script.headers.get("content-type") ?? "", /javascript/);
  await script.body?.cancel();
}
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
