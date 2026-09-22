# Independent double-check of the performance overhaul working tree — 2026-09-20

> Historical review. The later [remediation and triple-check](PERF_OVERHAUL_TRIPLECHECK_2026-09-20.md)
> supersedes the paste-safety claim, test counts and merge assessment below. Historical result
> bundles may have been pruned by Xcode; their absence is not a new test failure.

Repository: `~/Developer/voiceink-sync`; branch `perf/mac-architecture-overhaul`; committed head
`5d03c7e3`; pre-overhaul baseline `87a44f47`. All changes remain uncommitted. Nothing was published.

This report follows [the double-check prompt](PERF_OVERHAUL_DOUBLECHECK_PROMPT_2026-09-19.md). The
first half records the review of the tree as received; the second half records the fixes applied
afterwards at the user's request and the clean-build verification of the result.

## Review of the tree as received

### Verification

- Prescribed Debug arm64 command: **247 XCTest cases executed, 2 skipped, 0 failures**; the bundle
  `Test-VoiceInk-2026.09.20_07-19-51-+1000.xcresult` counts 248 including Swift Testing's example.
- That run was incremental and recompiled only two files (an MLX macro file and the XPC engine). It
  compiled no VoiceInk target source, so its clean warning output said nothing about the changed
  code. Every earlier recorded run was incremental as well.
- The follow-up report's cited full-run bundle (`19-31-43`) had been pruned by Xcode. The focused
  audio bundle (`19-33-39`, 4 passed) still existed and matched its claim.
- `git diff --check` clean. LLMkit checkout `1fc213b8` matches `Package.resolved`.

### Claims verified against source

- **Clipboard.** The change count is captured after `ClipboardManager.setClipboard` returns and is
  passed through the `defer` in `CursorPaster.performPasteSession`, so cancelled and skipped
  sessions still schedule restoration. `ClipboardSnapshot.restoreIfOwned` requires the original
  revision, text and session marker, and rechecks the revision before `clearContents()`. The window
  between that recheck and `clearContents()` cannot be closed with `NSPasteboard`.
- **Prompts.** No `promptDidChange`, `updatePrompt` or `handlePromptChange` callers remain. Saved
  language prompts flow from `TranscriptionRuntimeConfiguration.requestContext` through
  `FileTranscriptionSession.prepare` into `WhisperContextManager.performInference` and one
  synchronous `WhisperContext` turn. A nil prompt reaches whisper.cpp as an empty string, which it
  tokenizes to zero prompt tokens and ignores (`whisper.cpp` `1fe009ca`, lines 6950–6961), so it
  clears the previous prompt. The earlier correction stands: this removed a redundant setter.
- **Accessibility.** Every explicit animation site under `Features/Recording` honours Reduce
  Motion; the controls moved to `RecorderControls.swift` differ from the removed code only by the
  intended edits; the recorder panels call `setFrame` without AppKit animation. Not checked live.
- **Audio.** Stop, switch and teardown close the gate, stop the hardware, and drain without bound
  before any resource mutation. The gate opens only in `startAudioUnit`, always from a closed and
  drained state. Every `CoreAudioRecorder` lifecycle call from `Recorder` runs on `audioSetupQueue`,
  including deinit and the no-device teardown. A sorted-line comparison of the old recorder with
  the split files shows the gate substitution, the throwing buffer allocation and `try
  startAudioUnit()` in `switchDevice` as the only logic changes.
- **Streaming and prewarm.** All nine LLMkit clients assign `transcriptionEvents` in `init` only.
  Providers are created per session; the final-commit wait has a 10 s timeout; deinit disconnects
  the client without retaining the provider. Prewarm tasks are stored, cancelled on sleep and
  deinit, and coalesced.
- **Tests.** All new tests call production types; fakes replace only loaders, clients and the
  transcription service. Tests that expose an original defect: the shared-waiter Whisper test, the
  marker-preserving clipboard rewrite test, both drain tests, the converter-failure test, the
  disconnect-after-commit test, the idle-forwarding retention test, the no-spin and floor-modifier
  wait tests, and the failed/skipped auto-send tests. The rest are preservation tests. The WAV stop
  test fails the old path because the old `stopRecording` skipped waiting entirely when no audio
  unit existed and gave up after 200 ms otherwise; it does not reproduce a HAL stall.

### Findings

Introduced:

1. **Medium.** `CursorPaster.performPasteSession` skipped the paste whenever the change count moved
   during the wait. Utilities that rewrite the pasteboard on every change (plain-text sanitizers,
   normalising clipboard managers) would trip this on every dictation. Before this tree the paste
   still went through.
2. **Low.** `LastTranscriptionService` used `pasteAtCursor`, which discarded the result, so a skipped
   re-paste from History gave no feedback.
3. **Low.** The new labels `Text("Recording mode")` and `Text("Recording")` had no catalogue entries.
4. **Low.** A cancelled wait logged "posting paste while a modifier key is still held" although
   nothing was posted.

Pre-existing (present at `5d03c7e3` or `87a44f47`):

- `VoiceInkEngine.swift` is 817 lines.
- `ClipboardSnapshot.init` reads every representation synchronously on the main actor, as the old
  snapshot code did.
- A `switchDevice` failure after uninitialise leaves the unit uninitialised with `isRecording` true
  until the next stop.
- The unbounded drain keeps `Recorder.stopRecording` suspended on a permanently stalled callback.
- `AudioSampleReader.swift:46` produced an unused-result warning and used a force unwrap
  (introduced by `df1c84a1` on this branch, committed before `5d03c7e3`).

Gaps: no production code cancels the paste task, so the cancellation guards are defensive rather
than live paths; `performPasteSession` itself is untested; the clipboard tests write sessions with
`writeObjects` rather than the production writer; no test holds a callback across a device switch;
the real `CartesiaStreamingProvider` is untested; the prompt session test does not reach native
inference.

## Fixes applied

- The paste skip now requires both a moved revision **and** a pasteboard string that differs from
  the transcript (`CursorPaster.shouldSkipPaste`). Rewrites that keep the transcript paste normally;
  foreign content still skips. The text is read only when the revision moved.
- `CursorPaster.notifyIfSkipped` (`CursorPaster+Feedback.swift`) is the single skip notification.
  `TranscriptionDelivery` and `pasteAtCursor` (History re-paste) both use it.
- The cancelled-wait log line is suppressed when the task was cancelled.
- Added `de` and `zh-Hans` entries for "Recording" and "Recording mode".
- `AudioSampleReader` now uses the decoded sample count, trims any shortfall, and no longer force
  unwraps the buffer base address.
- Added `PasteSkipDecisionTests` (4 cases) covering unchanged revision without a text read,
  rewritten revision holding the transcript, foreign content, and an emptied clipboard.
- Updated `CHANGELOG.md` and this document; the verification brief points here.

## Verification of the fixed tree

- **Clean build** (build products removed, all 545 VoiceInk and test sources recompiled):
  `Test-VoiceInk-2026.09.20_07-40-24-+1000.xcresult`, 252 cases, 249 passed, 2 skipped, 1 failed.
  The failure was not an assertion: the test host exited silently during
  `TTSViewModelTests.testRapidAllocDealloc` and Xcode relaunched it to finish the remaining 35 tests.
  No crash report was written. The 2026-09-16 review recorded the same interruption in the same
  suite at `5d03c7e3`, and the branch touches the TTS view model only lightly, so this is a
  pre-existing intermittent test-host exit, not attributed to the working tree. The only compiler
  warning in that clean build was the `AudioSampleReader` one fixed above.
- **Final run after the fixes** (`Test-VoiceInk-2026.09.20_07-47-22-+1000.xcresult`): the string
  catalogue change regenerated symbols, so 538 VoiceInk and test sources recompiled with **0
  compiler warnings**. **251 XCTest cases executed, 2 skipped, 0 failures**; 252 in the bundle
  including Swift Testing's example. No test-host restart occurred in this run. The two skips are
  the `AudioDeviceManagerTests` cases that need an input device.
- `git diff --check` clean. `bash ./reset_permissions.sh` was run after the successful Debug build,
  per `AGENTS.md`.
- There are now 44 added tests relative to `5d03c7e3` (219 → 263 static `func test` declarations;
  207 → 251 executed).

Merge assessment: ready. Release assessment: not yet verified; see below.

## Remaining release checks

Unchanged from the earlier reports: live microphone capture, device switch, sleep and wake,
stalled-driver behaviour, clipboard managers and sanitisers, cross-application paste delivery,
VoiceOver and Reduce Motion, Keychain upgrades, CloudKit maintenance and native inference. The
silent test-host exit in `TTSViewModelTests` deserves its own investigation.
