# AI Agents Guide for VoiceInk

This document provides comprehensive guidance for AI coding assistants (Claude, GPT-4, Cursor, GitHub Copilot, etc.) working with the VoiceInk codebase.

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Technologies](#architecture--technologies)
3. [Codebase Structure](#codebase-structure)
4. [Coding Standards](#coding-standards)
5. [Production Standards](#production-standards)
6. [Security Guidelines](#security-guidelines)
7. [Common Patterns](#common-patterns)
8. [Testing & Quality](#testing--quality)
8. [Working with Features](#working-with-features)
9. [Troubleshooting](#troubleshooting)
10. [Contributing Workflow](#contributing-workflow)

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
- ⛔ Never block the main thread
- ⛔ Avoid completion handlers (use async/await instead)
- ⛔ Never call `@MainActor` methods from `deinit` (use direct cleanup instead)

**ObservableObject Requirements:**

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

**deinit with @MainActor:**

```swift
@MainActor
class TimerManager: ObservableObject {
    private var timer: Timer?
    
    // ✅ Good: Direct cleanup in deinit (doesn't call isolated methods)
    deinit {
        timer?.invalidate()
    }
    
    // ⛔ Bad: Calling @MainActor method from deinit causes compiler error
    deinit {
        stopTimer()  // Error: Can't call isolated method from deinit
    }
}
```

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
├── Services/                   # Business logic
│   ├── TranscriptionService.swift
│   ├── AIEnhancementService.swift
│   ├── AudioDeviceManager.swift
│   ├── ScreenCaptureService.swift
│   ├── CloudTranscription/     # Cloud provider integrations
│   └── OllamaService.swift
├── Whisper/                    # Local Whisper integration
│   ├── WhisperState.swift
│   ├── LibWhisper.swift
│   └── WhisperState+*.swift    # Feature extensions
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

### 3. Logging

**Never log sensitive data:**

```swift
// ✅ Good: Debug logging only
#if DEBUG
print("Failed to save API key: \(error)")
#endif

// ⛔ NEVER: Production logging of secrets
print("API Key: \(apiKey)")  // SECURITY VIOLATION!
```

### 4. Input Validation

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

### 5. Temporary Files

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
- [ ] HTTPS-only URLs (no `http://`)
- [ ] No sensitive data in logs
- [ ] Input validation on all user data
- [ ] Temporary files cleaned up
- [ ] Error messages don't leak secrets
- [ ] Ephemeral URLSessions for API calls

**See `TTS_SECURITY_AUDIT.md` for comprehensive security analysis.**

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
class ElevenLabsService: TTSProvider {
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
    private let elevenLabs: ElevenLabsService
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

### 3. Error Handling

**Use typed errors:**

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

### 4. Extension Pattern

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

### 5. Combine Publishers

**Use Combine for reactive updates:**

```swift
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

---

## Testing & Quality

### Testing Strategy

1. **Automated First**: Run `./run_tests.sh` before every commit.
2. **Unit Tests**: Required for all business logic (Services, ViewModels).
3. **Manual Verification**: Use only for UI interactions that XCTest cannot cover.

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

- [ ] Code compiles without warnings
- [ ] Tests pass (run `./run_tests.sh`)
- [ ] No secrets or API keys in code or tests
- [ ] No force-unwraps (`!`) in production code
- [ ] No `.data(using: .utf8)!` force unwraps (use `Data(string.utf8)`)
- [ ] No `try!` in SwiftUI previews
- [ ] All `ObservableObject` classes have `@MainActor`
- [ ] All `print()` statements wrapped in `#if DEBUG`
- [ ] No UserDefaults usage for API keys or secrets
- [ ] All new code follows Swift style guide
- [ ] Security guidelines followed (see above)
- [ ] No hardcoded values or strings (use `Localization`)
- [ ] Error handling for all async operations
- [ ] Memory leaks checked (use `[weak self]` in closures)
- [ ] Audio files verified with `file` command (WAV/MP3 format matches extension)

### Build & Run

```bash
# Open in Xcode
open VoiceInk.xcodeproj

# Or build from command line
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug build
```

**See `BUILDING.md` for detailed build instructions.**

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

**Solution:**
```swift
// Use [weak self] in closures
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.updateUI()
}

// Store cancellables
private var cancellables = Set<AnyCancellable>()

publisher.sink { [weak self] value in
    self?.handle(value)
}
.store(in: &cancellables)
```

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

### Development Workflow

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/VoiceInk.git
   cd VoiceInk
   ```

2. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Changes**
   - Follow coding standards above
   - Test thoroughly
   - Document new features

4. **Commit Changes**
   ```bash
   git add .
   git commit -m "Add feature: description
   
   - Detail 1
   - Detail 2
   
   Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"
   ```

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   gh pr create --title "Add feature: description" --body "Detailed description..."
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

- **Build Guide**: `BUILDING.md` - Compilation instructions
- **Contributing**: `CONTRIBUTING.md` - How to contribute
- **Security Audit**: `TTS_SECURITY_AUDIT.md` - Security analysis
- **Code of Conduct**: `CODE_OF_CONDUCT.md` - Community standards

### External Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [AVFoundation Guide](https://developer.apple.com/av-foundation/)

### Project Links

- **Website**: [tryvoiceink.com](https://tryvoiceink.com)
- **GitHub**: [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)
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
Task {
    await performLongRunningTask()
}
```

**Main thread update:**
```swift
Task { @MainActor in
    self.updateUI()
}
```

---

## Version History

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

**Last Updated:** November 26, 2025  
**Maintained By:** VoiceInk Community  
**License:** GPL v3 (same as project)

**Recent Updates:**
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
