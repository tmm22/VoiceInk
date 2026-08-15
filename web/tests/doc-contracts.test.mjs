import assert from "node:assert/strict";
import test from "node:test";
import { checkDocumentationContracts, forbiddenDocumentationDrift } from "../scripts/check-doc-contracts.mjs";

test("documentation matches production architecture and canonical policy", async () => {
  await checkDocumentationContracts();
});

test("documentation drift guard rejects public ASR and external fallbacks", () => {
  assert.equal(forbiddenDocumentationDrift("Private ASR service binding only.").length, 0);
  assert.equal(forbiddenDocumentationDrift("Use PARAKEET_API_URL for a fallback.").length, 1);
  assert.equal(forbiddenDocumentationDrift("https://voiceink-asr.example.workers.dev").length, 1);
});
