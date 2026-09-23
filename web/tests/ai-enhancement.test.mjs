import assert from "node:assert/strict";
import test from "node:test";
import { enhancementInstructions, isEnhancementMode } from "../cloudflare-asr/src/enhancement.ts";

test("AI enhancement exposes only the supported product presets", () => {
  for (const mode of ["clean", "concise", "professional", "notes"]) {
    assert.equal(isEnhancementMode(mode), true);
    assert.ok(enhancementInstructions[mode].length > 30);
  }
  assert.equal(isEnhancementMode("translate"), false);
  assert.equal(isEnhancementMode(undefined), false);
});

test("enhancement presets preserve meaning and avoid unsupported invention", () => {
  const combined = Object.values(enhancementInstructions).join(" ");
  assert.match(combined, /preserv/i);
  assert.match(combined, /invent/i);
  assert.match(enhancementInstructions.notes, /action item/i);
});

test("the rewrite result and the footer name the text model that produced it", async () => {
  const { readFile } = await import("node:fs/promises");
  const panel = await readFile(new URL("../app/ai-enhancement.tsx", import.meta.url), "utf8");
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  // The label comes from the model the server reported for this result.
  assert.match(panel, /setResultModel\(result\.model === TEXT_GENERATION_MODEL_NAME \? TEXT_GENERATION_MODEL_LABEL : result\.model \?\? ""\)/);
  assert.match(panel, /Rewritten transcript\{enhancedText && resultModel \?/);
  assert.match(page, /Whisper large-v3 turbo · \{TEXT_GENERATION_MODEL_LABEL\}/);
});
