import assert from "node:assert/strict";

const base = process.env.VOICEINK_PRODUCTION_URL ?? "https://v.paul.im";

const home = await fetch(base, { redirect: "error" });
assert.equal(home.status, 200);
assert.match(home.headers.get("content-security-policy") ?? "", /script-src 'nonce-/);
assert.match(home.headers.get("strict-transport-security") ?? "", /max-age=31536000/);
assert.equal(home.headers.get("x-content-type-options"), "nosniff");
assert.match(await home.text(), /VoiceInk/);

const crossOrigin = await fetch(`${base}/api/summarize`, {
  method: "POST",
  headers: { origin: "https://example.invalid", "content-type": "application/json" },
  body: JSON.stringify({ text: "This request must not reach inference." }),
});
assert.equal(crossOrigin.status, 403);

const asrHealth = await fetch("https://voiceink-asr.paul-2eb.workers.dev/");
assert.equal(asrHealth.status, 200);
assert.equal((await asrHealth.json()).model, "@cf/openai/whisper-large-v3-turbo");

const directAsr = await fetch("https://voiceink-asr.paul-2eb.workers.dev/v1/summaries", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ text: "Must be unauthorized before inference." }),
});
assert.equal(directAsr.status, 401);

console.log(`Production smoke checks passed for ${base}`);
