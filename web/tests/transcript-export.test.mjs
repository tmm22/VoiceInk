import assert from "node:assert/strict";
import test from "node:test";
import { buildSrt, buildVtt } from "../lib/transcriptExport.ts";

test("SRT export preserves provider segment timing", () => {
  assert.equal(buildSrt([
    { start: 0.25, end: 4.75, text: "First sentence." },
    { start: 5.5, end: 9.875, text: "Second sentence!" },
  ]), [
    "1",
    "00:00:00,250 --> 00:00:04,750",
    "First sentence.",
    "",
    "2",
    "00:00:05,500 --> 00:00:09,875",
    "Second sentence!",
  ].join("\n"));
});

test("WebVTT export uses provider timings and handles no segments", () => {
  assert.match(buildVtt([{ start: 0, end: 1.234, text: "A single cue." }]), /^WEBVTT\n\n00:00:00\.000 --> 00:00:01\.234/);
  assert.equal(buildVtt([]), "WEBVTT");
});

test("subtitle generation never emits negative timestamps", () => {
  assert.doesNotMatch(buildSrt([{ start: -1, end: 1, text: "Safe timing." }]), /-\d{2}:\d{2}:\d{2}/);
});
