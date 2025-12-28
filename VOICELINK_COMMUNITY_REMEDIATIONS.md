# VoiceLink Community Remediations (Security & Performance)

Date: 2025-12-20 (latest), 2025-12-19  
Scope: Security hardening, async I/O performance, memory reduction, storage
optimization, concurrency cleanup

This document records the recent rectifications and improvements applied to the
VoiceLink Community codebase, following the updated audit.

## Refactoring and Cleanup (2025-12-29)

### Settings Centralization
- **Issue**: Settings logic was split between `AppSettings` and `UserDefaultsManager`, leading to scattered persistence logic and potential duplication.
- **Fix**: Consolidated all persistence into `AppSettings`. Migrated license/trial key management to `AppSettings+License.swift`. Deleted `UserDefaultsManager.swift`.
- **Files**:
  - `VoiceInk/Utilities/AppSettings+License.swift`
  - `VoiceInk/Services/UserDefaultsManager.swift` (Deleted)

### Shared Utilities
- **Issue**: `AuthorizationHeader` struct was isolated in TTS Utilities but needed by other services.
- **Fix**: Moved to `VoiceInk/Utilities/AuthorizationHeader.swift` and added documentation.
- **Files**:
  - `VoiceInk/Utilities/AuthorizationHeader.swift`

## Performance and Memory Improvements (2025-12-20)

### Stream Audio Preprocessing to Reduce Peak Memory
- **Issue**: Audio preprocessing previously loaded entire files into memory,
  increasing peak RAM usage for long recordings.
- **Fix**: Added a streaming transcode path that converts source audio to a
  Whisper-ready 16 kHz mono WAV without materializing full sample arrays.
- **Files**:
  - `VoiceInk/Services/AudioFileProcessor.swift`
  - `VoiceInk/Services/AudioFileTranscriptionManager.swift`

### Chunked PCM Reads for Local and On-Device Engines
- **Issue**: Local, Parakeet, SenseVoice, and FastConformer flows read full WAV
  data into memory before decoding.
- **Fix**: Introduced `AudioSampleReader` to read PCM16 samples in chunks.
- **Files**:
  - `VoiceInk/Services/AudioSampleReader.swift`
  - `VoiceInk/Services/LocalTranscriptionService.swift`
  - `VoiceInk/Services/ParakeetTranscriptionService.swift`
  - `VoiceInk/Services/SenseVoiceTranscriptionService.swift`
  - `VoiceInk/Services/FastConformerTranscriptionService.swift`

### Stream Transcription Request Bodies
- **Issue**: Multipart and JSON bodies were built in memory for large audio
  uploads.
- **Fix**: Build request bodies on disk and stream via `upload(for:fromFile:)`.
- **Files**:
  - `VoiceInk/TTS/Services/OpenAITranscriptionService.swift`
  - `VoiceInk/TTS/Services/GoogleTranscriptionService.swift`

### Cap AI Context Payload Size at the Source
- **Issue**: Browser text and OCR output could be very large, ballooning AI
  context payloads and memory usage.
- **Fix**: Truncate browser content and OCR text to 5,000 characters before
  they enter the context pipeline. Stored AI request context strings are capped
  for debugging use.
- **Files**:
  - `VoiceInk/Services/AIEnhancement/BrowserContentService.swift`
  - `VoiceInk/Services/ScreenCaptureService.swift`
  - `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

### Reduce TTS History Memory Footprint
- **Issue**: Recent TTS generations stored audio data in memory for every
  history entry.
- **Fix**: Store large audio blobs on disk (cache) with size limits and cleanup,
  keeping only small payloads in memory.
- **Files**:
  - `VoiceInk/TTS/Models/GenerationHistoryItem.swift`
  - `VoiceInk/TTS/ViewModels/TTSViewModel.swift`
  - `VoiceInk/TTS/ViewModels/TTSViewModel+History.swift`

### Avoid Duplicate Audio File Storage
- **Issue**: Retranscriptions and recorded audio copies created redundant data.
- **Fix**: Reuse audio files via hard links when safe, falling back to copies
  when linking is not possible.
- **Files**:
  - `VoiceInk/Utilities/FileCopyUtilities.swift`
  - `VoiceInk/Services/AudioFileTranscriptionService.swift`

### Prevent Playback Timer Leaks
- **Issue**: Playback timers could be scheduled multiple times without cleanup,
  leading to extra timers and unnecessary work.
- **Fix**: Clear timers before starting new ones in the audio player view.
- **Files**:
  - `VoiceInk/Views/AudioPlayerView.swift`

## Security Fixes

### Enforce HTTPS for Custom AI Provider Verification
- **Issue**: Custom AI provider endpoints could be verified over non-HTTPS URLs,
  risking API key exposure during verification.
- **Fix**: `AIProvider.validateSecureURL` is now used inside
  `AIService.verifyOpenAICompatibleAPIKey`, rejecting insecure URLs and only
  allowing localhost for Ollama.
- **Files**:
  - `VoiceInk/Services/AIEnhancement/AIService.swift`

## Performance Improvements

### Avoid Blocking File Reads on Main Actor
- **Issue**: Multiple cloud transcription services used `Data(contentsOf:)`
  directly, which can block the main thread or UI if called from a main-actor
  context.
- **Fix**: Introduced `AudioFileLoader.loadData(from:)` to offload file reads to
  a detached task. In addition, services that support direct file uploads now
  use `URLSession.upload(for:fromFile:)` to avoid full in-memory loads.
- **Files**:
  - `VoiceInk/Services/AudioFileLoader.swift`
  - `VoiceInk/Services/CloudTranscription/DeepgramTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/AssemblyAITranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/GeminiTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/OpenAICompatibleTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/GroqTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/MistralTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/ZAITranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/SonioxTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/ElevenLabsTranscriptionService.swift`

## Concurrency and Main-Thread Cleanup

### Remove Redundant Main-Thread Hops in @MainActor Classes
- **Issue**: Several `@MainActor` classes used `DispatchQueue.main.async` or
  `MainActor.run`, which is redundant and can add latency or reentrancy risk.
- **Fix**: Removed redundant hops and updated state directly on the main actor.
- **Files**:
  - `VoiceInk/SoundManager.swift`
  - `VoiceInk/Whisper/WhisperState+LocalModelManager.swift`
  - `VoiceInk/MenuBarManager.swift`

## I/O and UserDefaults Adjustments

### Remove Forced UserDefaults Synchronization
- **Issue**: `UserDefaults.synchronize()` forces disk I/O and can be a
  performance drag on hot paths.
- **Fix**: Removed `synchronize()` calls in prompt update flows.
- **Files**:
  - `VoiceInk/Whisper/WhisperPrompt.swift`

## Summary of Changes

- Custom AI provider verification now enforces HTTPS for API key safety.
- Audio file handling avoids blocking reads and reduces main-thread I/O.
- Redundant main-thread dispatches removed in main-actor classes.
- Forced UserDefaults synchronization removed from prompt updates.
- Audio preprocessing and transcription uploads now stream to lower peak memory.
- AI context payloads are capped at the source to control memory use.
- TTS history audio is cached on disk with size limits to reduce RAM pressure.
- Audio file copies reuse hard links when possible to reduce storage overhead.

## Modification Log (2025-12-20)

### Performance
- Streamed audio preprocessing to avoid loading full sample arrays.
  - `VoiceInk/Services/AudioFileProcessor.swift`
  - `VoiceInk/Services/AudioFileTranscriptionManager.swift`
- Streamed transcription request bodies for OpenAI and Google.
  - `VoiceInk/TTS/Services/OpenAITranscriptionService.swift`
  - `VoiceInk/TTS/Services/GoogleTranscriptionService.swift`

### Memory
- Chunked PCM sample reads for local/on-device transcription engines.
  - `VoiceInk/Services/AudioSampleReader.swift`
  - `VoiceInk/Services/LocalTranscriptionService.swift`
  - `VoiceInk/Services/ParakeetTranscriptionService.swift`
  - `VoiceInk/Services/SenseVoiceTranscriptionService.swift`
  - `VoiceInk/Services/FastConformerTranscriptionService.swift`
- Capped browser/OCR context and stored AI request payloads.
  - `VoiceInk/Services/AIEnhancement/BrowserContentService.swift`
  - `VoiceInk/Services/ScreenCaptureService.swift`
  - `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- Cached recent TTS history audio on disk with size limits.
  - `VoiceInk/TTS/Models/GenerationHistoryItem.swift`
  - `VoiceInk/TTS/ViewModels/TTSViewModel.swift`
  - `VoiceInk/TTS/ViewModels/TTSViewModel+History.swift`

### Storage
- Reused audio files via hard links when safe to reduce duplicates.
  - `VoiceInk/Utilities/FileCopyUtilities.swift`
  - `VoiceInk/Services/AudioFileTranscriptionService.swift`

### Reliability
- Prevented duplicate playback timers.
  - `VoiceInk/Views/AudioPlayerView.swift`

## Modification Log (2025-12-19)

### Security
- Enforced HTTPS validation for custom AI provider verification.
  - `VoiceInk/Services/AIEnhancement/AIService.swift`

### Performance
- Added async file loader for audio files to avoid blocking reads.
  - `VoiceInk/Services/AudioFileLoader.swift`
- Switched cloud transcription uploads to async file handling or upload-by-file.
  - `VoiceInk/Services/CloudTranscription/DeepgramTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/AssemblyAITranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/GeminiTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/OpenAICompatibleTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/GroqTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/MistralTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/ZAITranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/SonioxTranscriptionService.swift`
  - `VoiceInk/Services/CloudTranscription/ElevenLabsTranscriptionService.swift`

### Concurrency and Main-Thread Cleanup
- Removed redundant main-thread hops in `@MainActor` classes.
  - `VoiceInk/SoundManager.swift`
  - `VoiceInk/Whisper/WhisperState+LocalModelManager.swift`
  - `VoiceInk/MenuBarManager.swift`

### I/O and UserDefaults
- Removed forced `UserDefaults.synchronize()` calls in prompt updates.
  - `VoiceInk/Whisper/WhisperPrompt.swift`

### Documentation
- Added and linked remediation documentation, changelog, and standards updates.
  - `README.md`
  - `START_HERE.md`
  - `DESIGN_DOCUMENT.md`
  - `CODE_AUDIT_REPORT.md`
  - `SECURITY_FIXES_SUMMARY.md`
  - `CHANGELOG.md`

## Suggested Validation

- Run `./run_tests.sh` to confirm no regressions.
- Exercise custom AI provider configuration to confirm HTTPS validation.
- Transcribe a large audio file to confirm UI remains responsive.
