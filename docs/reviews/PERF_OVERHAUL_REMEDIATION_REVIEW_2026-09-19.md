# Independent review of the performance overhaul remediation — 2026-09-19

Reviewed the uncommitted working tree of `perf/mac-architecture-overhaul` (committed head
`5d03c7e3`, overhaul baseline `87a44f47`) in `~/Developer/voiceink-sync`, against the claims in
[the remediation report](PERF_OVERHAUL_REMEDIATION_2026-09-19.md) and the findings in
[the original review](PERF_OVERHAUL_REVIEW_2026-09-16.md). The second half of this document
records the small adjustments made after the review; the first half describes the state before them.

## Verification

The brief's exact `xcodebuild test` command was run before inspecting the code.

- Working tree as received: **240 XCTest cases executed, 2 skipped, 0 failures**; the result
  bundle counts 241 including Swift Testing's `example()`
  (`Test-VoiceInk-2026.09.19_17-12-10-+1000.xcresult`). The two skips are the
  `AudioDeviceManagerTests` cases that need an input device; the build host has none.
- After the adjustments below: **241 XCTest cases executed, 2 skipped, 0 failures**; 242 in the
  bundle (`Test-VoiceInk-2026.09.19_17-45-03-+1000.xcresult`). No compiler warnings in `VoiceInk/`
  sources; the build was incremental, so that check covers recompiled files only.
- `git diff --check` clean. All six new or extended suites executed.
- No live microphone, device switch, sleep/wake, cross-application paste, VoiceOver, real Keychain,
  or native model inference was exercised.

## Claims verified

1. **Audio callback lifetime.** Every mutation of render-thread resources is preceded by
   `AudioCallbackGate.close()`, a hardware stop where a unit exists, and an unbounded drain:
   `CoreAudioRecorder.stopRecording`, `switchDevice`, and `teardownPreparedAudioUnit`. All
   `CoreAudioRecorder` lifecycle calls from `Recorder` run on `audioSetupQueue`, including deinit
   and the no-device teardown. Stop returns only after drain, converter flush and file close.
   `testStopWaitsForFinalPCMThenClosesReadableWAV` holds a callback past the old 200 ms deadline
   and would fail against the pre-fix stop path, which closed the file on timeout.
2. **Whisper generations.** `testConcurrentWaitersSharePublishedContextWithoutReleasingIt`
   reproduces the original P1 against the real manager. Publication and invalidation are separate,
   release happens once after the last active inference, and a failed or invalidated old load never
   removes a replacement. Callers only use `loadContext` to warm the cache.
3. **Streaming.** The forwarding task holds only the client stream across the await. All nine
   LLMkit clients assign `transcriptionEvents` in `init` only, so capturing it before `connect` is
   safe. Providers are created per session; the session's final-commit wait has a timeout, so the
   removed Cartesia acknowledgement on cancel cannot hang a stop.
4. **Paste.** The wait policy exits on cancellation without spinning and rechecks modifiers after
   the floor sleep. A failed or cancelled paste never posts Enter.
5. **Accessibility and prewarm.** The controls moved into `RecorderControls.swift` are identical to
   the removed code apart from the intended accessibility edits. Prewarm tasks are stored,
   cancelled on sleep and deinit, and never overlap.

## Findings

### Introduced behaviour change — medium

`CursorPaster.performPasteSession` skipped the paste when the pasteboard change count moved during
the wait window, returning `.commandNotPosted`, which `TranscriptionDelivery.paste` discarded.
Trigger: a clipboard utility that rewrites the pasteboard on change, or a user copy within roughly
150 ms. Impact: nothing pasted and no feedback. Safer than pasting foreign content, but silent.
**Addressed below.**

### Design limitation — medium, documented

The drain wait is unbounded by design. A permanently stalled HAL callback leaves the stop
continuation in `Recorder.stopRecording` suspended, so the engine never leaves its stopping state,
and there is no watchdog. This is the correct trade against use-after-free and remains a live
release check on USB and Bluetooth devices.

### Pre-existing — low

- `CoreAudioRecorder.deinit` still calls `teardown()`. The meter task captured the core strongly,
  so a main-actor release could in principle be the last one. Harmless because resources are
  already torn down by then, but the deinit comment overstated the guarantee. **Addressed below.**
- `WhisperContextManager.updatePrompt` is overwritten on every inference because
  `ManagedWhisperContext.transcribe` sets `prompt ?? ""`, so `VoiceInkEngine.handlePromptChange`
  is effectively a no-op. Unchanged from the base commit; left as is.
- A Whisper load cancelled by an unload was logged at error level. **Addressed below.**

### Process

- `CHANGELOG.md` was not updated despite user-visible changes. **Addressed below.**
- The remediation report cited a result bundle timestamped 11:22:19 that is not present under
  `.local-build/Logs/Test/`. **Corrected below.**
- Two test hooks live in production code: `WhisperContextManager.pendingLoadWaiterCount` and the
  `isRunningTests` guard in `ModelPrewarmService.init`. Acceptable, noted for awareness.

### Coverage gaps

- No test holds a callback across a device switch's buffer reallocation, the original P1 scenario.
  The gate mechanism is identical to the tested stop path, so this is low risk.
- The pasteboard-changed refusal inside `performPasteSession` is not unit tested; it depends on
  `NSPasteboard.general` and CGEvent posting.
- The real `CartesiaStreamingProvider` is untested; the test double mirrors its hooks.

## Adjustments made after the review

- `CursorPaster.PasteResult` gained `skippedClipboardChanged`, returned only when the change count
  moved; cancellation still returns `.commandNotPosted`. `TranscriptionDelivery.paste` shows one
  warning notification for the skipped case, then defers to `autoSendAfterPaste`, which never
  sends for any non-posted result. New test:
  `PasteAutoSendTests.testSkippedPasteAfterClipboardChangeDoesNotSubmitExistingText`.
- `Recorder.startMeterUpdates` captures the core weakly, so the setup-queue teardown closure is the
  final owner and `CoreAudioRecorder.deinit` runs on that queue; the deinit comment now says so.
- `WhisperContextManager.loadGeneration` logs a cancelled load at notice level and still rethrows.
- Added the `2026-09-19` section to `CHANGELOG.md`.
- Corrected the result-bundle reference in the remediation report and linked this document.
- Wrote [the verification brief](PERF_OVERHAUL_VERIFICATION_BRIEF_2026-09-19.md) for a fresh agent.

## Conclusion

Ready to merge. Both P1 findings are fixed and covered by tests that exercise production code and
would expose the original defects. Not ready to release: live microphone capture, device switching,
sleep and wake, stalled-driver behaviour, real cross-application paste with clipboard managers,
VoiceOver, Keychain upgrades and native model inference remain unverified, exactly as the
remediation report states.
