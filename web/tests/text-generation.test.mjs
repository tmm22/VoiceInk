import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";
import { allowStreamedRequestBodies, fakeAsrEnv, TEST_ASR_KEY } from "./support/asr-fakes.mjs";

allowStreamedRequestBodies();
register("./support/workers-loader.mjs", import.meta.url);
const { default: worker } = await import("../cloudflare-asr/src/index.ts");
const { generatedText } = await import("../cloudflare-asr/src/textGeneration.ts");
const { env } = await import("cloudflare:workers");
const summarizeRoute = await import("../app/api/summarize/route.ts");
const enhanceRoute = await import("../app/api/enhance/route.ts");

const GEMMA = "@cf/google/gemma-4-26b-a4b-it";

function gemmaReply(content, usage = { prompt_tokens: 400, completion_tokens: 120 }) {
  return { choices: [{ message: { role: "assistant", content }, finish_reason: "stop" }], usage };
}

async function post(path, body, fake) {
  const request = new Request(`https://asr.internal${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${TEST_ASR_KEY}`, "content-type": "application/json", "x-voiceink-client-key": "k" },
    body: JSON.stringify(body),
  });
  const response = await worker.fetch(request, fake.env, fake.executionContext);
  await fake.settled();
  return { response, body: await response.json() };
}

test("summaries run Gemma with reasoning off, a bounded output, and usage-based settlement", async () => {
  const fake = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("Overview: budget due Friday the 26th.") } });
  const { response, body } = await post("/v1/summaries", { text: "Sam sends the budget by Friday the 26th." }, fake);
  assert.equal(response.status, 200);
  assert.deepEqual(body, { summary: "Overview: budget due Friday the 26th.", model: "gemma-4-26b-a4b-it" });
  const [{ model, input }] = fake.calls;
  assert.equal(model, GEMMA);
  assert.deepEqual(input.chat_template_kwargs, { enable_thinking: false });
  assert.equal(input.max_completion_tokens, 500);
  assert.equal(input.max_tokens, undefined);
  const reserve = fake.ledger.find((entry) => entry.op === "reserve");
  const commit = fake.ledger.find((entry) => entry.op === "commit");
  assert.ok(reserve.request.estimateMicros >= commit.micros);
  assert.equal(commit.micros, Math.ceil(400 * 0.1 + 120 * 0.3));
});

test("enhancement uses the same model and caps output at 3,000 tokens", async () => {
  const fake = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("Move the launch to next week.") } });
  const { response, body } = await post("/v1/enhancements", { text: "um move the launch", mode: "clean" }, fake);
  assert.equal(response.status, 200);
  assert.deepEqual(body, { enhanced: "Move the launch to next week.", mode: "clean", model: "gemma-4-26b-a4b-it" });
  assert.equal(fake.calls[0].input.max_completion_tokens, 3_000);
});

test("a failed model call releases its reservation; an empty summary falls back to the transcript", async () => {
  const failing = fakeAsrEnv({ models: { [GEMMA]: () => { throw new Error("down"); } } });
  assert.equal((await post("/v1/summaries", { text: "Hello there." }, failing)).response.status, 502);
  assert.deepEqual(failing.ledger.map((entry) => entry.op), ["reserve", "release"]);
  const empty = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("") } });
  const { body } = await post("/v1/summaries", { text: "First point. Second point." }, empty);
  assert.equal(body.summary, "First point. Second point.");
});

test("the reply parser reads the chat shape and the older shapes", () => {
  assert.equal(generatedText(gemmaReply("  chat  ")), "chat");
  assert.equal(generatedText({ response: " legacy " }), "legacy");
  assert.equal(generatedText({ text: "t" }), "t");
  assert.equal(generatedText({ choices: [{ message: { content: 5 } }] }), "");
  assert.equal(generatedText(null), "");
});

function installWebBindings(asrReply) {
  env.SUMMARY_RATE_LIMITER = { limit: async () => ({ success: true }) };
  env.ENHANCEMENT_RATE_LIMITER = { limit: async () => ({ success: true }) };
  env.ASR = { fetch: async () => Response.json(asrReply) };
  Object.assign(process.env, { ASR_API_KEY: "k", HISTORY_ENCRYPTION_KEY: "p" });
}

function webRequest(path, body) {
  return new Request(`https://v.paul.im${path}`, {
    method: "POST",
    headers: { origin: "https://v.paul.im", "content-type": "application/json", "content-length": String(JSON.stringify(body).length) },
    body: JSON.stringify(body),
  });
}

test("the web routes accept only the current text model's replies", async () => {
  installWebBindings({ summary: "S", model: "gemma-4-26b-a4b-it" });
  assert.equal((await summarizeRoute.POST(webRequest("/api/summarize", { text: "hello" }))).status, 200);
  installWebBindings({ summary: "S", model: "llama-3.2-3b-instruct" });
  assert.equal((await summarizeRoute.POST(webRequest("/api/summarize", { text: "hello" }))).status, 502);
  installWebBindings({ enhanced: "E", mode: "clean", model: "gemma-4-26b-a4b-it" });
  assert.equal((await enhanceRoute.POST(webRequest("/api/enhance", { text: "hello", mode: "clean" }))).status, 200);
});

test("the reservation covers the serialized prompt's bytes, not its character count", async () => {
  const plain = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("ok") } });
  await post("/v1/summaries", { text: "a".repeat(1_000) }, plain);
  const escaped = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("ok") } });
  await post("/v1/summaries", { text: `x${"\u0001".repeat(999)}` }, escaped);
  const wide = fakeAsrEnv({ models: { [GEMMA]: () => gemmaReply("ok") } });
  await post("/v1/summaries", { text: "語".repeat(1_000) }, wide);
  const reserved = (fake) => fake.ledger.find((entry) => entry.op === "reserve").request.estimateMicros;
  assert.ok(reserved(escaped) > reserved(plain) + 400, "each escaped control character counts as six bytes");
  assert.ok(reserved(wide) > reserved(plain) + 150, "three-byte characters count as three bytes");
});
