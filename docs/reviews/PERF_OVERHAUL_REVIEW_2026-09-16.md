# Mac performance overhaul correctness review — 2026-09-16

Follow-up: [2026-09-19 remediation and verification](PERF_OVERHAUL_REMEDIATION_2026-09-19.md). The findings below describe the original reviewed state.

Reviewed `87a44f47..5d03c7e3` on `perf/mac-architecture-overhaul` in `~/Developer/voiceink-sync`, following the review brief's priority order. The difference from the brief's recorded implementation head (`a2929a4e`) is the review-brief commit. No production code was changed during this review.

## Verification

The exact `xcodebuild test` command in the brief was launched before inspecting implementation changes.

- Initial run: **205 passed, 2 skipped, 1 failed**, 208 total including the Swift Testing example. `TTSViewModelTests.testViewModelDoesNotLeak()` was interrupted by the test runner exiting with code 0. This was not a failed leak assertion. Xcode restarted the host to run remaining tests.
- Isolated rerun of that test: **passed**.
- Full `test-without-building` rerun with the same target, configuration, destination and signing options: **206 passed, 2 skipped, 0 failed**. The first-run interruption remains unexplained; no baseline reproduction was performed, so it is not attributed to this branch.
- Result bundles under `.local-build/Logs/Test/`: `Test-VoiceInk-2026.09.16_13-18-53-+1000.xcresult` (initial), `Test-VoiceInk-2026.09.16_13-21-16-+1000.xcresult` (isolated), `Test-VoiceInk-2026.09.16_13-21-55-+1000.xcresult` (full retry).
- Additional standalone probe compiled the actual `RecordingAudioFormatConverter.swift` and `PCMSampleConversion.swift`. One-second synthetic input at 8, 16, 22.05, 44.1, 48 and 96 kHz, with 32/128/512/4096-frame chunks, produced exactly 16,000 output frames after flush in every case. This verifies frame accounting, not live hardware behavior or speech accuracy.
- No live microphone capture, live cloud-provider calls, real-keychain migration, cross-application paste, CloudKit migration, or real-model XPC round trip was performed.

## Branch regression

### P1 — Do not continue resource teardown after the render-callback wait times out

**Location:** `VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift:585-590`.

The new 200 ms deadline returns normally even when `renderCallbacksInFlight` is still nonzero. Callers cannot distinguish this from successful quiescence. `switchDevice` then reconfigures/reallocates buffers; `teardownPreparedAudioUnit` disposes the audio unit and frees the render buffer and input slots (`VoiceInk/CoreAudioRecorder+Setup.swift:381-411`).

A callback delayed inside `AudioUnitRender`, or descheduled after taking the render-buffer pointer, can subsequently resume and access those resources. The callback checks `recordingActive` only before rendering (`CoreAudioRecorder.swift:400`); clearing it does not retire callbacks already past that check. Draining the processing queue also does not drain the render thread. The previous unbounded wait did not allow callers to advance while that counter remained nonzero.

**Impact:** use-after-free/data races, lost audio, or stale audio crossing recording/device generations under the slow/stalled callback condition this timeout is intended to handle. This is a source-level finding; a live HAL stall was not induced.

**Fix direction:** return an explicit quiescence result and prevent disposal, buffer reuse and restart on timeout. Preserve the old generation's resources until its final callback exits; perform any delayed retirement off the main actor. A timeout alone is not a lifetime barrier.

**Regression test:** hold an injected callback past the timeout while stopping/switching, assert its resources remain alive and unavailable for reuse, release it, then verify retirement and a clean next recording.

## Additional overlooked defect — present at the base commit

### P1 — Shared Whisper load waiters can release the successfully cached context

**Location:** `VoiceInk/Transcription/Whisper/Actors/WhisperContextManager.swift:43-52`.

Two requests arriving during the same model load share `load.task`. The first resumed waiter installs the context and clears `contextLoads[modelName]`. The second waiter then fails the identity guard because that dictionary entry is nil, treats the successfully completed load as invalid, calls `context.releaseResources()`, and throws `CancellationError`. The cache still contains that released context, so subsequent inference can fail as well.

This was reproduced by compiling the **actual manager source** with a fake asynchronous Whisper loader and issuing two concurrent `loadContext` requests. Output was:

```text
success
CancellationError
cached context release count: 1
```

The fake loader replaces inference/hardware only; the manager's load/lifetime logic was unchanged. Probe source and binaries are in `/tmp/voiceink-perf-probes/` for this session. The branch changes only the logger in this manager, so this is explicitly **not a new branch regression**. It matters to launch/wake prewarming racing the user's first transcription.

**Fix direction:** represent successful publication separately from invalidation and permit every waiter for the successful generation to receive its context. Only a truly invalidated generation should release its result, once. Cover two simultaneous loads, unload during load, replacement by a new generation, and inference overlapping unload.

## Coverage in the requested order

1. **Audio conversion:** converter replacement conditions include rate, channels and capacity; stop/switch flush before file close/replacement; the input block supplies each buffer once and distinguishes no-data from end-of-stream. New conversion work runs on the processing queue. Existing callback scheduling still uses `DispatchQueue.async`, so a strict “zero allocations anywhere in the render callback” claim needs measurement. The timeout regression above is the blocker.
2. **Credentials:** production/local service strings and Data Protection/login-keychain selection are preserved. TTS uses its existing bundle-derived service, omits synchronizable and applies `whenUnlocked`; production synchronization/accessibility behavior is preserved. An optional access group is now consistently applied to TTS reads/updates/deletes, whereas several old queries omitted it; no in-tree use needing the old omission was identified. Real upgrade verification is still missing.
3. **Nine streaming providers:** checked vendor model/language mapping, vocabulary limits, Deepgram/Gemini finalization streams, Gemini disconnect-on-connect-failure and Cartesia's empty committed event. No additional introduced behavior mismatch found. Timeout normalization and vocabulary-error logging match the stated changes.
4. **Paste:** policy tests verify timing decisions, not successful delivery to target applications. The reduced clipboard delay and removed event gaps still require application-level validation, particularly shortcut modifiers, alternate layouts, slow editors and clipboard restoration.
5. **XPC:** both protocol endpoints use matching String arguments/replies and both targets build. Native reply callbacks provide request association after removal of the JSON response ID. Cancellation/interruption with real inference remains untested.
6. **Launch/persistence:** the legacy multi-store reopen test passes. Detached maintenance creates its own context. The normal test bootstrap skips the new launch-maintenance path, so concurrent edits and background-save visibility need dedicated coverage.
7. **Live transcript:** all in-tree text writes still pass through the engine setter, which updates the leaf state and publishes empty/nonempty transitions. Mini/notch/assistant text views observe that leaf. No additional regression found; behavior/notification-count tests are missing.

## Recommended additions to this overhaul

These are follow-up improvements and verification gaps, not further claims of branch regressions.

- **Audio integrity beyond tone tests:** retain the multi-rate/chunk probe as a regression test; add very short utterances, stop immediately after startup, repeated flush/reset, device unplug/switch, sleep/wake, queue saturation and equality of streamed PCM versus saved PCM. Propagate converter initialization failure instead of merely logging and allowing an empty recording (`VoiceInk/CoreAudioRecorder+Setup.swift:250`). Exercise Bluetooth and USB devices manually.
- **Resource ownership and energy:** share the actual inference runtime with prewarming, especially FluidAudio, instead of retaining a private prewarm registry (`VoiceInk/App/Lifecycle/ModelPrewarmService.swift:12`). Store/cancel/coalesce wake-prewarm tasks (`:39`, `:48`), and benchmark retained memory after model switches and repeated wake events. This ownership pattern predates the branch.
- **Streaming lifetime tests:** the shared base still strengthens weak `self` for the entire stream loop (`VoiceInk/Infrastructure/Providers/Transcription/Cloud/Streaming/LLMKitStreamingProvider.swift:140`). An indefinitely open stream can retain its provider/task unless explicit disconnect runs; this pattern was inherited from the old wrappers. Inject a fake client to test event mapping, finalization, failed connect, disconnect, cancellation and provider deallocation without contacting vendors.
- **Accessibility and real paste delivery:** test held modifiers/Sticky Keys, VoiceOver, Dvorak-QWERTY command switching, Terminal/Electron/native editors, clipboard managers and concurrent user clipboard changes. Recheck modifier state after the minimum-delay sleep (`VoiceInk/Infrastructure/SystemIntegration/Paste/PrePasteWaitPolicy.swift:51`) if readiness is meant to describe the actual posting instant. A posted Cmd+V is not proof that the transcript arrived.
- **Idle rendering:** the visualizer still ticks at 30 Hz during silent active recordings (`VoiceInk/Features/Recording/Components/AudioVisualizerView.swift:38`). Pause animation for zero amplitude and Reduce Motion where appropriate; measure both mini and notch views to ensure leaf observation reduces real CPU usage.
- **Persistence upgrades:** exercise background duplicate cleanup against simultaneous edits/CloudKit arrivals and main-context visibility (`VoiceInk/App/VoiceInk.swift:204`). Before changing model properties, freeze historical model definitions: V1 currently references the live top-level model types (`VoiceInk/Infrastructure/Persistence/Schema/VoiceInkSchemaV1.swift:17`), so editing those classes would also change the apparent historical schema. Test upgrades from representative older stores, not only a legacy schema assembled from today's types.
- **Measurable performance/privacy gates:** collect cold/warm startup, record-to-first-partial and stop-to-paste p50/p95, idle CPU, peak/retained memory and dropped-buffer counts on the base and branch. Include long sessions, memory pressure and offline operation. Keep transcript text, prompts, keys and URLs out of performance telemetry. Add an end-to-end assertion that selecting an offline mode never silently invokes a cloud fallback.

Recommendation: fix the callback lifetime regression before merging. Track the existing Whisper load race as a separate correctness fix. The passing retry is useful evidence, but does not close the manual audio/paste/XPC verification gaps or explain the first test-host exit.
