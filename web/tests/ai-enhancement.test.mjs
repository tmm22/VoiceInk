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
