import assert from "node:assert/strict";
import test from "node:test";

import {
  ANONYMOUS_AUDIO_SECONDS,
  audioFileExtension,
  elapsedRecordingSeconds,
  readAudioDuration,
  recordingLimitSeconds,
  selectRecorderMimeType,
  SIGNED_IN_RECORDING_SECONDS,
  SIGNED_IN_UPLOAD_SECONDS,
  uploadDurationError,
  uploadLimitSeconds,
  uploadSizeError,
} from "../lib/recording.ts";

test("signed-in users keep full duration limits while guests get the trial tier", () => {
  assert.equal(recordingLimitSeconds(true), SIGNED_IN_RECORDING_SECONDS);
  assert.equal(recordingLimitSeconds(false), ANONYMOUS_AUDIO_SECONDS);
  assert.equal(uploadLimitSeconds(true), SIGNED_IN_UPLOAD_SECONDS);
  assert.equal(uploadLimitSeconds(false), ANONYMOUS_AUDIO_SECONDS);
  assert.equal(SIGNED_IN_RECORDING_SECONDS, 30 * 60);
  assert.equal(SIGNED_IN_UPLOAD_SECONDS, 2 * 60 * 60);
  assert.equal(ANONYMOUS_AUDIO_SECONDS, 10 * 60);
});

test("upload validation reports tier-appropriate errors", () => {
  assert.equal(uploadSizeError(10, 100), null);
  assert.match(uploadSizeError(101, 100) ?? "", /24 MB/);
  assert.equal(uploadDurationError(SIGNED_IN_UPLOAD_SECONDS, true), null);
  assert.match(uploadDurationError(SIGNED_IN_UPLOAD_SECONDS + 1, true) ?? "", /two hours/);
  assert.equal(uploadDurationError(ANONYMOUS_AUDIO_SECONDS, false), null);
  assert.match(uploadDurationError(ANONYMOUS_AUDIO_SECONDS + 1, false) ?? "", /Sign in/);
  assert.match(uploadDurationError(null, false) ?? "", /could not read/);
});

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
