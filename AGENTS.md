# AI Agents Guide for VoiceInk

This document provides comprehensive guidance for AI coding assistants (Claude, GPT-4, Cursor, GitHub Copilot, etc.) working with the VoiceInk codebase.

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Technologies](#architecture--technologies)
3. [Codebase Structure](#codebase-structure)
4. [Coding Standards](#coding-standards)
5. [Memory Management](#memory-management)
6. [Production Standards](#production-standards)
7. [Security Guidelines](#security-guidelines)
8. [Common Patterns](#common-patterns)
9. [AI Context System](#ai-context-system)
10. [Testing & Quality](#testing--quality)
11. [Working with Features](#working-with-features)
12. [Troubleshooting](#troubleshooting)
13. [Contributing Workflow](#contributing-workflow)

---

## Project Overview

**VoiceInk** is a privacy-focused, native macOS application for voice-to-text transcription with AI enhancement capabilities.

### Core Principles

1. **Privacy First**: 100% offline processing, no data leaves the device
2. **Native Performance**: Built with SwiftUI for optimal macOS integration
3. **Accessibility Focus**: Designed for users with disabilities and diverse needs
4. **Modular Architecture**: Clean separation of concerns for maintainability

### Key Features

- **Whisper Integration**: Local AI transcription with multiple model sizes
- **Power Mode**: Context-aware AI that adapts to active app/URL
- **AI Enhancement**: Text refinement with multiple AI providers (Ollama, OpenAI, etc.)
- **TTS Workspace**: Text-to-speech with ElevenLabs, OpenAI, Google Cloud TTS
- **Personal Dictionary**: Custom terminology and pronunciation rules
- **Cloud Transcription**: Optional providers (Groq, Deepgram, Gemini, etc.)

---

## Architecture & Technologies

### Tech Stack

```
Platform:    macOS 14.0+ (Sonoma)
Language:    Swift 5.9+
Framework:   SwiftUI, Combine, AVFoundation
ML:          Core ML, Whisper.cpp bindings
Audio:       AVAudioEngine, AudioKit
Security:    Keychain Services, App Sandbox
```

### Key Dependencies

- **WhisperKit**: Local Whisper model inference
- **Parakeet**: Alternative transcription engine
- **llama.cpp**: Local LLM inference (via Ollama)
- **AVFoundation**: Audio capture and playback
- **Combine**: Reactive programming for state management

### Concurrency Model

**VoiceInk uses Swift's modern concurrency:**

```swift
// Main actor isolation for UI
@MainActor
class TTSViewModel: ObservableObject {
    // All UI updates happen on main thread
}

// Async/await for network and I/O
func synthesizeSpeech(text: String) async throws -> Data {
    let (data, _) = try await session.data(for: request)
    return data
}

// Actors for shared mutable state
actor TranscriptionQueue {
    private var queue: [TranscriptionJob] = []
}
```

**Critical Rules:**
- ✅ Always use `@MainActor` for view models and UI-related classes
- ✅ ALL `ObservableObject` classes with `@Published` properties MUST be marked `@MainActor`
- ✅ Classes that access `@MainActor` singletons must also be `@MainActor`
- ✅ Use `async/await` for network calls and file I/O
- ✅ Use `Task` for background work
- ✅ Avoid blocking file reads on the main actor (prefer `URLSession.upload(fromFile:)` or async loaders)
- ✅ For local file reads that would otherwise use `Data(contentsOf:)`, prefer [`FileDataLoader.loadData(from:options:)`](VoiceInk/Services/FileDataLoader.swift:9) (uses `.mappedIfSafe` by default and runs in a detached task to avoid main-actor stalls)
- ⛔ Never block the main thread
- ⛔ Avoid completion handlers (use async/await instead)
- ⛔ Never call `@MainActor` methods from `deinit` (use direct cleanup instead)
- ⛔ Never use `MainActor.run` or `DispatchQueue.main.async` inside `@MainActor` classes (redundant)

**ObservableObject Requirements:**

> **Why This Matters:** In Swift 6 strict concurrency mode, `@Published` property wrappers must be accessed from the same actor context. Without `@MainActor`, concurrent access to `@Published` properties causes data races and potential crashes. The 2025-12-03 code review found 14 ObservableObject classes missing this annotation, all of which could cause subtle threading bugs.

```swift
// ✅ REQUIRED: All ObservableObject classes MUST use @MainActor
@MainActor
class AudioDeviceManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
}

// ⛔ NEVER: ObservableObject without @MainActor
class AudioDeviceManager: ObservableObject {  // Missing @MainActor - will cause data races!
    @Published var availableDevices: [AudioDevice] = []
}
```

**deinit with @MainActor - Comprehensive Cleanup:**

> **Context:** `deinit` is nonisolated in Swift, meaning it cannot call `@MainActor`-isolated methods. This is a common source of bugs when trying to clean up timers, observers, or cancel tasks.

```swift
@MainActor
class TimerManager: ObservableObject {
    private var timer: Timer?
    private var monitorTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // ✅ Good: Direct cleanup in deinit (doesn't call isolated methods)
    deinit {
        // Direct property access is OK
        timer?.invalidate()
        
        // Task cancellation is OK (cancel() is thread-safe)
        monitorTask?.cancel()
        
        // Remove observers directly
        NotificationCenter.default.removeObserver(self)
        
        // Cancel all Combine subscriptions
        cancellables.removeAll()
    }
    
    // ⛔ Bad: Calling @MainActor method from deinit causes compiler error
    deinit {
        stopTimer()  // Error: Can't call isolated method from deinit
        cleanup()    // Error: Same issue
    }
}
```

**deinit Cleanup Checklist:**

Every class with cleanup requirements should verify these in `deinit`:

- [ ] **Timers**: Call `timer?.invalidate()` directly
- [ ] **Tasks**: Call `task?.cancel()` directly (cancel() is thread-safe)
- [ ] **Observers**: Call `NotificationCenter.default.removeObserver(self)`
- [ ] **Combine**: Clear `cancellables.removeAll()` or let them deallocate
- [ ] **Audio**: Stop audio engines directly if stored as properties
- [ ] **KVO**: Remove any KVO observers

### Redundant `MainActor.run` in `@MainActor` Classes

> **Context:** The 2025-12-05 code review found 17+ instances of redundant `MainActor.run` and `DispatchQueue.main.async` calls inside classes already marked `@MainActor`. This adds unnecessary overhead and clutters code.

**Rule: Never use `MainActor.run` or `DispatchQueue.main.async` inside `@MainActor` classes.**

```swift
@MainActor
class MyService: ObservableObject {
    @Published var data: String = ""
    
    // ⛔ WRONG: Redundant MainActor.run - already on MainActor!
    func updateData() async {
        await MainActor.run {
            self.data = "updated"
        }
    }
    
    // ⛔ WRONG: Redundant DispatchQueue.main
    func handleCallback() {
        DispatchQueue.main.async {
            self.data = "updated"
        }
    }
    
    // ✅ CORRECT: Direct assignment - class is already @MainActor
    func updateData() async {
        self.data = "updated"
    }
    
    // ✅ CORRECT: For @objc callbacks, use Task
    @objc func handleNotification() {
        Task { @MainActor [weak self] in
            self?.data = "updated"
        }
    }
}
```

**When IS `MainActor.run` needed:**
- In nonisolated functions that need to update `@MainActor` state
- In detached Tasks that need to call back to the main actor
- NOT inside `@MainActor` classes or their methods

---

## Codebase Structure

```
VoiceInk/
├── VoiceInk.swift              # App entry point
├── AppDelegate.swift           # App lifecycle
├── Models/                     # Data models
│   ├── TranscriptionModel.swift
│   ├── PredefinedModels.swift
│   └── LicenseViewModel.swift
├── Views/                      # SwiftUI views
│   ├── ContentView.swift
│   ├── MenuBarView.swift
│   ├── Settings/               # Settings screens
│   ├── Recorder/               # Recording UI
│   ├── AI Models/              # Model management
│   ├── Dictionary/             # Custom dictionary
│   ├── Onboarding/             # First-run experience
│   ├── Components/             # Reusable UI components
│   └── Common/                 # Shared view utilities
├── Utilities/
│   ├── AppLogger.swift               # OSLog wrapper
│   ├── Localization.swift            # String localization
│   ├── DesignSystem.swift            # UI constants
│   ├── View+VoiceInkStyle.swift      # SwiftUI modifiers
│   ├── AppSettings.swift             # Centralized settings wrapper
│   └── AuthorizationHeader.swift     # Shared auth header struct
├── Services/                   # Business logic
│   ├── TranscriptionService.swift
│   ├── AIEnhancementService.swift
│   ├── AudioDeviceManager.swift
│   ├── ScreenCaptureService.swift
│   ├── MetricsManager.swift    # MetricKit production performance monitoring
│   ├── CloudTranscription/     # Cloud provider integrations
│   ├── OllamaAIService.swift
│   └── CloudSyncService.swift  # iCloud Sync integration
├── Whisper/                    # Local Whisper integration (SOLID architecture)
│   ├── WhisperState.swift      # Main coordinator (backward compatible)
│   ├── ModelManager.swift      # Model coordination with Combine bindings
│   ├── RecordingState.swift    # Recording state enum
│   ├── LibWhisper.swift        # C bindings to whisper.cpp
│   ├── WhisperState+*.swift    # Feature extensions (UI, Recording, Parakeet, etc.)
│   ├── Protocols/              # SOLID protocol definitions
│   │   ├── ModelProviderProtocol.swift
│   │   ├── RecordingSessionProtocol.swift
│   │   ├── TranscriptionProcessorProtocol.swift
│   │   └── UIManagerProtocol.swift
│   ├── Providers/              # Model provider implementations
│   │   ├── LocalModelProvider.swift      # Whisper.cpp models
│   │   └── ParakeetModelProvider.swift   # Parakeet models
│   ├── Managers/               # State and resource managers
│   │   ├── RecordingSessionManager.swift
│   │   ├── AudioBufferManager.swift
│   │   └── UIManager.swift
│   ├── Processors/             # Transcription processing pipeline
│   │   ├── TranscriptionProcessor.swift
│   │   ├── AudioPreprocessor.swift
│   │   └── TranscriptionResultProcessor.swift
│   ├── Actors/                 # Thread-safe actors
│   │   └── WhisperContextManager.swift   # @globalActor for Whisper ops
│   ├── Coordinators/           # Workflow coordination
│   │   └── InferenceCoordinator.swift    # Priority queue with cancellation
│   └── Models/                 # Data models
│       └── WhisperContextWrapper.swift
├── TTS/                        # Text-to-Speech workspace
│   ├── Models/
│   ├── Services/               # Provider implementations
│   ├── ViewModels/
│   ├── Views/
│   └── Utilities/
├── PowerMode/                  # Context-aware AI
│   ├── PowerModeSessionManager.swift
│   ├── ActiveWindowService.swift
│   └── BrowserURLService.swift
├── Notifications/              # Notification system
├── AppIntents/                 # Siri Shortcuts
├── Resources/                  # Assets and sounds
└── Preview Content/            # SwiftUI previews
```

### File Naming Conventions

- **Models**: `*Model.swift` or descriptive noun (e.g., `TranscriptionModel.swift`)
- **Views**: `*View.swift` (e.g., `SettingsView.swift`)
- **Services**: `*Service.swift` or `*Manager.swift` (e.g., `AIService.swift`)
- **Extensions**: `Type+Feature.swift` (e.g., `WhisperState+UI.swift`)
- **Protocols**: Descriptive adjective ending in `-ing` or `-able` (e.g., `URLContentLoading`)

### File Size Limits

> **Context:** The 2025-12-03 code review identified TTSViewModel.swift at 2,936 lines and TTSWorkspaceView.swift at 1,907 lines. Large files are difficult to maintain, test, and review.

**Rules:**
- ✅ Files SHOULD NOT exceed **500 lines** of code
- ✅ Files MUST NOT exceed **1,000 lines** of code without explicit justification
- ⛔ Never let a file grow beyond 2,000 lines - refactor immediately

**Strategies for Splitting Large Files:**

1. **Use Extensions for Feature Groups:**
```swift
// WhisperState.swift - Core functionality (~300 lines)
// WhisperState+ModelManagement.swift - Model download/delete (~200 lines)
// WhisperState+UI.swift - UI-related computed properties (~150 lines)
// WhisperState+Parakeet.swift - Parakeet integration (~200 lines)
```

2. **Extract Subviews:**
```swift
// ❌ Before: One massive TTSWorkspaceView.swift (1,907 lines)

// ✅ After: Logical breakdown
// TTSWorkspaceView.swift - Main container (~200 lines)
// TTSTextEditorView.swift - Text input area (~150 lines)
// TTSPlaybackControlsView.swift - Audio controls (~100 lines)
// TTSSettingsView.swift - Settings panels (~150 lines)
// TTSInspectorView.swift - Side panel (~200 lines)
```

3. **Extract Helper Types:**
```swift
// Move nested types to separate files
// TTSError.swift - Error definitions
// TTSConstants.swift - Configuration values
// TTSProviderType.swift - Enum definitions
```

### Single Source of Truth

> **Context:** The 2026-03-07 code review found `TranscriptionHistoryView`, `HistoryTranscriptionView`, and `TranscriptionHistoryLegacyView` drifting after fixes landed in only one copy.

**Rule: One feature/screen should have exactly one real implementation.**

When a view or service is superseded:
- ✅ Delete the duplicate, OR
- ✅ Replace old entry points with a thin wrapper/typealias that forwards to the canonical implementation
- ⛔ Never keep multiple near-identical copies of a screen or service and edit them independently

```swift
// ✅ Good: Legacy name forwards to the real implementation
@available(*, deprecated, message: "Use TranscriptionHistoryView")
typealias HistoryTranscriptionView = TranscriptionHistoryView

// ✅ Good: Compatibility wrapper delegates to the canonical view
struct TranscriptionHistoryLegacyView: View {
    var body: some View { TranscriptionHistoryView() }
}

// ⛔ Bad: Forked copy that will drift
struct HistoryTranscriptionView: View {
    // 400 lines copied from TranscriptionHistoryView
}
```

---

## Coding Standards

### Swift Style Guide

VoiceInk follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with these additions:

#### Naming

```swift
// ✅ Good: Clear, descriptive names
func transcribeAudio(from url: URL) async throws -> Transcription
var isRecording: Bool
let maximumRecordingDuration: TimeInterval

// ⛔ Bad: Abbreviated or unclear
func tscr(url: URL) -> Transcription
var rec: Bool
let maxDur: TimeInterval
```

#### Code Organization

```swift
// MARK: - Properties
private let service: TranscriptionService
@Published var transcriptionText: String = ""

// MARK: - Initialization
init(service: TranscriptionService) {
    self.service = service
}

// MARK: - Public Methods
func startRecording() {
    // Implementation
}

// MARK: - Private Methods
private func processAudio() {
    // Implementation
}
```

#### Access Control

```swift
// Default to private, expose only what's necessary
private let audioEngine = AVAudioEngine()
internal let session: URLSession  // Internal for testing
public func synthesizeSpeech() { }  // Public API
```

### Logging

**ALWAYS use `AppLogger` (OSLog) for logging. All `print()` statements MUST be wrapped in `#if DEBUG`.**

```swift
// ✅ Good: Structured, categorized logging (preferred)
AppLogger.transcription.error("Failed to transcribe: \(error)")

// ✅ Good: Debug-only print statements (acceptable for development)
#if DEBUG
print("Debug: Processing file \(filename)")
#endif

// ⛔ Bad: Unstructured logging, spams console
print("Error: \(error)")

// ⛔ Bad: Unguarded print ships to production
print("Debug: Processing file \(filename)")  // Ships to production!
```

#### Sensitive Data Logging

> **Context:** The 2026-03-07 code review found AI system prompts, transcript text, enhanced text, and active browser URLs logged with `privacy: .public`.

**Rule: Never log user content or derived context payloads.**

Sensitive payloads include:
- API keys, bearer tokens, authorization headers
- Transcript text, enhanced text, prompts, conversation history
- Clipboard contents, focused-element text, selected file contents
- Browser URLs, page titles, screen-capture OCR, calendar events

```swift
// ✅ Good: Log metadata only
logger.debug("Transcript received. Character count: \(text.count, privacy: .public)")
logger.debug("Browser URL fetch succeeded for \(browser.displayName, privacy: .public)")

// ✅ Good: If correlation is needed, log a hash or identifier instead of content
logger.debug("Prompt template id: \(prompt.id.uuidString, privacy: .public)")

// ⛔ Bad: Logging sensitive payloads
logger.notice("Transcript: \(text, privacy: .public)")
logger.notice("System prompt: \(systemMessage, privacy: .public)")
logger.debug("Current URL: \(output, privacy: .public)")
```

### Localization

**All user-facing strings MUST be localized.**

```swift
// ✅ Good: Using Localization struct
NotificationManager.shared.showNotification(
    title: Localization.Transcription.noTranscriptionAvailable,
    type: .error
)

// ⛔ Bad: Hardcoded string
title: "No transcription available"
```

### Safety

**Avoid force unwrapping (`!`) in production code.**

```swift
// ✅ Good: Safe unwrapping
if let result = result {
    process(result)
}

// ⛔ Bad: Force unwrap
process(result!)
```

### Data Encoding

**Use safe UTF-8 encoding patterns for multipart form data and string conversions.**

```swift
// ✅ Good: Safe UTF-8 encoding (never fails for valid Swift strings)
body.append(Data("--\(boundary)\r\n".utf8))
body.append(Data(modelName.utf8))
body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))

// ⛔ Bad: Force unwrap on encoding (unnecessary crash risk)
body.append("--\(boundary)\r\n".data(using: .utf8)!)
body.append(modelName.data(using: .utf8)!)
```

### Error Handling

**Use typed errors and NEVER silently swallow failures:**

```swift
enum TTSError: LocalizedError {
    case invalidAPIKey
    case networkError(String)
    case quotaExceeded
    case textTooLong(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .networkError(let message):
            return "Network error: \(message)"
        case .quotaExceeded:
            return "API quota exceeded."
        case .textTooLong(let limit):
            return "Text exceeds maximum length of \(limit) characters."
        }
    }
}
```

#### Silent Failure Prevention

> **Context:** The 2025-12-03 code review found multiple instances of `try?` used without logging in AIEnhancementService.swift and AIService.swift. Silent failures make debugging extremely difficult.

**Rule: `try?` MUST be accompanied by error logging OR have explicit justification.**

```swift
// ✅ Good: try? with logging for recoverable failures
if let data = try? await fetchData() {
    process(data)
} else {
    AppLogger.network.warning("Failed to fetch data, using cached version")
    useCachedData()
}

// ✅ Good: try? with explicit comment explaining why silent is OK
// Cleanup failure is non-critical - file may not exist
try? FileManager.default.removeItem(at: tempURL)

// ✅ Good: try? in defer for best-effort cleanup
defer {
    // Best-effort cleanup, failure is acceptable
    try? FileManager.default.removeItem(at: tempURL)
}

// ⛔ Bad: Silent failure with no logging or justification
let result = try? service.process(data)  // What happened if this failed?

// ⛔ Bad: Ignoring errors in critical paths
try? keychain.save(apiKey, for: .openAI)  // User has no idea save failed!
```

**Pattern for Critical vs Recoverable Failures:**

```swift
// Critical failures - MUST throw or show error to user
func saveAPIKey(_ key: String) throws {
    do {
        try keychain.save(key, for: provider)
    } catch {
        AppLogger.security.error("Failed to save API key: \(error)")
        throw SettingsError.keychainSaveFailed(error)
    }
}

// Recoverable failures - Log and continue with fallback
func loadCachedTranscription() -> Transcription? {
    do {
        return try cache.load()
    } catch {
        AppLogger.cache.info("Cache miss: \(error.localizedDescription)")
        return nil  // Fallback: will fetch fresh data
    }
}
```

### Audio File Guidelines

**Use proper audio formats for bundled sound files. Verify format before committing.**

VoiceInk uses WAV and MP3 files for audio feedback. When adding or generating audio files:

```bash
# ✅ Good: Verify audio file format before committing
file VoiceInk/Resources/Sounds/my-sound.mp3
# Expected output for MP3: "Audio file with ID3 version 2.4.0, contains: MPEG ADTS, layer III..."
# Expected output for WAV: "RIFF (little-endian) data, WAVE audio..."

# ⛔ Bad: M4A/AAC file incorrectly named as .mp3
file VoiceInk/Resources/Sounds/my-sound.mp3
# Output: "ISO Media, MP4 v2 [ISO 14496-14]"  # This is NOT an MP3!
```

**Critical Rules:**
- ✅ Use WAV format for generated/synthesized sounds (universally compatible)
- ✅ Use actual MP3 files if MP3 extension is specified in code
- ✅ Verify file format with `file` command before committing
- ✅ Match file extensions in code (`AudioFeedbackSettings.swift`) to actual file formats
- ⛔ Never use `afconvert` to create "MP3" files (it creates M4A/AAC containers)
- ⛔ Never rename M4A/AAC files to `.mp3` extension

**Generating Audio Files:**

```python
# ✅ Good: Generate proper WAV files with scipy
from scipy.io import wavfile
import numpy as np

audio_data = (np.sin(2 * np.pi * 440 * t) * 32767).astype(np.int16)
wavfile.write("sound.wav", 44100, audio_data)

# ⛔ Bad: Using afconvert and renaming (creates M4A, not MP3)
# afconvert -f mp4f -d aac input.wav output.m4a
# mv output.m4a output.mp3  # WRONG - still M4A inside!
```

**Sound File Locations:**
- All sound files go in `VoiceInk/Resources/Sounds/`
- Files are automatically included via Xcode's synchronized folder feature
- Reference files in `AudioFeedbackSettings.swift` with correct extensions

---

### SwiftUI Best Practices

```swift
// ✅ Good: Extract complex views
struct SettingsView: View {
    var body: some View {
        ScrollView {
            APIKeysSection()
            AudioSettingsSection()
            GeneralSettingsSection()
        }
    }
}

// ✅ Good: Use @ViewBuilder for conditional views
@ViewBuilder
private func statusIndicator() -> some View {
    if isRecording {
        RecordingIndicator()
    } else {
        IdleIndicator()
    }
}

// ⛔ Bad: Massive body with nested conditionals
var body: some View {
    VStack {
        if condition1 {
            if condition2 {
                // 50 lines of UI...
            }
        }
    }
}
```

---

## Memory Management

> **Context:** The 2025-12-03 code review found multiple memory management issues: Tasks missing `[weak self]`, missing Task cancellation in deinit, and strong captures in callbacks. These cause memory leaks and retain cycles.

### Task Lifecycle Management

**Rule: ALL Tasks that capture `self` and are stored/long-lived MUST use `[weak self]`.**

> **Why This Matters:** A Task that captures `self` strongly will prevent the object from being deallocated until the Task completes. For long-running or infinite Tasks (like monitoring loops), this causes permanent memory leaks.

```swift
@MainActor
class Recorder: ObservableObject {
    private var durationUpdateTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    
    // ✅ Good: Task with [weak self] - object can deallocate
    func startDurationUpdates() {
        durationUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.updateDuration()  // Use optional chaining
            }
        }
    }
    
    // ⛔ Bad: Strong capture prevents deallocation
    func startDurationUpdates() {
        durationUpdateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.updateDuration()  // Strong capture - MEMORY LEAK!
            }
        }
    }
    
    // ✅ Required: Cancel ALL stored Tasks in deinit
    deinit {
        durationUpdateTask?.cancel()
        monitoringTask?.cancel()
    }
}
```

### Task Cancellation in deinit

**Rule: ALL Task properties MUST be cancelled in deinit.**

```swift
@MainActor
class AudioPlayerService: ObservableObject {
    private var fadeTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    
    // ✅ Required: Cancel every Task property
    deinit {
        fadeTask?.cancel()
        playbackTask?.cancel()
        monitorTask?.cancel()
    }
}
```

### Closures and Callbacks

**Rule: Long-lived closures (stored callbacks, notification handlers) MUST use `[weak self]}` for classes.**

```swift
// ✅ Good: Combine sink with [weak self]
NotificationCenter.default
    .publisher(for: .AVCaptureDeviceWasConnected)
    .sink { [weak self] _ in
        self?.refreshDevices()
    }
    .store(in: &cancellables)

// ✅ Good: Timer with [weak self] in a CLASS
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.updateUI()
}

// ✅ Good: Stored closure with [weak self]
audioEngine.onComplete = { [weak self] in
    self?.handleCompletion()
}

// ⛔ Bad: Strong capture in stored closure
audioEngine.onComplete = {
    self.handleCompletion()  // Retain cycle!
}
```

### SwiftUI Structs and `[weak self]`

> **Context:** The 2025-12-05 code review found a build error caused by using `[weak self]` in a SwiftUI View struct. Value types cannot use weak references.

**Rule: `[weak self]` is ONLY for classes. SwiftUI Views are structs.**

```swift
// ⛔ WRONG: SwiftUI View is a struct - this causes a compiler error!
struct NotificationView: View {
    @State private var timer: Timer?
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // ERROR: 'weak' may only be applied to class and class-bound protocol types
            self?.updateProgress()
        }
    }
}

// ✅ CORRECT: For structs, rely on SwiftUI lifecycle (onDisappear) for cleanup
struct NotificationView: View {
    @State private var timer: Timer?
    @State private var progress: Double = 1.0
    
    var body: some View {
        ProgressView(value: progress)
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }  // Cleanup on view removal
    }
    
    func startTimer() {
        // No [weak self] needed - structs are value types
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if progress > 0 {
                progress -= 0.01
            }
        }
    }
}
```

**Key Insight:** SwiftUI manages View lifecycle. Use `onDisappear` to invalidate timers and clean up resources in Views.

### Nonisolated Methods Creating Tasks

**Pattern for delegate methods and callbacks that need to call @MainActor methods:**

```swift
@MainActor
class AudioDeviceManager: ObservableObject {
    // Delegate callback - nonisolated context
    nonisolated func audioDeviceDidChange(_ device: AudioDevice) {
        // ✅ Correct: Create Task with [weak self] for nonisolated -> MainActor
        Task { [weak self] in
            await self?.handleDeviceChange(device)
        }
    }
    
    private func handleDeviceChange(_ device: AudioDevice) {
        // This runs on MainActor
        self.currentDevice = device
        self.refreshDeviceList()
    }
    
    // ⛔ Bad: Strong capture from nonisolated context
    nonisolated func audioDeviceDidChange(_ device: AudioDevice) {
        Task {
            await self.handleDeviceChange(device)  // Strong capture!
        }
    }
}
```

### Memory Management Checklist

Before submitting code with Tasks or closures:

- [ ] All stored Tasks use `[weak self]`
- [ ] All Task properties are cancelled in `deinit`
- [ ] Combine subscriptions stored in `cancellables` Set
- [ ] Timer callbacks use `[weak self]`
- [ ] Stored closures/callbacks use `[weak self]`
- [ ] Nonisolated methods creating Tasks use `[weak self]`
- [ ] No strong reference cycles between objects

---

## Production Standards

VoiceInk aims for production-grade quality. Every contribution must meet these criteria:

1. **Zero Regressions**: Existing tests must pass. New features must include tests.
2. **Secure by Design**: Secrets in Keychain only. No insecure fallbacks (e.g. UserDefaults).
3. **Localized**: No hardcoded strings in UI/Service layers. Use `Localization`.
4. **Observability**: Use `AppLogger` for all significant events and errors.
5. **Zero Artifacts**: Commit history must be clean (no `TestResults`, derived data, or secrets).

---

## Security Guidelines

**VoiceInk handles sensitive user data (API keys, recordings, transcripts). Security is paramount.**

### 1. Credential Storage

**ALWAYS use macOS Keychain for API keys. Never use UserDefaults fallbacks.**

> **Note:** Legacy API key migration from UserDefaults has been completed. All cloud transcription services now use Keychain-only access. Never add UserDefaults fallbacks for credentials.
>
> **LOCAL_BUILD is NOT an exception:** Unsigned/local builds must still use Keychain. If local entitlements cannot support syncable/shared items, disable sync (`syncable: false`) or fail closed. Never redirect secrets to `UserDefaults`, temp files, or plist storage.

```swift
// ✅ Good: Keychain storage with no fallback
let keychain = KeychainManager()
keychain.saveAPIKey(apiKey, for: "OpenAI")

// ✅ Good: Keychain-only retrieval
func getAPIKey() throws -> String {
    guard let key = keychain.getAPIKey(for: provider), !key.isEmpty else {
        throw CloudTranscriptionError.missingAPIKey
    }
    return key
}

// ⛔ NEVER: UserDefaults or plist
UserDefaults.standard.set(apiKey, forKey: "openai_key")  // INSECURE!

// ⛔ NEVER: UserDefaults fallback pattern
func getAPIKey() -> String {
    if let key = keychain.getAPIKey(for: provider) { return key }
    if let legacy = UserDefaults.standard.string(forKey: "APIKey") { return legacy }  // INSECURE!
    throw error
}

// ✅ Good: Local build still uses Keychain, just without syncable items
keychain.save(apiKey, forKey: keyIdentifier, syncable: false)
```

**CustomCloudModel API key rule (critical):**

- Keep exactly **one** `apiKey` computed property on `CustomCloudModel`.
- Resolve keys through `APIKeyManager` for custom model IDs.
- Do not introduce competing keychain key formats or duplicate computed properties.

```swift
// ✅ Good: Single source of truth with optional fallback for legacy key naming
var apiKey: String {
    if let key = APIKeyManager.shared.getCustomModelAPIKey(forModelId: id), !key.isEmpty {
        return key
    }
    return KeychainManager.shared.getAPIKey(for: "custom_model_\(id.uuidString)") ?? ""
}

// ⛔ Bad: Multiple apiKey properties / duplicated logic in same type
var apiKey: String { ... }
var apiKey: String { ... }  // Invalid redeclaration + inconsistent behavior
```

### 2. Network Security

**HTTPS only, ephemeral sessions:**

```swift
// ✅ Good: Secure ephemeral session
let session = SecureURLSession.makeEphemeral()

// Configuration:
configuration.urlCache = nil                 // No disk cache
configuration.httpCookieStorage = nil        // No cookies
configuration.httpShouldSetCookies = false   // Block tracking
```

### 2a. Large Audio Uploads

> **Context:** The 2026-03-07 code review found cloud transcription providers reading entire recordings into memory and using `URLSession.shared` even though the codebase already had secure ephemeral sessions.

**Rule: Stream uploads for recordings whenever the API allows it.**

- ✅ Use `SecureURLSession.makeEphemeral()`
- ✅ Prefer `session.upload(for:request, fromFile:)` for raw file uploads
- ✅ For multipart uploads, stream to a temporary body file, then upload that file
- ⛔ Never use `URLSession.shared` for credentialed uploads
- ⛔ Never use `Data(contentsOf:)` for large audio uploads when `fromFile:` or a streamed body is possible

```swift
// ✅ Good: Raw upload from file
let (data, response) = try await session.upload(for: request, fromFile: audioURL)

// ✅ Good: Multipart upload via streamed temporary body file
let (bodyURL, contentType) = try makeMultipartBodyFile(audioURL: audioURL, fields: fields)
defer { try? FileManager.default.removeItem(at: bodyURL) }
request.setValue(contentType, forHTTPHeaderField: "Content-Type")
let (data, response) = try await session.upload(for: request, fromFile: bodyURL)

// ⛔ Bad: Full recording loaded into RAM
let audioData = try Data(contentsOf: audioURL)
let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)
```

### 3. URL Validation for Custom Providers

> **Context:** The 2025-12-03 code review found custom provider URLs were not validated for HTTPS, meaning credentials could be sent over unencrypted connections.

**Rule: Validate URL scheme for ALL user-provided URLs that will carry credentials.**

```swift
// ✅ Good: Validate URL scheme before use
func validateProviderURL(_ urlString: String) throws -> URL {
    guard let url = URL(string: urlString) else {
        throw ValidationError.invalidURL("Cannot parse URL")
    }
    
    // CRITICAL: Enforce HTTPS for any URL carrying credentials
    guard url.scheme?.lowercased() == "https" else {
        throw ValidationError.insecureURL("HTTPS required for API endpoints")
    }
    
    // Validate host exists
    guard url.host != nil, !url.host!.isEmpty else {
        throw ValidationError.invalidURL("Missing host")
    }
    
    return url
}

// ✅ Good: Use in custom model configuration
class CustomModelManager {
    func addCustomModel(name: String, urlString: String, apiKey: String) throws {
        let validatedURL = try validateProviderURL(urlString)
        // Now safe to use with API key
        try saveModel(name: name, url: validatedURL, apiKey: apiKey)
    }
}

// ⛔ Bad: Using URL without validation
func setCustomEndpoint(_ urlString: String) {
    self.endpoint = URL(string: urlString)  // Could be http://!
}
```

### 4. Logging

**Never log sensitive data:**

```swift
// ✅ Good: Debug logging only
#if DEBUG
print("Failed to save API key: \(error)")
#endif

// ⛔ NEVER: Production logging of secrets
print("API Key: \(apiKey)")  // SECURITY VIOLATION!
```

### 5. Input Validation

**Validate all user input:**

```swift
// ✅ Good: Validation before use
guard text.count <= 5000 else {
    throw TTSError.textTooLong(5000)
}

guard let url = URL(string: urlString),
      url.scheme == "https" else {
    throw ValidationError.invalidURL
}

// Provider-specific validation
guard KeychainManager.isValidAPIKey(key, for: "OpenAI") else {
    throw ValidationError.invalidKeyFormat
}
```

### 6. URL Domain Matching

> **Context:** The 2025-12-05 code review found that simple `contains()` string matching for URL domains causes false positives (e.g., "google.com" matching "notgoogle.com").

**Rule: Use precise domain matching, not substring matching.**

```swift
// ⛔ WRONG: Simple contains() causes false positives
func matchesURL(_ url: String, pattern: String) -> Bool {
    return url.contains(pattern)  // "notgoogle.com" matches "google.com"!
}

// ✅ CORRECT: Precise domain matching
func matchesURL(_ url: String, pattern: String) -> Bool {
    let cleanedURL = cleanURL(url)
    let configURL = cleanURL(pattern)
    
    // Exact match or proper subdomain/path matching
    return cleanedURL == configURL ||
           cleanedURL.hasPrefix(configURL + "/") ||
           cleanedURL.hasSuffix("." + configURL) ||
           cleanedURL.contains("." + configURL + "/")
}

func cleanURL(_ url: String) -> String {
    return url.lowercased()
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "www.", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```

**Why This Matters:** Incorrect URL matching in Power Mode could apply wrong settings or prompts based on unintended URL matches.

### 6. Temporary Files

**Clean up temporary files:**

```swift
// ✅ Good: Cleanup in defer
let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("wav")

defer {
    try? FileManager.default.removeItem(at: tempURL)
}

// Use the file...
```

### Security Checklist

Before committing code with credentials or network calls:

- [ ] API keys stored in Keychain (not UserDefaults)
- [ ] Local/unsigned builds do not downgrade secrets to plaintext storage
- [ ] HTTPS-only URLs (no `http://`)
- [ ] Custom/user-provided URLs validated for HTTPS scheme
- [ ] No sensitive data in logs
- [ ] Input validation on all user data
- [ ] Temporary files cleaned up
- [ ] Error messages don't leak secrets
- [ ] Ephemeral URLSessions for API calls
- [ ] Recording uploads use `upload(fromFile:)` or streamed multipart bodies when possible

**See `docs/reviews/TTS_SECURITY_AUDIT.md` for comprehensive security analysis.**

---

## Common Patterns

### 1. Service Protocol Pattern

VoiceInk uses protocol-oriented design for services:

```swift
// Protocol defines interface
@MainActor
protocol TTSProvider {
    var name: String { get }
    var availableVoices: [Voice] { get }
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data
}

// Implementation
@MainActor
class ElevenLabsTTSService: TTSProvider {
    var name: String { "ElevenLabs" }
    
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        // Implementation
    }
}
```

**Benefits:**
- Easy to add new providers
- Testable with mock implementations
- Dependency injection friendly

### 2. ViewModel Pattern

**All views use view models:**

```swift
@MainActor
class TTSViewModel: ObservableObject {
    // Published properties for UI binding
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    
    // Private dependencies
    private let elevenLabs: ElevenLabsTTSService
    private let audioPlayer: AudioPlayerService
    
    // Public methods for user actions
    func generateSpeech() async {
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            let audio = try await elevenLabs.synthesizeSpeech(...)
            await audioPlayer.play(audio)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### 3. Extension Pattern

**Organize feature code in extensions:**

```swift
// WhisperState+UI.swift
extension WhisperState {
    var formattedTranscription: String {
        // UI formatting logic
    }
}

// WhisperState+ModelManagement.swift
extension WhisperState {
    func downloadModel(_ model: WhisperModel) async throws {
        // Model download logic
    }
}
```

### 4. Combine Publishers

**Use Combine for reactive updates:**

```swift
@MainActor
class AudioDeviceManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // React to device changes
        NotificationCenter.default
            .publisher(for: .AVCaptureDeviceWasConnected)
            .sink { [weak self] _ in
                self?.refreshDevices()
            }
            .store(in: &cancellables)
    }
}
```

### 5. Provider Capability Registry (avoid `switch` statements)

VoiceInk uses a registry-based capability system for model providers so that adding a new provider does **not** require touching multiple `switch provider` call sites.

See [`ModelCapabilityRegistry`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:28) and the [`ProviderCapabilities`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:7) protocol.

**Why:** This follows the Open/Closed Principle: provider-specific behavior lives in a single capability type, not scattered conditionals.

**How to add a new provider capability:**

1. Create a new capability type that conforms to [`ProviderCapabilities`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:7).
   - Implement `checkAvailability(model:whisperState:)` to decide whether the model is usable.
   - Implement `getAPIKeyName()` if the provider requires a Keychain API key.
   - Implement `getAIServiceProvider()` if the provider maps to an `AIProvider`.
2. Register it in [`ModelCapabilityRegistry.registerAllCapabilities()`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:80).
3. Use the registry from call sites instead of adding new `switch` cases.
   - Example: [`ModelCapabilityRegistry.isModelAvailable(_:whisperState:)`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:58)

### 6. Notification Name Pattern

Use typed notifications from `VoiceInk/Notifications/AppNotifications.swift` for every post/observe path.

```swift
// ✅ Good: Typed notification names
NotificationCenter.default.post(name: .audioDeviceChanged, object: nil)
NotificationCenter.default.addObserver(forName: .toggleMiniRecorder, object: nil, queue: .main) { _ in
    // Handle event
}

// ⛔ Bad: String-literal names scattered across files
NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
```

**Why:** String literals drift during refactors and silently break observers. Keep all names centralized.

### 7. Dictionary Data Source Pattern

`VocabularyWord` (SwiftData) is the source of truth for vocabulary UI and editing.

- Use `@Query var vocabularyWords: [VocabularyWord]` in SwiftUI vocabulary screens.
- Keep `AppSettings.Dictionary.customVocabularyItemsData` as a serialized mirror for services that read settings data.
- When serializing vocabulary to settings, use a stable codable payload type (`VocabularyWordData`).
- Do not reintroduce legacy `DictionaryItem` as a primary model.

---

## AI Context System

The AI enhancement engine (v2) uses a structured pipeline to gather "Maximum Context" from the user's environment. This context is injected into LLM prompts to enable intelligent, situation-aware transcription.

### Architecture

1.  **AIContext**: A comprehensive struct (`VoiceInk/Models/AIContext.swift`) holding all context data.
2.  **AIContextBuilder**: A service (`VoiceInk/Services/AIEnhancement/AIContextBuilder.swift`) that aggregates data from multiple specialized services.
3.  **AIContextRenderer**: A utility (`VoiceInk/Services/AIEnhancement/AIContextRenderer.swift`) that formats the `AIContext` into XML tags for the prompt.

### Context Sources & Services

| Service | Context Type | XML Tag | Description |
|---------|--------------|---------|-------------|
| `SelectedFileService` | Finder Selection | `<SELECTED_FILES_CONTEXT>` | File names, paths, sizes of selected files |
| `FocusedElementService` | Input Field | `<INPUT_FIELD_CONTEXT>` | Input role, placeholder, surrounding text |
| `CalendarService` | Schedule | `<CALENDAR_CONTEXT>` | Upcoming events (Title, Time) |
| `BrowserContentService` | Web Content | `<BROWSER_CONTENT_CONTEXT>` | Text content of active web page |
| `ActiveWindowService` | Application | `<APPLICATION_CONTEXT>` | Active app name, bundle ID, URL |
| `CustomVocabularyService` | Vocabulary | `<CUSTOM_VOCABULARY>` | User-defined terms |
| *Settings* | User Bio | `<USER_CONTEXT>` | User persona and style preferences |

### Adding New Context

1.  **Define Model**: Add fields to `AIContext` struct.
2.  **Create Service**: Implement a service to fetch the data (e.g. `MyNewService.swift`).
3.  **Update Builder**: Inject service into `AIContextBuilder` and capture data in `captureImmediateContext()` or `buildContext()`.
4.  **Update Renderer**: Add rendering logic in `AIContextRenderer` to output new XML tag.
5.  **Update Prompts**: Document the new tag usage in `AIPrompts.swift`.
6.  **Update Settings**: Add toggle in `ContextSettingsView`.

### Privacy Considerations

*   **Opt-In**: High-privacy sources like Calendar and Browser Content must be opt-in via `AIContextSettings`.
*   **Token Limits**: `TokenBudgetManager` truncates context to fit LLM limits.
*   **Local Processing**: All context gathering happens locally. Data is only sent to the AI provider during the enhancement request.

---

## Testing & Quality

### Testing Strategy

1.  **Automated First**: Run `./run_tests.sh` before every commit.
2.  **Unit Tests**: Required for all business logic (Services, ViewModels).
3.  **Manual Verification**: Use only for UI interactions that XCTest cannot cover.

### SwiftUI Preview Guidelines

**Never use force-try (`try!`) in SwiftUI previews. Use safe fallback patterns.**

```swift
// ✅ Good: Safe preview with fallback
#Preview {
    let container = try? ModelContainer(for: Transcription.self)
    let context = container.map { ModelContext($0) }
    return MyView()
        .environmentObject(ViewModel(context: context ?? fallbackContext))
}

// ⛔ Bad: Force try crashes preview canvas on failure
#Preview {
    MyView()
        .environmentObject(ViewModel(context: try! ModelContainer(...)))
}
```

### Pre-Commit Checklist

Before committing changes:

**Code Quality:**
- [ ] Code compiles without warnings
- [ ] Tests pass (run `./run_tests.sh`)
- [ ] No duplicate untracked source files (e.g., `* 2.swift`, `* 3.swift`) that cause redeclarations
- [ ] No force-unwraps (`!`) in production code
- [ ] No `.data(using: .utf8)!` force unwraps (use `Data(string.utf8)`)
- [ ] No `try!` in SwiftUI previews
- [ ] All new code follows Swift style guide
- [ ] Files under 500 lines (refactor if larger)

**Concurrency & Memory:**
- [ ] All `ObservableObject` classes have `@MainActor`
- [ ] All stored Tasks use `[weak self]`
- [ ] All Task properties cancelled in `deinit`
- [ ] Memory leaks checked (use `[weak self]` in closures)
- [ ] Timers and observers cleaned up in `deinit`

**Security:**
- [ ] No secrets or API keys in code or tests
- [ ] No UserDefaults usage for API keys or secrets
- [ ] Custom URLs validated for HTTPS scheme
- [ ] Security guidelines followed (see above)

**Error Handling:**
- [ ] Error handling for all async operations
- [ ] No silent `try?` without logging or justification
- [ ] User-facing errors are localized

**Logging & Localization:**
- [ ] All `print()` statements wrapped in `#if DEBUG`
- [ ] No hardcoded user-facing strings (use `Localization`)

**Documentation & Process:**
- [ ] Update `CHANGELOG.md` for user-visible behavior changes, upstream syncs, and build workflow updates
- [ ] Update `AGENTS.md` when introducing or changing coding standards, workflow rules, or required tooling conventions
- [ ] After any successful local Debug build verification, run `bash ./reset_permissions.sh` to reset TCC permissions and onboarding for the next manual test pass

**Assets:**
- [ ] Audio files verified with `file` command (WAV/MP3 format matches extension)

### Build & Run

```bash
# Open in Xcode
open VoiceInk.xcodeproj

# Or build from command line
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug build

# Debug build WITHOUT code signing (for testing)
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Debug build with pinned destination (avoids multiple matching destinations warning)
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug build \
    -destination 'platform=macOS,arch=arm64,name=My Mac' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Build Location Rule

Avoid running `xcodebuild` release packaging flows from iCloud-synced or Desktop-backed working copies.

**Why:**
- macOS file coordination can cause `xcodebuild` to stall before compilation begins, often inside `NSFileCoordinator`
- This was reproduced from a Desktop-backed checkout during the `v1.61-community` release workflow

**Rule:**
- Prefer a normal local clone in a non-synced path such as `~/Developer/VoiceInk`
- If the current checkout lives under Desktop/iCloud/Dropbox/OneDrive, stage the repo into a temporary local path before doing release builds
- The repository automation already handles this for release artifacts; do not reintroduce direct in-place release packaging from synced folders

### Release Automation

Use the repository scripts instead of hand-building release artifacts or hand-assembling release notes.

```bash
# Build unsigned DMG artifact in a temporary non-synced staging workspace
make release-artifact

# Generate release notes from CHANGELOG.md + .github/RELEASE_TEMPLATE.md
./scripts/generate-release-notes.sh

# Build artifact, generate notes, push branch, tag, and publish GitHub release
./scripts/publish-github-release.sh
```

**Release rules:**
- `scripts/build-release-artifact.sh` is the source of truth for unsigned GitHub DMG packaging
- `VoiceInkRelease` is the dedicated shared scheme for scripted public/community release builds; do not swap release automation back to the everyday `VoiceInk` scheme unless the release policy changes
- The unsigned GitHub/community release strategy is a project constraint, not a temporary preference
- Do not switch the public release flow to Apple-signed/notarized distribution, require Apple Developer enrollment, or treat paid signing as the default solution unless the user explicitly changes that policy
- Unsigned GitHub DMGs must be built from Xcode `Release`
- Unsigned GitHub DMGs must preserve the size-focused release contract:
  - `ENABLE_CODE_COVERAGE=NO`
  - `CLANG_COVERAGE_MAPPING=NO`
  - `DEPLOYMENT_POSTPROCESSING=YES`
  - `STRIP_INSTALLED_PRODUCT=YES`
  - `COPY_PHASE_STRIP=YES`
  - `DEAD_CODE_STRIPPING=YES`
  - `LLVM_LTO=YES_THIN`
  - `STRIPFLAGS=-x`
  - `OTHER_SWIFT_FLAGS='$(inherited) -cross-module-optimization'`
  - `SWIFT_OPTIMIZATION_LEVEL=-Osize`
- Unsigned GitHub DMGs should keep the release binary free of `__llvm_prf*` and `__LLVM_COV` sections; if those sections reappear, treat it as a release-size regression
- Unsigned GitHub DMGs may prune bundled ESpeakNG dictionary data down to the English-only Pocket TTS subset, because the shipped Pocket voices are English-only in the current product
- Unsigned GitHub DMGs must use scripted symbol stripping, `UDBZ` DMG packaging, and arm64 thinning for universal embedded binaries
- Do not hand-assemble or publish a `Debug` app, an unstripped app, or a universal unsigned DMG unless the release policy is explicitly changed first
- `scripts/generate-release-notes.sh` is the source of truth for release note composition
- `scripts/publish-github-release.sh` requires a clean git worktree and authenticated `gh`
- Community releases publish to `tmm22/VoiceInk` by default, target branch `custom-main-v2`, and use tags in the form `vX.YY-community`
- Keep user-visible release changes in the latest top entry of `CHANGELOG.md`; the automation pulls from that entry
- Keep Gatekeeper, Apple Silicon-only artifact notes, and unsigned-build instructions in `.github/RELEASE_TEMPLATE.md`; the automation merges that text into the GitHub release body
- If release packaging policy changes, update `AGENTS.md`, `docs/development/RELEASING.md`, `docs/development/BUILDING.md`, `.github/RELEASE_TEMPLATE.md`, and the release scripts in the same change

### Post-Debug-Build Step

After every successful local `Debug` build completed by an AI agent, immediately run:

```bash
bash ./reset_permissions.sh
```

This resets TCC permissions and the onboarding flag for bundle ID `com.tmm22.VoiceLinkCommunity`, so the next launch replays the full permission flow. Use this after successful Debug build verification only; do not apply it to Release/archive/distribution workflows.

The built app will be located at:
```
~/Library/Developer/Xcode/DerivedData/VoiceInk-*/Build/Products/Debug/VoiceLink Community.app
```

**See `docs/development/BUILDING.md` for detailed build instructions.**

### Workspace Hygiene (Before Building)

If a working tree contains duplicated untracked source files (for example `SomeFile 2.swift`), Xcode may emit ambiguous type/redeclaration errors.

**Quick check:**

```bash
git status --short | grep -E "^\?\?.* [0-9]+\.swift$"
```

**Rule:**
- Quarantine or remove duplicate **untracked** files before build/test.
- Never delete or rewrite tracked files as part of cleanup.

---

## Working with Features

### Adding a New TTS Provider

1. **Create Service Class**

```swift
@MainActor
class NewProviderService: TTSProvider {
    var name: String { "New Provider" }
    var defaultVoice: Voice { /* ... */ }
    var availableVoices: [Voice] { /* ... */ }
    
    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        // Implementation
    }
    
    func hasValidAPIKey() -> Bool {
        // Check keychain
    }
}
```

**Authorization headers (required):**
- TTS providers must use the centralized authorization helper [`AuthorizationService`](VoiceInk/TTS/Utilities/AuthorizationService.swift:5).
- Do **not** add per-provider `authorizationHeader()` helpers (avoid duplicated header logic and inconsistent managed-credential fallback).
- Request headers via [`AuthorizationService.authorizationHeader(for:headerType:)`](VoiceInk/TTS/Utilities/AuthorizationService.swift:22) using the appropriate [`HeaderType`](VoiceInk/TTS/Utilities/AuthorizationService.swift:69) (see convenience cases in [`HeaderType` extension](VoiceInk/TTS/Utilities/AuthorizationService.swift:90)).

2. **Update Provider Enum**

```swift
// TTSProvider.swift
enum ProviderType: String {
    case elevenLabs = "ElevenLabs"
    case openAI = "OpenAI"
    case newProvider = "NewProvider"  // Add here
}
```

3. **Register in ViewModel**

```swift
// TTSViewModel.swift
init() {
    self.newProvider = NewProviderService()
}

private func getProvider(for type: TTSProviderType) -> TTSProvider {
    switch type {
    case .newProvider:
        return newProvider
    // ...
    }
}
```

4. **Add UI Integration**

```swift
// TTSSettingsView.swift
GroupBox {
    VStack {
        Text("New Provider")
        SecureField("API Key", text: $newProviderKey)
    }
}
```

### Pocket TTS Voice Lifecycle (Hide / Restore)

When working with Pocket voices in Tight Ass Mode, use this pattern so users can remove voices from selection without breaking defaults:

1. **Voice ID conventions**
- Pocket voices should use the `pocket-tts:<voice-id>` identifier format.
- Keep Pocket voice identity checks centralized (for example, `isPocketVoiceID(_:)`) to avoid prefix drift.

2. **Persist hidden state in settings**
- Store hidden Pocket voice IDs in `AppSettings` as `[String]` (key: `hiddenPocketVoiceIDs`).
- Expose a typed accessor in `AppSettings+Voice.swift` instead of reading raw `UserDefaults` in view models.

3. **Filter in provider refresh path**
- After loading provider voices, filter through a single helper (for example, `visibleVoices(from:providerType:)`) so all UI surfaces stay consistent.
- Never mutate provider voice lists globally; apply filtering at view-model state level.

4. **Hide behavior requirements**
- When hiding the currently previewing voice, stop preview first.
- Persist hidden IDs immediately after mutation.
- Attempt best-effort cache cleanup for Pocket embedding files at:
  - `~/.cache/fluidaudio/Models/kokoro/voices/<voice-id>.json`
- Cache deletion must not fail the user flow; log and continue.

5. **Restore behavior requirements**
- Support restoring one voice and restoring all hidden voices.
- Ensure restored voices reappear in all selection menus after provider refresh.

6. **Required regression tests**
- Add service tests for Pocket voice helper APIs (voice IDs/name mapping/detection).
- Add view-model tests for hide/restore filtering and persistence across new VM instances.
- Test setup/teardown should preserve and restore `AppSettings.TTS.hiddenPocketVoiceIDs` to avoid cross-test pollution.

### Adding a Cloud Transcription Provider

1. **Create Service**

```swift
// Services/CloudTranscription/NewProviderTranscriptionService.swift
class NewProviderTranscriptionService: CloudTranscriptionService {
    func transcribe(audioData: Data, languageHint: String?) async throws -> TranscriptionResult {
        // Implementation
    }
}
```

2. **Register Provider**

```swift
// TranscriptionService.swift
enum TranscriptionProvider {
    case newProvider
}
```

3. **Update Settings UI**

### Adding a PowerMode Configuration

PowerMode detects the active app/URL and applies custom transcription settings:

1. **Create Configuration**

```swift
struct PowerModeConfig: Codable {
    let id: UUID
    let appIdentifier: String  // Bundle ID or URL pattern
    let prompt: String         // AI system prompt
    let autoEnhance: Bool
    let aiModel: String?
}
```

2. **Add Detection Logic**

```swift
// PowerModeSessionManager.swift
func detectActiveContext() -> PowerModeConfig? {
    if let url = BrowserURLService.shared.getCurrentURL() {
        return matchURLPattern(url)
    }
    if let app = ActiveWindowService.shared.frontmostApp {
        return matchApp(app)
    }
    return nil
}
```

---

## Troubleshooting

### Common Issues

#### 1. Audio Not Recording

**Symptoms:** Microphone doesn't capture audio  
**Causes:**
- Missing microphone permission
- Wrong audio device selected
- Audio engine not started

**Solution:**
```swift
// Check permissions
let status = AVCaptureDevice.authorizationStatus(for: .audio)
guard status == .authorized else {
    // Request permission
    return
}

// Verify device selection
let device = AudioDeviceManager.shared.selectedDevice
print("Selected device: \(device.name)")
```

#### 2. Whisper Model Not Loading

**Symptoms:** Transcription fails with model error  
**Causes:**
- Model not downloaded
- Corrupted model file
- Insufficient memory

**Solution:**
```swift
// Verify model file exists
let modelURL = WhisperState.modelDirectory.appendingPathComponent("ggml-base.bin")
guard FileManager.default.fileExists(atPath: modelURL.path) else {
    // Re-download model
    return
}
```

#### 3. TTS Generation Fails

**Symptoms:** Speech synthesis returns error  
**Causes:**
- Invalid API key
- Network issues
- Text exceeds provider limit

**Solution:**
```swift
// Validate before calling API
guard text.count <= provider.characterLimit else {
    throw TTSError.textTooLong(provider.characterLimit)
}

guard provider.hasValidAPIKey() else {
    throw TTSError.invalidAPIKey
}
```

#### 4. Memory Leaks

**Symptoms:** Memory usage grows over time  
**Causes:**
- Strong reference cycles in closures
- Observers not removed
- Combine subscriptions not cancelled
- Tasks not cancelled in deinit

**Solution:**
```swift
// Use [weak self] in ALL closures
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.updateUI()
}

// Store cancellables
private var cancellables = Set<AnyCancellable>()

publisher.sink { [weak self] value in
    self?.handle(value)
}
.store(in: &cancellables)

// Cancel tasks in deinit
deinit {
    durationUpdateTask?.cancel()
    monitorTask?.cancel()
}
```

#### 5. Build/Test Fails with `sandbox-exec: sandbox_apply`

**Symptoms:** `xcodebuild build` / `xcodebuild test` fails during SwiftPM package resolution with sandbox errors.  
**Causes:**
- Restricted execution environment blocking SwiftPM sandboxing.
- Package manifest resolution attempting to write to restricted cache locations.

**Solution:**
1. Run full build/tests in normal local Xcode environment (preferred).
2. Use parser validation (`swiftc -frontend -parse`) only as a temporary syntax-level fallback.
3. Treat parser-only success as insufficient for release; always perform at least one full `xcodebuild` pass before merge.

#### 6. `xcodebuild` Hangs Before Compilation Starts

**Symptoms:** `xcodebuild` appears to hang indefinitely with no meaningful compiler progress, especially during local release packaging from a Desktop-backed checkout.  
**Causes:**
- macOS file coordination on synced folders (Desktop/iCloud Drive and similar providers)
- Repository path participating in file-provider coordination before build output is created

**Solution:**
1. Move or clone the repository into a normal non-synced directory such as `~/Developer/VoiceInk`.
2. For release builds, use `./scripts/build-release-artifact.sh` or `make release-artifact`; these stage the repo into a temporary local path automatically.
3. If publishing, use `./scripts/publish-github-release.sh` from a clean checkout instead of manually building and uploading assets.
4. Do not trust stale `DerivedData` app bundles as a substitute for a fresh release build.

### Debug Logging

Enable debug output:

```swift
#if DEBUG
print("🎙️ Recording started at \(Date())")
print("📊 Audio format: \(format)")
print("🔊 Sample rate: \(sampleRate)")
#endif
```

---

## Contributing Workflow

### Before Starting Work

1. **Check for Existing Issues** - Search GitHub issues
2. **Open a Discussion** - Propose major changes first
3. **Read Contributing Guidelines** - See `CONTRIBUTING.md`
4. **Check Code of Conduct** - See `CODE_OF_CONDUCT.md`

### Development Workflow (Graphite)

This project uses **Graphite** for branch management and PR creation. AI agents MUST use Graphite CLI (`gt`) commands instead of standard `git`/`gh` commands for branching and PR workflows.

**Trunk Branches:**
- `custom-main-v2` - Primary working branch for this fork (base new features here)
- `main` - Tracks upstream repository (for syncing upstream changes)

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/VoiceInk.git
   cd VoiceInk
   gt init --trunk custom-main-v2
   gt trunk --add main  # Add upstream tracking
   ```

2. **Create Feature Branch**
   ```bash
   gt create feature/your-feature-name
   ```

3. **Make Changes**
   - Follow coding standards above
   - Test thoroughly
   - Document new features

4. **Commit Changes**
   ```bash
   gt commit -m "Add feature: description

   - Detail 1
   - Detail 2

   Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"
   ```

5. **Push and Create PR (Graphite)**
   
   This project uses [Graphite](https://graphite.dev) for PR management. Always use Graphite CLI (`gt`) instead of `gh`:
   
   ```bash
   # Track your branch with Graphite
   gt track
   
   # Submit PR with AI-generated description (recommended)
   gt submit --stack --publish --ai
   
   # Or submit interactively to write your own description
   gt submit --stack --publish
   ```
   
   **Important:** Always use `--ai` flag or interactive mode when submitting PRs. Never use `--no-interactive` without `--ai`, as this causes GitHub's default PR template to override your description.
   
   **Fallback (GitHub CLI):** Only if Graphite is unavailable:
   ```bash
   git push origin feature/your-feature-name
   gh pr create --title "type: description" --body "Detailed description..."
   ```

### Stacked PRs (When to Use)

Use stacked PRs when:
- **Large features**: Break into logical, reviewable chunks (e.g., "add model" → "add service" → "add UI")
- **Dependent changes**: When change B depends on change A that isn't merged yet
- **Incremental refactoring**: Each refactor step should be reviewed independently

**Stacking Workflow:**
```bash
# Create first branch in stack
gt create step-1-add-model
# Make changes, commit
gt commit -m "feat: Add new data model"

# Create second branch stacked on first
gt create step-2-add-service
# Make changes, commit
gt commit -m "feat: Add service layer"

# Create third branch stacked on second
gt create step-3-add-ui
# Make changes, commit
gt commit -m "feat: Add UI components"

# Submit entire stack as linked PRs (always use --ai)
gt submit --stack --ai
```

**Managing Stacks:**
```bash
gt log              # View your stack
gt sync             # Sync with remote and update stack
gt restack          # Rebase stack after changes to earlier PRs
```

### Commit Message Format

```
<type>: <short summary>

<detailed description>

<optional co-author>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**

```
feat: Add Google Cloud TTS provider

- Implement GoogleTTSService with Neural2 voices
- Add provider-specific style controls
- Include API key validation

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>
```

```
fix: Resolve audio device switching crash

The app crashed when switching audio devices during recording.
Added proper cleanup of audio engine before device change.

Fixes #123
```

### Pull Request Guidelines

**PR Title:** Clear and descriptive  
**PR Description:** Include:
- What changed
- Why it changed
- How to test
- Screenshots (if UI changes)
- Breaking changes (if any)

**Example PR Description:**

```markdown
## Overview
Adds support for Google Cloud Text-to-Speech with Neural2 voices.

## Changes
- New `GoogleTTSService` class implementing `TTSProvider`
- Voice selection UI with 20+ Google voices
- API key management in Settings
- Cost estimation for Google TTS

## Testing
1. Add Google Cloud API key in Settings > Text-to-Speech
2. Select a Google voice from dropdown
3. Enter text and generate speech
4. Verify audio playback works

## Screenshots
[Include screenshots]

## Breaking Changes
None - purely additive feature
```

---

## Additional Resources

### Documentation

- **Build Guide**: `docs/development/BUILDING.md` - Compilation instructions
- **Contributing**: `CONTRIBUTING.md` - How to contribute
- **Security Audit**: `docs/reviews/TTS_SECURITY_AUDIT.md` - Security analysis
- **Code of Conduct**: `CODE_OF_CONDUCT.md` - Community standards

### External Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [AVFoundation Guide](https://developer.apple.com/av-foundation/)

### Project Links

- **Website**: [tryvoiceink.com](https://tryvoiceink.com)
- **Community GitHub**: [tmm22/VoiceInk](https://github.com/tmm22/VoiceInk)
- **Upstream GitHub**: [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)
- **YouTube**: [@tryvoiceink](https://www.youtube.com/@tryvoiceink)

---

## Quick Reference

### Key Files

| File | Purpose |
|------|---------|
| `VoiceInk.swift` | App entry point |
| `AppDelegate.swift` | App lifecycle management |
| `WhisperState.swift` | Main transcription logic |
| `TTSViewModel.swift` | TTS workspace state |
| `PowerModeSessionManager.swift` | Context detection |
| `AIEnhancementService.swift` | AI text processing |
| `MetricsManager.swift` | MetricKit production performance monitoring |

### Graphite Commands (AI Agents Must Use)

| Task | Graphite Command | Notes |
|------|------------------|-------|
| Create new branch | `gt create branch-name` | Use instead of `git checkout -b` |
| Commit changes | `gt commit -m "message"` | Auto-stages all changes |
| Submit PR | `gt submit --ai` | **Always use `--ai`** for auto-generated descriptions |
| Submit entire stack | `gt submit --stack --ai` | **Always use `--ai`** for stacked PRs |
| Sync with trunk | `gt sync` | Pulls latest and rebases |
| View current stack | `gt log` | Shows branch relationships |
| Rebase stack | `gt restack` | After editing earlier commits |
| Switch branches | `gt checkout branch-name` | Navigate stack |
| Amend last commit | `gt modify --amend` | Edit previous commit |

> **CRITICAL:** Always include `--ai` when submitting PRs. Without it, PRs are created with empty descriptions (just the template placeholders). The `--ai` flag auto-generates descriptions from commit messages.

### Important Constants

```swift
// Audio
let WHISPER_SAMPLE_RATE = 16_000.0
let DEFAULT_RECORDING_DURATION = 300.0  // 5 minutes

// Character limits
let OPENAI_TTS_LIMIT = 4_096
let ELEVENLABS_TTS_LIMIT = 5_000
let GOOGLE_TTS_LIMIT = 5_000

// File locations
let APP_SUPPORT_DIR = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("VoiceInk")
```

### Useful Snippets

**Show alert:**
```swift
errorMessage = "Something went wrong"
showingAlert = true
```

**Background task:**
```swift
Task { [weak self] in
    await self?.performLongRunningTask()
}
```

**Main thread update:**
```swift
Task { @MainActor [weak self] in
    self?.updateUI()
}
```

---

## Version History

- **v1.12** (2026-03-10) - Release Automation and Synced-Workspace Build Lessons
  - Added build-location rule to avoid release packaging from Desktop/iCloud-backed working copies
  - Documented the `xcodebuild` pre-compilation hang symptom and its `NSFileCoordinator`-style mitigation path
  - Added release automation guidance for `build-release-artifact.sh`, `generate-release-notes.sh`, and `publish-github-release.sh`
  - Documented community release defaults: repo `tmm22/VoiceInk`, branch `custom-main-v2`, and tag format `vX.YY-community`
  - Clarified that GitHub release bodies are generated from `CHANGELOG.md` plus `.github/RELEASE_TEMPLATE.md`
- **v1.11** (2026-02-07) - Recent Lessons (Build + Data Consistency)
  - Added workspace hygiene guidance for duplicate untracked source files (e.g., `* 2.swift`) that cause redeclaration build failures
  - Added dictionary source-of-truth pattern: `VocabularyWord` (SwiftData) + `VocabularyWordData` mirror for settings-backed services
  - Added notification centralization rule to use typed names from `AppNotifications.swift` (no string-literal notification names)
  - Added `CustomCloudModel` API key ownership rule to avoid duplicate `apiKey` properties and keychain drift
  - Added troubleshooting guidance for `sandbox-exec: sandbox_apply` SwiftPM/xcodebuild failures with parser-only fallback caveat
- **v1.10** (2026-01-10) - MetricKit Production Performance Monitoring
  - Added MetricsManager service for MetricKit integration
  - Extended AppLogger with metrics category
  - Added DebugMetricsView for DEBUG builds
  - Integrated performance monitoring in app lifecycle
- **v1.0** (2025-11-03) - Initial AGENTS.md created
  - Comprehensive project overview
  - Security guidelines
  - Common patterns documentation
  - Troubleshooting guide

---

## Contributing to This Guide

This guide is a living document. If you find errors, outdated information, or have suggestions:

1. Open an issue with label `documentation`
2. Submit a PR with proposed changes
3. Reference specific sections that need updates

**Maintainers:** Please keep this guide updated when:
- Architecture changes significantly
- New major features are added
- Security practices evolve
- Common issues are discovered

---

**Last Updated:** March 10, 2026
**Maintained By:** VoiceInk Community
**License:** GPL v3 (same as project)

**Recent Updates:**
- **v1.12** (2026-03-10) - Release Automation and Synced-Workspace Build Lessons
  - Added release-build guidance to avoid Desktop/iCloud-backed workspaces for `xcodebuild`
  - Added troubleshooting steps for pre-compilation `xcodebuild` hangs caused by file coordination
  - Documented automated artifact/release-note publishing via `scripts/build-release-artifact.sh`, `scripts/generate-release-notes.sh`, and `scripts/publish-github-release.sh`
  - Added community release defaults for repo, branch, and tag naming
- **v1.11** (2026-02-07) - Recent Lessons (Build + Data Consistency)
  - Added workspace hygiene guidance for duplicate untracked Swift files before building
  - Added dictionary source-of-truth guidance (`VocabularyWord` + `VocabularyWordData` mirror)
  - Added typed notification-name requirement via `AppNotifications.swift`
  - Added `CustomCloudModel` API key ownership/single-property rule
  - Added troubleshooting path for `sandbox-exec: sandbox_apply` package-resolution failures
- **v1.10** (2026-01-10) - MetricKit Production Performance Monitoring
  - Added [`MetricsManager`](VoiceInk/Services/MetricsManager.swift) for production performance monitoring via MetricKit
  - Extended [`AppLogger`](VoiceInk/Utilities/AppLogger.swift) with `.metrics` category for performance logging
  - Added optional [`DebugMetricsView`](VoiceInk/Views/Settings/DebugMetricsView.swift) for DEBUG builds to display metrics summary
  - Integrated MetricsManager registration in app lifecycle (`VoiceInk.swift`)
  - Collects: CPU time, peak memory, disk I/O, launch times, hang diagnostics
  - View metrics in Console.app with filter `category:Metrics`
- **v1.9** (2026-01-02) - Graphite Integration
  - Configured Graphite CLI for stacked PRs workflow
  - Updated **Development Workflow** section to use `gt` commands instead of `git`/`gh`
  - Added **Stacked PRs (When to Use)** section with workflow examples
  - Added **Graphite Commands** quick reference table for AI agents
  - AI agents MUST use Graphite commands for branching, commits, and PR submission
- **v1.8** (2025-12-27) - Documentation Guidance Updates
  - Documented provider capability registry guidance via [`ModelCapabilityRegistry`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:28) and [`ProviderCapabilities`](VoiceInk/Whisper/ModelCapabilityRegistry.swift:7)
  - Documented centralized TTS authorization header usage via [`AuthorizationService`](VoiceInk/TTS/Utilities/AuthorizationService.swift:5) and [`AuthorizationService.authorizationHeader(for:headerType:)`](VoiceInk/TTS/Utilities/AuthorizationService.swift:22)
  - Documented non-blocking local file I/O guidance via [`FileDataLoader.loadData(from:options:)`](VoiceInk/Services/FileDataLoader.swift:9)
  - Added build/test note about UI test bundle signing limitations when signing is disabled (see [`docs/development/BUILD_AND_TEST_GUIDE.md`](docs/development/BUILD_AND_TEST_GUIDE.md:39))
- **v1.7** (2025-12-27) - WhisperState SOLID Refactoring
  - Updated **Codebase Structure** section with new Whisper architecture
  - Documented new subdirectories: Protocols/, Providers/, Managers/, Processors/, Actors/, Coordinators/, Models/
  - Added descriptions for all new components (ModelManager, RecordingState, WhisperContextManager, etc.)
  - Architecture follows SOLID principles with protocol-based extensibility
- **v1.6** (2025-12-05) - AI Context Awareness System
  - Added **AI Context System** section documenting the new v2 architecture
  - Detailed the structured context pipeline (`AIContext`, `Builder`, `Renderer`)
  - Documented new context sources: Calendar, Browser, Files, Input Field, User Bio
  - Defined protocol for adding new context types
- **v1.5** (2025-12-05) - Build Fixes and SwiftUI Struct Guidance
  - Added **SwiftUI Structs and `[weak self]`** section explaining value type limitations
  - Added **Redundant `MainActor.run`** section with examples of what to avoid
  - Added **URL Domain Matching** section to Security Guidelines
  - Added **Debug build without code signing** command to Build & Run section
  - Updated Critical Rules to prohibit redundant `MainActor.run` in `@MainActor` classes
  - Clarified that `[weak self]` in Timer closures only applies to classes, not structs
- **v1.4** (2025-12-03) - Comprehensive Code Review Guidelines
  - Added new **Memory Management** section with Task lifecycle rules
  - Added `[weak self]` requirements for ALL stored Tasks and closures
  - Added Task cancellation requirements in `deinit`
  - Added pattern for nonisolated delegate methods creating Tasks
  - Expanded **deinit Cleanup Checklist** with comprehensive verification items
  - Added **File Size Limits** section (500 line guideline, 1000 max)
  - Added strategies for splitting large files with extensions
  - Added **Silent Failure Prevention** guidelines for `try?` usage
  - Added **URL Validation for Custom Providers** to Security Guidelines
  - Expanded **Pre-Commit Checklist** with memory, concurrency, and security items
  - Added context boxes explaining *why* each rule matters
  - Updated useful snippets to use `[weak self]` pattern
- **v1.3** (2025-11-26) - Audio File Guidelines
  - Added `Audio File Guidelines` section with format verification rules
  - Added guidance on generating WAV files with Python/scipy
  - Warning against using `afconvert` for MP3 creation (produces M4A containers)
  - Updated `Pre-Commit Checklist` to include audio format verification
- **v1.2** (2025-11-25) - Code Audit Findings
  - Added mandatory `@MainActor` requirements for all `ObservableObject` classes
  - Added `deinit` + `@MainActor` pattern guidance
  - Added `Data Encoding` section with safe UTF-8 patterns
  - Expanded `Security Guidelines` with API key migration note and anti-pattern examples
  - Added `SwiftUI Preview Guidelines` section
  - Enhanced `Pre-Commit Checklist` with 5 new critical items
  - Updated `Logging` section to require `#if DEBUG` for print statements
- **v1.1** (2025-11-23) - Enhanced Production Standards
  - Added `Production Standards` section
  - Updated `Security Guidelines` (Strict Keychain usage)
  - Updated `Coding Standards` (Localization, Logging)
  - Updated `Testing Strategy` (Automated tests via `run_tests.sh`)
- **v1.0** (2025-11-03) - Initial AGENTS.md created
