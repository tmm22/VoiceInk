import assert from "node:assert/strict";
import test from "node:test";

import {
  audioFileExtension,
  elapsedRecordingSeconds,
  readAudioDuration,
  selectRecorderMimeType,
} from "../lib/recording.ts";

test("selects the first supported speech-efficient recording container", () => {
  assert.equal(selectRecorderMimeType((value) => value === "audio/ogg;codecs=opus"), "audio/ogg;codecs=opus");
  assert.equal(selectRecorderMimeType(() => false), undefined);
});

test("audio metadata validation times out and releases browser resources", async () => {
  const originalAudio = globalThis.Audio;
  const originalCreate = URL.createObjectURL;
  const originalRevoke = URL.revokeObjectURL;
  let revoked = false;
  class NeverLoadingAudio {
    duration = Number.NaN;
    onerror = null;
    onloadedmetadata = null;
    preload = "";
    src = "";
    load() {}
    removeAttribute() {}
  }
  globalThis.Audio = NeverLoadingAudio;
  URL.createObjectURL = () => "blob:test";
  URL.revokeObjectURL = () => { revoked = true; };
  try {
    assert.equal(await readAudioDuration({}, 5), null);
    assert.equal(revoked, true);
  } finally {
    globalThis.Audio = originalAudio;
    URL.createObjectURL = originalCreate;
    URL.revokeObjectURL = originalRevoke;
  }
});

test("derives filenames from the actual recorder MIME type", () => {
  assert.equal(audioFileExtension("audio/webm;codecs=opus"), "webm");
  assert.equal(audioFileExtension("audio/ogg;codecs=opus"), "ogg");
  assert.equal(audioFileExtension("audio/mp4"), "m4a");
});

test("measures elapsed time monotonically instead of trusting timer ticks", () => {
  assert.equal(elapsedRecordingSeconds(1_000, 1_000), 0);
  assert.equal(elapsedRecordingSeconds(1_000, 3_510), 3);
  assert.equal(elapsedRecordingSeconds(3_000, 2_000), 0);
});
