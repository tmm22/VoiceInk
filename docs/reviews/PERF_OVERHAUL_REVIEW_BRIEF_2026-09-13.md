# Mac App Performance Overhaul — Review Brief (2026-09-13)

Purpose: hand this work to an independent reviewer. Everything a reviewer needs is in this file
and in the git history of the branch below; no other conversation context is required.

## Where the code is

- Repository clone: `~/Developer/voiceink-sync` (use this, not the iCloud Desktop copy, which hangs on builds)
- Branch: `perf/mac-architecture-overhaul`
- Base: `87a44f47` (v2.13, tip of `origin/custom-main-v2`)
- Head at time of writing: `a2929a4e`
- Not pushed. To publish: `git push -u origin perf/mac-architecture-overhaul`

Review the diff with: `git diff 87a44f47..perf/mac-architecture-overhaul` (109 files, ~2,100 added, ~1,640 removed).

## Verify before reviewing

```
cd ~/Developer/voiceink-sync
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceInkTests -parallel-testing-enabled NO \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: 207 tests, 2 skipped, 0 failures (base was 181/2/0). A clean build takes ~10 minutes.
Requires `~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework` (already present).

## Commits, in order

1. `c973ab9b` refactor(logging): unify OSLog subsystem behind AppLogger.subsystem
2. `99009170`, `771096da` typed `.audioDeviceChanged` notification
3. `df1c84a1` perf(audio): band-limited resampler, vDSP metering, push-based meter UI
4. `50bd692f` perf(latency): adaptive paste wait, deferred launch work, load-only prewarm, direct XPC args
5. `eaada3e9` refactor: single Keychain engine and single appearance preference type
6. `6cf7deea` refactor(streaming): shared LLMkit streaming base for nine cloud providers; pin FluidAudio and mediaremote-adapter
7. `d9705862` logger constant in the new converter file
8. `a2929a4e` perf(recorder): isolate streaming partials from engine observers (LiveTranscriptState)

## What to scrutinise (highest risk first)

1. `VoiceInk/Infrastructure/Audio/RecordingAudioFormatConverter.swift` and its use in
   `CoreAudioRecorder.swift` / `CoreAudioRecorder+Setup.swift`. Check: converter rebuilt on
   device/format change; `flush()` called before file close and before device switch; no
   allocation in the render callback; `AVAudioConverterInputBlock` returns `.noDataNow` after
   handing the buffer once and `.endOfStream` only during flush. Tests:
   `Tests/VoiceInkTests/AudioSystem/RecordingAudioFormatConverterTests.swift`.
   Not verified with a live microphone. A manual recording plus WAV inspection is the one
   remaining verification step.
2. `VoiceInk/Infrastructure/Credentials/KeychainService.swift` + `VoiceInk/TTS/Utilities/KeychainManager.swift`.
   The invariant: `kSecAttrService` strings and keychain flavour per namespace are unchanged, so
   previously stored API keys still resolve. Confirm `.credentials` matches the old
   `KeychainService` query exactly (Data Protection keychain, synchronizable, accessibility) and
   `.loginKeychain(service:)` matches the old `KeychainManager` query (login keychain, no
   synchronizable, `whenUnlocked` accessibility).
3. `VoiceInk/Infrastructure/Providers/Transcription/Cloud/Streaming/LLMKitStreamingProvider.swift`
   and the nine subclasses. Behaviour intended identical to the previous per-vendor copies except:
   `LLMKitError.timeout` now maps to `StreamingTranscriptionError.timeout` for all vendors
   (previously only some), and a vocabulary fetch failure is now logged for all vendors.
   Cartesia's end-of-stream `.committed("")` emission is preserved via hooks.
4. `VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift` + `PrePasteWaitPolicy.swift`.
   Fixed 100 ms wait replaced by modifier-key poll (5 ms, cap 150 ms, floor 20 ms); two of three
   inter-key sleeps removed. Regression surface: apps that need the pasteboard to settle longer.
5. `Shared/VoiceInkRefineXPCProtocol.swift`, `VoiceInkRefineXPC/VoiceInkRefineXPCService.swift`,
   `VoiceInk/Infrastructure/Providers/Enhancement/VoiceInkRefine/VoiceInkRefineXPCClient.swift`.
   Protocol changed to plain String arguments. Both targets must be rebuilt together.
6. `VoiceInk/App/VoiceInk.swift`. Dictionary duplicate sweep moved to a detached task on a
   background `ModelContext`; App Shortcuts donation deferred; `Schema(versionedSchema:)` plus
   `VoiceInkMigrationPlan`. Test `VoiceInkSchemaMigrationTests` reopens a legacy store.
7. `VoiceInk/Features/Recording/State/LiveTranscriptState.swift` and the recorder views.
   `RecorderStateProvider` now exposes `hasPartialTranscript` and `liveTranscript` instead of
   `partialTranscript`.

## Deliberately not done

- Migrating JSON blobs in UserDefaults (prompts, modes, shortcuts, metrics) into SwiftData.
- Moving `TranscriptionServiceRegistry` / model managers off `@MainActor` onto actors.
- Splitting `VoiceInkEngine` beyond the live-transcript extraction.
- Merging the TTS workspace's own OpenAI/Google transcription services with the main providers.
- Removing any transcription engine (Transcribe-cpp serves Cohere GGUF models; ONNX serves
  FastConformer/SenseVoice; none are duplicates of whisper.cpp).

## Prompt to give a reviewing agent

"Read docs/reviews/PERF_OVERHAUL_REVIEW_BRIEF_2026-09-13.md in ~/Developer/voiceink-sync, then
review the branch perf/mac-architecture-overhaul against 87a44f47 for correctness regressions,
in the priority order listed. Run the test command first. Report findings with file:line."
