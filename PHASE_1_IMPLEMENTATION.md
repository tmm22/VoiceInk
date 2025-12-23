# Phase 1 Implementation Checklist

Scope: Critical + High issues from the 2025-12-05 code review.

## Status
- [ ] In progress
- [x] Ready for review
- [ ] Complete

## Review Phase 1/2: Critical + High Issues
### CRITICAL-001: deinit calling @MainActor methods via Task
- [x] `VoiceInk/HotkeyManager.swift` direct cleanup in `deinit`
- [x] `VoiceInk/MiniRecorderShortcutManager.swift` direct cleanup in `deinit`

### CRITICAL-002: HTTPS validation for custom URLs
- [x] `VoiceInk/Services/CloudTranscription/CustomModelManager.swift` enforce https scheme + host
- [x] `VoiceInk/TTS/Utilities/ManagedProvisioningPreferences.swift` enforce https scheme + host
- [x] `VoiceInk/Models/TranscriptionModel.swift` enforce https scheme + host

### CRITICAL-003: Stable `WhisperStateError.id`
- [x] `VoiceInk/Whisper/WhisperError.swift` use stable identifiers

### CRITICAL-004: Real microphone permission checks
- [x] `VoiceInk/Whisper/WhisperState.swift` implement `AVCaptureDevice` permission handling

### CRITICAL-005: Missing browsers in `BrowserType.allCases`
- [x] `VoiceInk/PowerMode/BrowserURLService.swift` include Firefox + Zen

### CRITICAL-006: Timer strong capture
- [x] `VoiceInk/Notifications/AppNotificationView.swift` use weak capture + invalidate on nil

### HIGH-001: Missing `[weak self]` in Tasks
- [x] `VoiceInk/Whisper/WhisperState.swift` (all Task captures)
- [x] `VoiceInk/Whisper/WhisperModelWarmupCoordinator.swift`
- [x] `VoiceInk/Services/AudioFileTranscriptionManager.swift`
- [x] `VoiceInk/HotkeyManager.swift`
- [x] `VoiceInk/Recorder.swift`
- [x] `VoiceInk/SoundManager.swift`
- [x] `VoiceInk/PowerMode/PowerModeSessionManager.swift`
- [x] `VoiceInk/MiniRecorderShortcutManager.swift`

### HIGH-002: Missing `@MainActor`
- [x] `VoiceInk/Notifications/NotificationManager.swift`
- [x] `VoiceInk/Notifications/AnnouncementManager.swift`
- [x] `VoiceInk/WindowManager.swift`
- [x] `VoiceInk/Services/TranscriptionAutoCleanupService.swift`
- [x] `VoiceInk/TTS/Services/ManagedProvisioningClient.swift`
- [x] `VoiceInk/TTS/Utilities/ManagedProvisioningPreferences.swift`
- [x] `VoiceInk/Whisper/VADModelManager.swift`
- [x] `VoiceInk/PowerMode/BrowserURLService.swift`

### HIGH-003: Redundant `MainActor.run` in `@MainActor` classes
- [x] `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- [x] `VoiceInk/Services/ScreenCaptureService.swift`
- [x] `VoiceInk/Services/AudioFileTranscriptionService.swift`
- [x] `VoiceInk/Whisper/WhisperState+UI.swift`
- [x] `VoiceInk/Whisper/WhisperState+LocalModelManager.swift`
- [x] `VoiceInk/Services/ImportExportService.swift`

### HIGH-004: Missing deinit cleanup
- [x] `VoiceInk/Services/AnnouncementsService.swift`
- [x] `VoiceInk/Notifications/NotificationManager.swift`
- [x] `VoiceInk/PlaybackController.swift`
- [x] `VoiceInk/Whisper/WhisperState.swift`

### HIGH-005: Unguarded print statements
- [x] `VoiceInk/PowerMode/PowerModeSessionManager.swift`
- [x] `VoiceInk/MenuBarManager.swift`
- [x] `VoiceInk/Views/ContentView.swift`
- [x] `VoiceInk/Views/AudioTranscribeView.swift`
- [x] `VoiceInk/Services/CloudTranscription/DeepgramTranscriptionService.swift`
- [x] `VoiceInk/Services/CloudTranscription/AssemblyAITranscriptionService.swift`
- [x] `VoiceInk/TTS/ViewModels/TTSViewModel+Helpers.swift`

## Quality Gates
- [ ] Build succeeds
- [ ] Targeted tests updated or added
- [ ] No new warnings
- [ ] Docs updated (if public API changed)

## Notes / Decisions
- [x] Deferred structural refactors (TTSViewModel/WhisperState splits) to Phase 2 to keep Phase 1 scoped to critical/high fixes
