# Implementation-completeness audit and fixes — 2026-09-22/23

Repository `~/Developer/voiceink-sync`, branch `perf/mac-architecture-overhaul`, committed head
`5d03c7e3`, baseline `87a44f47`. Merge target `custom-main-v2` was still `87a44f47` (local and
remote) at the time of the audit, an ancestor of HEAD. All work below is uncommitted. Nothing was
staged, committed, pushed or merged.

Earlier review documents are historical records. This document supersedes their merge verdicts.

## Audit findings (2026-09-22)

The audit verified every earlier remediation claim against source. It found no introduced
high-severity correctness regression in the audio gate, Whisper generation lifetime, or paste and
auto-send paths. It did find the following.

Introduced by the uncommitted remediation:

1. **TTS tests overwrote a real user preference.** The lifecycle factory injects a nil notification
   center, so `TTSSettingsViewModel.loadSavedSettings` set `notificationsEnabled = false` and saved it
   to `UserDefaults.standard` on every run.
2. **Failed connect no longer ended the app-facing stream** for providers whose stream ends with the
   client's (Cartesia policy). No production consumer was affected. The test masked it by calling
   `disconnect()` before asserting.
3. **A clipboard change during snapshot capture skipped the paste** with no retry.

Pre-existing, found or confirmed during the audit:

4. **WAV payload offset.** `AudioSampleReader` skipped a fixed 44 bytes. Core Audio's WAV writer
   places the `data` payload at byte 4096 after an `FLLR` padding chunk, so about 2,000 samples of
   header and padding reached Whisper, SenseVoice and FastConformer at the start of every recording.
5. **Streaming timeout returned truncated text.** Seven vendors without an explicit finalization
   stream returned only the committed segments after the 10-second deadline, with no batch fallback.
6. **Streaming vocabulary fetch ran off the main actor** on the main `ModelContext`.
7. **FluidAudio prewarm loaded a private duplicate runtime** that transcription never used.
8. **Whisper model switch discarded the prewarmed context.** `WhisperModelManager.loadModel`
   unloaded every context, including the one prewarm had just built for the same model.
9. **Sparkle started inside the unit-test host.** The one unclosed in-process lead for the
   historical exit-code-0 host exits.

Documentation and test-claim gaps:

10. `CHANGELOG.md` had no entry for the twelve committed overhaul commits, including the OSLog
    subsystem change.
11. `PERF_OVERHAUL_TRIPLECHECK_2026-09-20.md` says three tests exercise "the actual device-switch
    transaction". They exercise the `RecordingDeviceSwitch.perform` helper, not the recorder's
    hardware recovery closure.
12. The changelog's Cartesia cancellation line overstated a defect that had no user-visible path.
13. `AsyncExpectationTests` passed with or without the blocking helper it was described as guarding.
14. `AGENTS.md` claimed every production file was below 500 lines; 22 exceed it.
15. The failing 2026-09-20 result bundles (host exits) were pruned; only passing runs were preserved.

## Fixes applied (2026-09-23)

| Finding | Change |
|---|---|
| 1 | `TTSDefaultsSnapshot` captures, clears and restores every persisted TTS key around each test (`TTSViewModelTests+Factory.swift`). Tests start from default settings, so the ElevenLabs voice fetch is not reached on load. |
| 2 | `LLMKitStreamingProvider.connect` finishes the app-facing stream on failure when `finishesEventsWhenClientStreamEnds`. The test now asserts the end before `disconnect()`, with a bounded wait. |
| 3 | `CursorPaster.captureStableSnapshot` retries once; a clipboard that keeps changing is still left alone. |
| 4 | `AudioSampleReader` walks RIFF chunks to `data`, honours the declared data size, sizes its buffer from the bytes on disk rather than the header, rejects non-16-bit PCM and a `data` chunk without a preceding `fmt `, and keeps the raw-header fallback for non-RIFF input. |
| 5 | `StreamingStopResult.timedOut(partialText:)`. `StreamingTranscriptionSession` transcribes the full recording in batch and returns the committed text only if that fails. Streaming-only providers (Cartesia) skip the batch attempt. Cancellation: `StreamingTranscriptionService.throwIfCancelled()` runs after the chunk drain, in the commit failure path and after both final waits; the session rethrows `CancellationError`, refuses the fallback after its own `cancel()`, and `isCancellation` unwraps `URLError.cancelled` and `CloudTranscriptionError.networkError`. `TranscriptionPipeline` records a thrown error as cancelled when the user cancelled. |
| 6 | `DictionaryVocabulary.terms` runs on the main actor. Streaming providers fetch it at the start of `connect` unless `sendsCustomVocabulary` is false (Cartesia, Mistral, xAI); the batch `CloudTranscriptionService` uses it too, replacing a silent `try?` fetch off the main actor. |
| 7 | `ModelPrewarmService` uses the engine's registry and does not start unless the engine is idle. `FluidAudioTranscriptionService` is an actor: same-model preparations share one task (captured weakly); a different model waits for it; managers are detached synchronously before release and only after active inferences finish; `transcribe` verifies the loaded managers match its model before claiming them (three attempts, then an error); `cleanup()` waits for an in-flight load. |
| 8 | `WhisperContextManager.unloadAllContexts(except:)`; `WhisperModelManager.loadModel` keeps the target model's generation. |
| 9 | `UpdaterViewModel` does not start Sparkle when `AppRuntimeEnvironment.isRunningTests`. |
| 10, 12 | Changelog sections for the committed overhaul (2026-09-13) and this pass (2026-09-23); Cartesia and test-count wording corrected. |
| 13 | Test removed. |
| 14 | `AGENTS.md` inventory replaced with measured figures; invariants added for WAV payload location and the shared prewarm runtime. |

Smaller changes: converter rejections have their own dropped-buffer counter; idle placeholder
bars are hidden from accessibility; the moved `baseAddress!` in `CoreAudioRecorder+DeviceInfo.swift`
is a guard; `CoreAudioRecorder+Setup.swift` moved from the module root to `Infrastructure/Audio/`;
streaming state and stop-result types moved to `StreamingTranscriptionTypes.swift` and the chunk
source and metrics (now internal) to `StreamingTranscriptionSupport.swift`, leaving
`StreamingTranscriptionService.swift` at about 425 lines; the service gained a test seam
(`finalizationTimeout:`, `providerFactory:`) that production does not use; `try? Task.sleep`
race arms have comments.

## Independent review of the fix pass

A read-only sub-agent reviewed the fixes twice. The first round found no blocker but two medium
defects that this pass had introduced: a user cancel during the final wait was reported as a
timeout and uploaded the recording in batch, and a cancellation from the fallback fell through to
a second fallback. It also found that Cartesia's fallback could never succeed, that the shared
FluidAudio actor did not protect inference from a concurrent model switch or cleanup, an
unbounded buffer reservation from the WAV header, and several overclaims. All were fixed.

The second round confirmed those fixes and found two narrower remaining gaps: a cancel that makes
the provider's commit throw still reached the fallback, and FluidAudio released managers across a
suspension and did not check that the loaded model matched the request. Both were then fixed and
covered or reasoned as described in rows 5 and 7. The second round was not repeated after those
last two changes; they are covered by the final test run below and by the commit-after-cancel test.

## Not changed, and why

- **Device-switch recovery closure** (`CoreAudioRecorder.switchDevice`): testing it needs a live
  AUHAL unit and at least two input devices. The build host has none. Remains a hardware check.
- **Cartesia first-commit wait**: the service treats the first committed event after `commit()` as
  final. A redesign needs vendor protocol verification. Pre-existing.
- **Unbounded awaits before the final-commit timer** (`drainRemainingChunks`, `provider.commit()`).
  A structured-concurrency timeout cannot bound a non-cancellable socket call. Pre-existing.
- **Connect/disconnect race inside LLMkit clients**: lives in the pinned dependency.
- **`VoiceInkSchemaV1` references live model types**: freezing historical models is a schema
  project, not an audit fix. Pre-existing.
- **Clipboard snapshot on a detached task**: Apple's AppKit thread-safety summary does not list
  `NSPasteboard`. Off-main use is unverified rather than documented safe; left as is to avoid
  blocking the UI on promised data.
- **Historical host exits**: cause still not established. Sparkle gating removes one lead only.
- **Pipeline cancel routing** (`TranscriptionPipeline` catch) and the FluidAudio inference counting
  have no dedicated tests; the pipeline needs an engine harness and FluidAudio needs real models.
- **Prewarm idle gate**: the engine reports idle while a cancelled pipeline is still finishing, so a
  prewarm can start in that window. With inference counting this is safe, only wasteful.
- **Zero-size `data` chunk** is treated as unfinalized and read to end of file. Pre-existing.
- **`TTSDefaultsSnapshot` restores values but cannot undo earlier runs.** The developer's TTS
  notification preference was already off before this pass and may have been turned off by earlier
  test runs. It was left as found.

## Verification

All runs used the prescribed Debug arm64 `xcodebuild test` command with `-only-testing:VoiceInkTests`.

| Run | Result |
|---|---|
| Audit baseline, clean build (2026-09-22) | 556 project sources compiled, 0 project warnings; 266 executed, 2 skipped, 0 failures |
| Audit baseline, five relaunched repetitions | 266 / 2 / 0 each; no host restart |
| Final tree, clean build (2026-09-23) | 561 project sources compiled, 0 project warnings; 289 executed, 2 skipped, 0 failures |
| Final tree, three relaunched repetitions | 289 / 2 / 0 each; no host restart |

The only warnings are four MLX C++17-extension warnings in a dependency and two AppIntents
metadata-extraction notices. The two skips are `AudioDeviceManagerTests` cases that need an input
device. `git diff --check` and `Localizable.xcstrings` JSON validation pass. Static `func test`
declarations: 318, up from 236 at `5d03c7e3`.

Mutation checks: each fix below was temporarily reverted, the named tests failed, and the files
were restored byte-for-byte (checked with `shasum`/`cmp`).

| Reverted behaviour | Tests that failed |
|---|---|
| Fixed 44-byte WAV offset | three `AudioSampleReaderTests` (Core Audio WAV, AVAudioFile WAV, trailing chunk) |
| No stream end on failed connect | `testFailedConnectMapsErrorAndDisconnectsWhenRequested` |
| Unload every Whisper context on switch | `testSwitchingKeepsTheTargetModelsLiveContextAndRetiresOthers` |
| Cancel treated as timeout; cancel-broken commit reaching fallback | three `StreamingTimeoutFallbackTests` cancel cases |

A TTS test run with the developer's TTS notification preference set on left it on; the value was
then restored to what it was before the check (off).

The suite takes about 45 s instead of 30 s after `reset_permissions.sh`, because
`ScreenCaptureServiceTests` run slower once screen-recording permission is reset. Those tests were
not changed.

`bash ./reset_permissions.sh` ran after each successful Debug build, as `AGENTS.md` requires. It
reset TCC approvals and the onboarding flag for `com.tmm22.VoiceLinkCommunity`.

Preserved evidence: `.local-build/merge-verification/audit-2026-09-23/` (final clean and
three-run bundles plus every log from this audit, including the failing compile and mutation logs).

## Verdicts

- **Implementation complete:** yes for everything that can be verified without hardware. The
  device-switch recovery closure and the items under "Not changed" remain open.
- **Safe to merge the complete working tree:** yes, as an engineering judgement from review and
  repeated passing runs. Include every tracked modification and every untracked file listed by
  `git status`, including the moved `CoreAudioRecorder+Setup.swift` (old path deleted, new path
  untracked). Do not merge `5d03c7e3` alone.
- **Ready to release:** no. Live microphone capture and device switching, sleep and wake,
  cross-application paste with clipboard managers, VoiceOver and Reduce Motion, native Whisper and
  XPC inference, real Keychain upgrades, CloudKit maintenance, streaming vendor finalization under
  slow networks, and performance measurements are still unverified.
