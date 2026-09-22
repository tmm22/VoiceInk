# Performance overhaul remediation — independent verification brief (2026-09-19)

Purpose: hand the post-review state of `perf/mac-architecture-overhaul` to a fresh, independent
agent. Everything the verifier needs is in this file and the documents it links; no conversation
context is required.

Current state: [independent double-check and fixes, 2026-09-20](PERF_OVERHAUL_DOUBLECHECK_2026-09-20.md).
Earlier follow-up: [fixes and verification](PERF_OVERHAUL_FOLLOWUP_2026-09-19.md).
For a fresh review use [the 2026-09-20 double-check prompt](PERF_OVERHAUL_DOUBLECHECK_PROMPT_2026-09-20.md);
the [2026-09-19 prompt](PERF_OVERHAUL_DOUBLECHECK_PROMPT_2026-09-19.md) is the previous round's brief.
The earlier documents below describe historical stages.

## Where the code is

- Repository clone: `~/Developer/voiceink-sync` (do not use the iCloud Desktop copy; builds hang there)
- Branch: `perf/mac-architecture-overhaul`, committed head `5d03c7e3`
- Overhaul baseline for "was this behaviour already there": `87a44f47`
- All remediation and follow-up changes are **uncommitted**: review tracked modifications **and**
  untracked source, test and doc files (`git status --short` lists them)

## Read first

1. `AGENTS.md`
2. `docs/reviews/PERF_OVERHAUL_REVIEW_2026-09-16.md` — the original review (two P1 findings)
3. `docs/reviews/PERF_OVERHAUL_REMEDIATION_2026-09-19.md` — the remediation's own claims
4. `docs/reviews/PERF_OVERHAUL_REMEDIATION_REVIEW_2026-09-19.md` — the independent review of that
   remediation and the small follow-up adjustments it made

Treat every statement in documents 3 and 4 as a claim to verify, not as fact.

## Run first

```
cd ~/Developer/voiceink-sync
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceInkTests -parallel-testing-enabled NO \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: `xcodebuild` reports 247 XCTest cases executed, 2 skipped (no audio input device on the
host), 0 failures; the `.xcresult` bundle counts 248 because it includes Swift Testing's
`example()`. Expect no compiler warnings in `VoiceInk/` sources. If the build is incremental, note that the warning
check covers only recompiled files.

## Prompt for the verifying agent

"Read `docs/reviews/PERF_OVERHAUL_VERIFICATION_BRIEF_2026-09-19.md` in `~/Developer/voiceink-sync`
and the four documents it lists. Run the test command first. Then independently verify the
uncommitted working tree of `perf/mac-architecture-overhaul` against `5d03c7e3`, using `87a44f47`
to classify anything as pre-existing:

1. **Audio callback lifetime.** Confirm every mutation of render-thread resources (audio unit,
   render buffer, input slots, converter, file) is preceded by `AudioCallbackGate.close()`, a
   hardware stop where a unit exists, and an unbounded `waitUntilDrained`. Confirm every
   `CoreAudioRecorder` lifecycle call from `Recorder` runs on `audioSetupQueue`, including deinit
   and the no-device teardown. Confirm the meter task now captures the core weakly and cannot be
   its last owner. Confirm `AudioCallbackGate.open()` can never be reached while the gate is open
   or callbacks are active (its precondition traps). Decide whether the
   `testStopWaitsForFinalPCMThenClosesReadableWAV` test would fail against the pre-fix stop path.
2. **Whisper generations.** Confirm two concurrent waiters share one published context, a cancelled
   waiter does not cancel the shared load, invalidated results are released exactly once and only
   after the last active inference, and old completions never remove a replacement generation.
   Confirm the cancelled-load log path now logs at notice level and still rethrows.
3. **Streaming.** Confirm the forwarding task holds only the client stream across the await, all
   nine LLMkit clients assign `transcriptionEvents` in `init` only, providers are created per
   session, deinit disconnects the client without retaining the provider, and cancellation does not
   synthesize Cartesia's empty committed event. Confirm the session's final-commit wait has a
   timeout so a missing acknowledgement cannot hang a stop.
4. **Paste.** Confirm `PasteResult.skippedClipboardChanged` is returned only when the pasteboard
   change count moved during the wait, that cancellation still returns `.commandNotPosted`, that
   `TranscriptionDelivery` shows one warning notification for the skipped case and none otherwise,
   and that `autoSendAfterPaste` never sends for `.commandNotPosted`,
   `.skippedClipboardChanged`, a cancelled paste task, or a cancelled delay. Confirm the clipboard
   restore path cannot overwrite a user's newer clipboard contents.
5. **Accessibility and prewarm.** Confirm the recorder controls moved into `RecorderControls.swift`
   are unchanged apart from the intended accessibility edits, Reduce Motion pauses every
   animation, and prewarm tasks are stored, cancelled on sleep and deinit, and never overlap.
6. **Documentation.** Confirm `CHANGELOG.md` describes only behaviour that actually changed, and
   that the remediation doc's test-result references point at bundles that exist under
   `.local-build/Logs/Test/`.

Check whether each new test exercises production code rather than a copy, and whether it would
expose the original defect. Report actionable findings with severity, `file:line`, trigger, and
user impact. Separate introduced regressions, pre-existing defects, and unverified release checks.
Review only; do not modify files. Conclude separately whether the working tree is ready to merge
and whether it is ready to release."

## Known limits the verifier should not re-discover as news

- The build host has no audio input device; live microphone, device switch, sleep/wake and
  stalled-driver behaviour cannot be exercised by the unit suite.
- The unbounded drain wait is deliberate: a permanently stalled HAL callback keeps stop pending
  rather than freeing memory a callback may still touch.
- Cross-application paste delivery, VoiceOver, clipboard managers, real Keychain upgrades and real
  model inference remain manual release checks.
