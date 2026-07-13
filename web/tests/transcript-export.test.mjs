import assert from "node:assert/strict";
import test from "node:test";
import { buildSrt, buildVtt } from "../lib/transcriptExport.ts";

test("SRT export assigns stable sequential cues across the supplied duration", () => {
  assert.equal(buildSrt("First sentence. Second sentence!", 10_000), [
    "1",
    "00:00:00,000 --> 00:00:05,000",
    "First sentence.",
    "",
    "2",
    "00:00:05,000 --> 00:00:10,000",
    "Second sentence!",
  ].join("\n"));
});

test("WebVTT export uses dot timestamps and handles empty text", () => {
  assert.match(buildVtt("A single cue.", 1_234), /^WEBVTT\n\n00:00:00\.000 --> 00:00:01\.234/);
  assert.equal(buildVtt(""), "WEBVTT");
});

test("subtitle generation never emits negative timestamps", () => {
  assert.doesNotMatch(buildSrt("Safe timing.", -100), /-\d{2}:\d{2}:\d{2}/);
});
