# VoiceInk Technical Design Document

> **For New Engineers** - A comprehensive guide to the VoiceInk codebase architecture and inner workings.

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Core Components](#3-core-components)
4. [Data Layer](#4-data-layer)
5. [Security Architecture](#5-security-architecture)
6. [Concurrency Model](#6-concurrency-model)
7. [Directory Structure](#7-directory-structure)
8. [Key Flows](#8-key-flows)
9. [Testing Strategy](#9-testing-strategy)
10. [Getting Started](#10-getting-started)

---

## 1. Executive Summary

VoiceInk is a **privacy-focused, native macOS application** for voice-to-text transcription with AI enhancement capabilities. It provides:

- **Local (offline) transcription** via Whisper.cpp, Parakeet, FastConformer, and Apple's native Speech Recognition
- **Cloud-based transcription** via Groq, Deepgram, ElevenLabs, Gemini, Mistral, Soniox, and custom endpoints
- **AI text enhancement** via OpenAI, Anthropic, Gemini, Mistral, Groq, Ollama, and more
- **Text-to-Speech synthesis** via ElevenLabs, OpenAI, Google Cloud TTS, and local system voices
- **Power Mode** - context-aware configurations that adapt to the active application or URL

### Tech Stack

| Component | Technology |
|-----------|------------|
| Platform | macOS 14.0+ (Sonoma) |
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Data Persistence | SwiftData |
| Audio | AVFoundation, AVAudioRecorder |
| ML/AI | Whisper.cpp, Core ML |
| Security | Keychain Services, App Sandbox |
| Concurrency | Swift Concurrency (async/await, @MainActor) |

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VoiceInk Application                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   SwiftUI    │  │  MenuBar     │  │  Recorder    │  │  Hotkey      │    │
│  │   Views      │  │  Manager     │  │  Panels      │  │  Manager     │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                 │                 │                 │            │
│         └─────────────────┴────────┬────────┴─────────────────┘            │
│                                    │                                       │
│  ┌─────────────────────────────────▼─────────────────────────────────────┐ │
│  │                  WhisperState (Central Orchestrator)                   │ │
│  │                                                                        │ │
│  │  • Recording State Machine    • Model Loading/Unloading               │ │
│  │  • Transcription Flow         • Enhancement Orchestration             │ │
│  │  • Mini/Notch Recorder UI     • Power Mode Integration                │ │
│  └────────────────────────────────┬──────────────────────────────────────┘ │
│                                   │                                        │
│  ┌────────────────────────────────┼────────────────────────────────────┐   │
│  │                         Service Layer                                │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │  Transcription  │  │ AI Enhancement  │  │  TTS Workspace  │      │   │
│  │  │   Services      │  │    Service      │  │   (TTSViewModel)│      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │  Power Mode     │  │   AI Service    │  │  Audio Device   │      │   │
│  │  │   Manager       │  │  (Multi-provider)│  │   Manager       │      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                        │
│  ┌────────────────────────────────▼────────────────────────────────────┐   │
│  │                    Data & Infrastructure Layer                       │   │
│  │                                                                      │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌─────────────────┐   │   │
│  │  │ SwiftData │  │ Keychain  │  │UserDefaults│  │  AVFoundation   │   │   │
│  │  │  (Store)  │  │ Manager   │  │ (Settings) │  │  (Audio I/O)    │   │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └─────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility |
|-------|---------------|
| **Presentation** | SwiftUI views, MenuBar, Recorder panels, Hotkey handling |
| **Orchestration** | WhisperState coordinates all recording/transcription workflows |
| **Service** | Business logic, API integrations, provider abstractions |
| **Data** | Persistence (SwiftData), secure storage (Keychain), settings (UserDefaults) |

---

## 3. Core Components

### 3.1 Application Entry Point (`VoiceInk.swift`)

The `@main` struct initializes all core services and manages the SwiftUI app lifecycle:

```swift
@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer              // SwiftData persistence
    
    @StateObject private var whisperState      // Central orchestrator
    @StateObject private var aiService         // AI provider management  
    @StateObject private var enhancementService // Text enhancement
    @StateObject private var hotkeyManager     // Keyboard shortcuts
    @StateObject private var menuBarManager    // Menu bar state
    @StateObject private var updaterViewModel  // Sparkle updates
}
```

**Initialization Order:**
1. API Key migration (legacy UserDefaults → Keychain)
2. SwiftData ModelContainer creation (with fallback strategies)
3. Service instantiation with dependency injection
4. Environment object propagation to SwiftUI views

---

### 3.2 Recording State Machine (`WhisperState`)

The **central orchestrator** managing the entire transcription workflow.

```
┌────────────────────────────────────────────────────────────────────────┐
│                      RecordingState Flow                                │
│                                                                         │
│                                                                         │
│   ┌────────┐   toggleRecord()   ┌─────────────┐                        │
│   │  IDLE  │ ─────────────────► │  RECORDING  │                        │
│   └────────┘                    └──────┬──────┘                        │
│       ▲                                │                                │
│       │                                │ toggleRecord() / stopRecording │
│       │                                ▼                                │
│       │                         ┌──────────────┐                       │
│       │                         │ TRANSCRIBING │                       │
│       │                         └──────┬───────┘                       │
│       │                                │                                │
│       │                                │ (if AI enhancement enabled)   │
│       │                                ▼                                │
│       │                         ┌──────────────┐                       │
│       │                         │  ENHANCING   │                       │
│       │                         └──────┬───────┘                       │
│       │                                │                                │
│       └────────────────────────────────┘                               │
│                            complete                                     │
│                                                                         │
│   Additional States:                                                    │
│   • BUSY - Model loading/unloading in progress                         │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

**Key Responsibilities:**

```swift
@MainActor
class WhisperState: NSObject, ObservableObject {
    // State
    @Published var recordingState: RecordingState = .idle
    @Published var isModelLoaded = false
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    
    // Core Components
    let recorder = Recorder()                    // Audio capture
    var whisperContext: WhisperContext?          // Local Whisper model
    let enhancementService: AIEnhancementService? // AI text refinement
    
    // Transcription Services (one per provider type)
    private var localTranscriptionService: LocalTranscriptionService?
    private lazy var cloudTranscriptionService = CloudTranscriptionService()
    private lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    internal lazy var parakeetTranscriptionService = ParakeetTranscriptionService()
    internal lazy var fastConformerTranscriptionService = FastConformerTranscriptionService(...)
    
    // Main workflow method
    func toggleRecord() async { ... }
}
```

---

### 3.3 Transcription Services

VoiceInk supports multiple transcription providers through a unified protocol:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  Transcription Service Architecture                      │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │              TranscriptionService (Protocol)                        │ │
│  │                                                                     │ │
│  │   func transcribe(audioURL: URL, model: TranscriptionModel)         │ │
│  │       async throws -> String                                        │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                 │                                        │
│         ┌───────────────────────┼───────────────────────┐               │
│         │                       │                       │               │
│         ▼                       ▼                       ▼               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐      │
│  │   LOCAL MODELS   │  │   CLOUD MODELS   │  │   NATIVE APPLE   │      │
│  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤      │
│  │ • Whisper.cpp    │  │ • Groq           │  │ • Apple Speech   │      │
│  │   (ggml models)  │  │ • Deepgram       │  │   Recognition    │      │
│  │ • Parakeet       │  │ • ElevenLabs     │  │   (on-device)    │      │
│  │   (NVIDIA NeMo)  │  │ • Gemini         │  └──────────────────┘      │
│  │ • FastConformer  │  │ • Mistral        │                             │
│  │   (CoreML)       │  │ • Soniox         │                             │
│  └──────────────────┘  │ • Custom API     │                             │
│                        └──────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────┘
```

**Model Provider Enum:**

```swift
enum ModelProvider: String, Codable, CaseIterable {
    case local = "Local"           // Whisper.cpp
    case parakeet = "Parakeet"     // NVIDIA NeMo Parakeet
    case fastConformer = "FastConformer"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case mistral = "Mistral"
    case gemini = "Gemini"
    case soniox = "Soniox"
    case custom = "Custom"
    case nativeApple = "Native Apple"
}
```

**TranscriptionModel Protocol:**

```swift
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }
}
```

---

### 3.4 AI Enhancement Pipeline

The AI enhancement service refines raw transcriptions using context-aware prompts:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      AI Enhancement Pipeline                             │
│                                                                          │
│  ┌────────────────┐                                                     │
│  │ Raw Transcript │                                                     │
│  └───────┬────────┘                                                     │
│          │                                                               │
│          ▼                                                               │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   AIEnhancementService                             │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │              Context Assembly                                │  │  │
│  │  │                                                              │  │  │
│  │  │  • Selected Text (from active app)                           │  │  │
│  │  │  • Clipboard Context (if enabled)                            │  │  │
│  │  │  • Screen Capture Context (OCR of active window)            │  │  │
│  │  │  • Custom Vocabulary (domain-specific terms)                 │  │  │
│  │  │  • Active Prompt Template                                    │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                            │                                       │  │
│  │                            ▼                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │                    AIService                                 │  │  │
│  │  │                                                              │  │  │
│  │  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │  │  │
│  │  │   │ OpenAI  │  │Anthropic│  │ Gemini  │  │ Mistral │       │  │  │
│  │  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘       │  │  │
│  │  │                                                              │  │  │
│  │  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │  │  │
│  │  │   │  Groq   │  │ Ollama  │  │OpenRouter│  │ Custom  │       │  │  │
│  │  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘       │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│          │                                                               │
│          ▼                                                               │
│  ┌────────────────┐                                                     │
│  │ Enhanced Text  │                                                     │
│  └────────────────┘                                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

**AIService Provider Enum:**

```swift
enum AIProvider: String, CaseIterable {
    case cerebras = "Cerebras"
    case groq = "GROQ"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case ollama = "Ollama"
    case custom = "Custom"
    
    var baseURL: String { ... }
    var defaultModel: String { ... }
    var availableModels: [String] { ... }
    var requiresAPIKey: Bool { ... }
}
```

---

### 3.5 Text-to-Speech (TTS) Architecture

The TTS Workspace provides speech synthesis with multiple providers:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TTS Workspace Architecture                            │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    TTSViewModel (@MainActor)                        │ │
│  │                                                                     │ │
│  │  Published State:                                                   │ │
│  │  • inputText, selectedProvider, selectedVoice                       │ │
│  │  • isGenerating, isPlaying, currentTime, duration                   │ │
│  │  • availableVoices, recentGenerations, batchItems                   │ │
│  │                                                                     │ │
│  │  Features:                                                          │ │
│  │  • Text input with character limits per provider                    │ │
│  │  • Long-form auto-chunking for texts > provider limit               │ │
│  │  • Batch generation (split by "---" delimiter)                      │ │
│  │  • Voice preview playback                                           │ │
│  │  • Text translation (via OpenAI)                                    │ │
│  │  • URL content import with summarization                            │ │
│  │  • Transcription recording (audio → text → TTS)                     │ │
│  │  • Cost estimation                                                  │ │
│  └───────────────────────────────────────────────────────────────────┬─┘ │
│                                                                       │   │
│      ┌──────────────┬──────────────┬──────────────┬──────────────┐   │   │
│      ▼              ▼              ▼              ▼              │   │   │
│  ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐ │   │   │
│  │ElevenLab│  │ OpenAI │   │ Google │   │ Local  │   │ Audio  │ │   │   │
│  │Service  │  │Service │   │  TTS   │   │  TTS   │   │ Player │ │   │   │
│  └────────┘   └────────┘   └────────┘   └────────┘   └────────┘ │   │   │
│                                                                  │   │   │
└──────────────────────────────────────────────────────────────────┼───────┘
                                                                   │
  ┌────────────────────────────────────────────────────────────────▼───────┐
  │                     TTSProvider Protocol                                │
  │                                                                         │
  │  var name: String { get }                                               │
  │  var defaultVoice: Voice { get }                                        │
  │  var availableVoices: [Voice] { get }                                   │
  │  var styleControls: [ProviderStyleControl] { get }                      │
  │                                                                         │
  │  func synthesizeSpeech(text: String, voice: Voice,                      │
  │                        settings: AudioSettings) async throws -> Data    │
  │  func hasValidAPIKey() -> Bool                                          │
  └─────────────────────────────────────────────────────────────────────────┘
```

**Character Limits by Provider:**

| Provider | Character Limit |
|----------|----------------|
| OpenAI | 4,096 |
| ElevenLabs | 5,000 |
| Google Cloud | 5,000 |
| Local (System) | 20,000 |

---

### 3.6 Power Mode (Context-Aware Configuration)

Power Mode automatically applies transcription/enhancement settings based on the active application or URL:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Power Mode Architecture                              │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                  ActiveWindowService (Singleton)                    │ │
│  │                                                                     │ │
│  │  • Monitors NSWorkspace.shared.frontmostApplication                 │ │
│  │  • Detects browser URLs via AppleScript (BrowserURLService)         │ │
│  │  • Triggers on each recording start                                 │ │
│  └──────────────────────────────────┬─────────────────────────────────┘ │
│                                     │                                    │
│                                     ▼                                    │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                 PowerModeManager (Singleton)                        │ │
│  │                                                                     │ │
│  │  • Stores PowerModeConfig[] in UserDefaults                         │ │
│  │  • Matches bundle identifiers → config                              │ │
│  │  • Matches URL patterns → config                                    │ │
│  │  • Returns default config if no match                               │ │
│  └──────────────────────────────────┬─────────────────────────────────┘ │
│                                     │                                    │
│                                     ▼                                    │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │             PowerModeSessionManager (Singleton)                     │ │
│  │                                                                     │ │
│  │  beginSession(config):                                              │ │
│  │    1. Snapshot current app state (ApplicationState)                 │ │
│  │    2. Apply config settings:                                        │ │
│  │       • isEnhancementEnabled                                        │ │
│  │       • selectedPrompt                                              │ │
│  │       • selectedTranscriptionModel                                  │ │
│  │       • selectedLanguage                                            │ │
│  │       • selectedAIProvider/Model                                    │ │
│  │       • useScreenCapture                                            │ │
│  │                                                                     │ │
│  │  endSession():                                                      │ │
│  │    1. Restore original ApplicationState                             │ │
│  │    2. Clear session                                                 │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  PowerModeConfig {                                                       │
│      id: UUID                                                            │
│      name: String                                                        │
│      emoji: String                                                       │
│      appConfigs: [AppConfig]?     // Bundle IDs to match                │
│      urlConfigs: [URLConfig]?     // URL patterns to match              │
│      isAIEnhancementEnabled: Bool                                        │
│      selectedPrompt: String?                                             │
│      selectedTranscriptionModelName: String?                             │
│      selectedLanguage: String?                                           │
│      selectedAIProvider: String?                                         │
│      selectedAIModel: String?                                            │
│      useScreenCapture: Bool                                              │
│      isAutoSendEnabled: Bool      // Auto-press Enter after paste       │
│      isEnabled: Bool                                                     │
│      isDefault: Bool              // Fallback config                    │
│  }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Data Layer

### 4.1 Persistence Strategy

| Data Type | Storage | Rationale |
|-----------|---------|-----------|
| **Transcriptions** | SwiftData | Structured data, queryable, soft-delete support |
| **API Keys** | Keychain | Security requirement - encrypted, sandboxed |
| **User Settings** | UserDefaults | Simple key-value preferences |
| **Model Files** | Application Support | Large binary files, managed lifecycle |
| **Audio Recordings** | Application Support | User data with configurable cleanup |
| **Power Mode Configs** | UserDefaults | JSON-encoded configuration array |

### 4.2 SwiftData Model: Transcription

```swift
@Model
final class Transcription {
    // Identity
    var id: UUID
    var timestamp: Date
    
    // Content
    var text: String                    // Raw transcription
    var enhancedText: String?           // AI-enhanced version
    var duration: TimeInterval          // Audio duration
    var audioFileURL: String?           // Path to WAV file
    
    // Metadata
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var powerModeName: String?
    var powerModeEmoji: String?
    
    // Performance Metrics
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    
    // AI Debug Info
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    
    // Status
    var transcriptionStatus: String?    // "pending", "completed", "failed"
    
    // Soft Delete
    var isDeleted: Bool = false
    var deletedAt: Date?
    
    func moveToTrash() { ... }
    func restore() { ... }
}
```

### 4.3 File System Layout

```
~/Library/Application Support/com.tmm22.VoiceLinkCommunity/
├── WhisperModels/              # Downloaded Whisper.cpp models
│   ├── ggml-base.bin
│   ├── ggml-small.bin
│   └── ...
├── FastConformer/              # FastConformer CoreML models
├── Recordings/                 # Audio recordings (WAV files)
│   ├── {uuid}.wav
│   └── ...
└── default.store               # SwiftData SQLite database
```

---

## 5. Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Security Architecture                               │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                     KeychainManager                                 │ │
│  │                                                                     │ │
│  │  Responsibilities:                                                  │ │
│  │  • Store all API keys (ElevenLabs, OpenAI, Google, Anthropic, etc.)│ │
│  │  • Provider-specific key validation patterns                        │ │
│  │  • Migration from legacy UserDefaults storage                       │ │
│  │                                                                     │ │
│  │  Methods:                                                           │ │
│  │  • saveAPIKey(_ key: String, for provider: String)                  │ │
│  │  • getAPIKey(for provider: String) -> String?                       │ │
│  │  • deleteAPIKey(for provider: String)                               │ │
│  │  • hasAPIKey(for provider: String) -> Bool                          │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                   SecureURLSession                                  │ │
│  │                                                                     │ │
│  │  static func makeEphemeral() -> URLSession {                        │ │
│  │      let config = URLSessionConfiguration.ephemeral                 │ │
│  │      config.urlCache = nil              // No disk cache            │ │
│  │      config.httpCookieStorage = nil     // No cookies               │ │
│  │      config.httpShouldSetCookies = false                            │ │
│  │      return URLSession(configuration: config)                       │ │
│  │  }                                                                  │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                   Security Rules                                    │ │
│  │                                                                     │ │
│  │  ✓ API keys stored ONLY in Keychain                                │ │
│  │  ✓ HTTPS-only for all network requests                             │ │
│  │  ✓ Ephemeral URLSession for API calls                              │ │
│  │  ✓ No sensitive data in logs (use OSLog with privacy: .private)    │ │
│  │  ✓ Temporary files cleaned up in defer blocks                      │ │
│  │                                                                     │ │
│  │  ✗ NEVER store API keys in UserDefaults                            │ │
│  │  ✗ NEVER log API keys or credentials                               │ │
│  │  ✗ NEVER use UserDefaults fallbacks for credentials                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Concurrency Model

VoiceInk uses Swift's modern concurrency with strict patterns:

### 6.1 @MainActor Requirement

**ALL `ObservableObject` classes with `@Published` properties MUST be marked `@MainActor`:**

```swift
// ✅ CORRECT
@MainActor
class WhisperState: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var isModelLoaded = false
}

// ✅ CORRECT
@MainActor
class TTSViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
}

// ❌ WRONG - Will cause data race crashes
class SomeViewModel: ObservableObject {
    @Published var data: [Item] = []  // Missing @MainActor!
}
```

### 6.2 Async/Await for I/O

```swift
// ✅ Network calls use async/await
func synthesizeSpeech(text: String, voice: Voice) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    // ...
}

// ✅ Background work uses Task
Task {
    await performLongRunningTask()
}

// ❌ NEVER block main thread
// ❌ NEVER use completion handlers (use async/await)
```

### 6.3 Community Edition I/O Standards

- Prefer `async/await` for all network and file I/O.
- Avoid blocking file reads on the main actor (use `URLSession.upload(fromFile:)` or async loaders).
- Keep `@MainActor` classes free of redundant `DispatchQueue.main.async` hops.

### 6.4 deinit Restrictions

```swift
@MainActor
class TimerManager: ObservableObject {
    private var timer: Timer?
    
    // ✅ Direct cleanup (doesn't call isolated methods)
    deinit {
        timer?.invalidate()
    }
    
    // ❌ Can't call @MainActor methods from deinit
    deinit {
        stopTimer()  // Compiler error!
    }
}
```

---

## 7. Directory Structure

```
VoiceInk/
├── VoiceInk.swift                    # @main App entry point
├── AppDelegate.swift                 # NSApplicationDelegate
├── Recorder.swift                    # AVAudioRecorder wrapper
├── HotkeyManager.swift               # Global keyboard shortcuts
├── MenuBarManager.swift              # Menu bar state
├── WindowManager.swift               # Window management
├── SoundManager.swift                # Audio feedback sounds
│
├── Models/
│   ├── Transcription.swift           # SwiftData @Model
│   ├── TranscriptionModel.swift      # Protocol + implementations
│   ├── PredefinedModels.swift        # Model catalog
│   ├── CustomPrompt.swift            # AI prompt templates
│   ├── AudioFeedbackSettings.swift   # Sound preferences
│   └── LicenseViewModel.swift        # Licensing
│
├── Services/
│   ├── TranscriptionService.swift    # Protocol definition
│   ├── LocalTranscriptionService.swift
│   ├── AudioDeviceManager.swift      # Microphone selection
│   ├── WordReplacementService.swift  # Text substitutions
│   ├── ScreenCaptureService.swift    # OCR context
│   ├── OllamaAIService.swift         # Local LLM
│   │
│   ├── AIEnhancement/
│   │   ├── AIService.swift           # Multi-provider AI client
│   │   ├── AIEnhancementService.swift
│   │   ├── AIEnhancementOutputFilter.swift
│   │   └── ReasoningConfig.swift
│   │
│   └── CloudTranscription/
│       ├── CloudTranscriptionService.swift
│       ├── GroqTranscriptionService.swift
│       ├── DeepgramTranscriptionService.swift
│       ├── ElevenLabsTranscriptionService.swift
│       ├── GeminiTranscriptionService.swift
│       ├── MistralTranscriptionService.swift
│       ├── SonioxTranscriptionService.swift
│       ├── CustomModelManager.swift
│       └── OpenAICompatibleTranscriptionService.swift
│
├── TTS/                              # Text-to-Speech Module
│   ├── Models/
│   │   ├── TTSProvider.swift         # Provider enum
│   │   ├── Voice.swift               # Voice model
│   │   └── GenerationHistoryItem.swift
│   ├── Services/
│   │   ├── ElevenLabsTTSService.swift
│   │   ├── OpenAITTSService.swift
│   │   ├── GoogleTTSService.swift
│   │   ├── LocalTTSService.swift
│   │   └── AudioPlayerService.swift
│   ├── ViewModels/
│   │   └── TTSViewModel.swift
│   ├── Views/
│   │   ├── TTSWorkspaceView.swift
│   │   ├── TTSSettingsView.swift
│   │   └── ...
│   └── Utilities/
│       ├── KeychainManager.swift
│       ├── SecureURLSession.swift
│       └── TextChunker.swift
│
├── PowerMode/
│   ├── PowerModeConfig.swift         # Configuration model
│   ├── PowerModeManager.swift        # Singleton manager
│   ├── PowerModeSessionManager.swift # Session state
│   ├── ActiveWindowService.swift     # App detection
│   ├── BrowserURLService.swift       # URL detection
│   └── PowerModeView.swift           # UI
│
├── Whisper/                          # SOLID architecture (refactored 2025-12-27)
│   ├── WhisperState.swift            # Central orchestrator (backward compatible)
│   ├── ModelManager.swift            # Provider coordination with Combine
│   ├── RecordingState.swift          # Recording state enum
│   ├── WhisperState+UI.swift
│   ├── WhisperState+ModelManagement.swift
│   ├── WhisperState+Parakeet.swift
│   ├── WhisperState+FastConformer.swift
│   ├── LibWhisper.swift              # C bindings
│   ├── WhisperPrompt.swift           # Prompt management
│   ├── WhisperTextFormatter.swift    # Output formatting
│   ├── Protocols/                    # SOLID protocol definitions
│   │   ├── ModelProviderProtocol.swift
│   │   ├── RecordingSessionProtocol.swift
│   │   ├── TranscriptionProcessorProtocol.swift
│   │   └── UIManagerProtocol.swift
│   ├── Providers/                    # Model provider implementations
│   │   ├── LocalModelProvider.swift
│   │   └── ParakeetModelProvider.swift
│   ├── Managers/                     # State and resource managers
│   │   ├── RecordingSessionManager.swift
│   │   ├── AudioBufferManager.swift
│   │   └── UIManager.swift
│   ├── Processors/                   # Transcription pipeline
│   │   ├── TranscriptionProcessor.swift
│   │   ├── AudioPreprocessor.swift
│   │   └── TranscriptionResultProcessor.swift
│   ├── Actors/                       # Thread-safe actors
│   │   └── WhisperContextManager.swift
│   ├── Coordinators/                 # Workflow coordination
│   │   └── InferenceCoordinator.swift
│   └── Models/                       # Data models
│       └── WhisperContextWrapper.swift
│
├── Views/
│   ├── ContentView.swift             # Main navigation
│   ├── MenuBarView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── AudioInputSettingsView.swift
│   │   └── ...
│   ├── Recorder/
│   │   ├── MiniRecorderView.swift
│   │   ├── NotchRecorderView.swift
│   │   └── ...
│   ├── AI Models/
│   │   ├── ModelManagementView.swift
│   │   └── ...
│   └── ...
│
├── Utilities/
│   ├── AppLogger.swift               # OSLog wrapper
│   ├── Localization.swift            # String localization
│   ├── DesignSystem.swift            # UI constants
│   └── View+VoiceInkStyle.swift      # SwiftUI modifiers
│
└── Notifications/
    ├── NotificationManager.swift
    └── AnnouncementManager.swift
```

---

## 8. Key Flows

### 8.1 Voice Recording → Transcription → Enhancement

```
┌─────────────────────────────────────────────────────────────────────────┐
│                Complete Recording Flow                                   │
│                                                                          │
│  User presses hotkey (e.g., ⌘+Shift+Space)                              │
│          │                                                               │
│          ▼                                                               │
│  ┌─────────────────┐                                                    │
│  │  HotkeyManager  │ ──► Calls whisperState.toggleRecord()              │
│  └────────┬────────┘     Shows MiniRecorder or NotchRecorder panel      │
│           │                                                              │
│           ▼                                                              │
│  ┌─────────────────┐                                                    │
│  │  WhisperState   │ ──► recordingState = .recording                    │
│  │ toggleRecord()  │ ──► Starts Recorder with selected audio device     │
│  └────────┬────────┘ ──► Applies PowerMode configuration                │
│           │          ──► Captures context (clipboard, screen)           │
│           │          ──► Preloads local model if needed                 │
│           │                                                              │
│           ▼  (User releases hotkey or clicks stop)                      │
│  ┌─────────────────┐                                                    │
│  │ stopRecording() │ ──► recordingState = .transcribing                 │
│  │                 │ ──► Plays stop sound                               │
│  │                 │ ──► Creates Transcription record in SwiftData      │
│  └────────┬────────┘                                                    │
│           │                                                              │
│           ▼                                                              │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │              Route to TranscriptionService                         │  │
│  │                                                                    │  │
│  │  switch model.provider:                                            │  │
│  │    case .local:       → LocalTranscriptionService (Whisper.cpp)   │  │
│  │    case .parakeet:    → ParakeetTranscriptionService              │  │
│  │    case .fastConformer: → FastConformerTranscriptionService       │  │
│  │    case .nativeApple: → NativeAppleTranscriptionService           │  │
│  │    default:           → CloudTranscriptionService                 │  │
│  └────────────────────────────┬──────────────────────────────────────┘  │
│                               │                                          │
│                               ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Post-Processing                               │    │
│  │                                                                  │    │
│  │  1. TranscriptionOutputFilter.filter(text)  // Remove artifacts  │    │
│  │  2. WhisperTextFormatter.format(text)       // Capitalize, etc.  │    │
│  │  3. WordReplacementService.applyReplacements(to: text)          │    │
│  │  4. PromptDetectionService.analyzeText()    // Detect triggers   │    │
│  └──────────────────────────────┬──────────────────────────────────┘    │
│                                 │                                        │
│                                 ▼ (if AI enhancement enabled)           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                  AIEnhancementService                            │    │
│  │                                                                  │    │
│  │  recordingState = .enhancing                                     │    │
│  │  1. Assemble system message (prompt + context)                   │    │
│  │  2. Call AIService with transcript                               │    │
│  │  3. Filter output with AIEnhancementOutputFilter                 │    │
│  │  4. Store enhanced text in Transcription                         │    │
│  └──────────────────────────────┬──────────────────────────────────┘    │
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Finalize & Paste                              │    │
│  │                                                                  │    │
│  │  1. Save Transcription to SwiftData                              │    │
│  │  2. CursorPaster.pasteAtCursor(finalText)                        │    │
│  │  3. If PowerMode.isAutoSendEnabled → CursorPaster.pressEnter()   │    │
│  │  4. Restore original settings (end PowerMode session)            │    │
│  │  5. Dismiss recorder panel                                       │    │
│  │  6. recordingState = .idle                                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.2 TTS Generation Flow

```
User enters text in TTS Workspace
          │
          ▼
┌─────────────────────┐
│  TTSViewModel       │
│  generateSpeech()   │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│  Pre-processing                                      │
│  • Strip batch delimiters                            │
│  • Check character limit                             │
│  • Apply pronunciation rules                         │
│  • Auto-chunk if text > provider limit               │
└─────────────────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│  Provider Selection                                  │
│  • getProvider(for: selectedProvider)                │
│  • Get API key from KeychainManager                  │
│  • Build request with voice + style settings         │
└─────────────────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│  synthesizeSpeech() → Data (audio bytes)            │
│  • Handle chunked generation for long text          │
│  • Merge audio segments if multiple chunks          │
└─────────────────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│  Post-processing                                     │
│  • Load into AudioPlayerService                      │
│  • Record in generation history                      │
│  • Auto-play if configured                           │
└─────────────────────────────────────────────────────┘
```

---

## 9. Testing Strategy

### 9.1 Test Organization

```
VoiceInkTests/            # Unit tests
├── Services/
├── Models/
└── Utilities/

VoiceInkUITests/          # UI automation tests
```

### 9.2 Running Tests

```bash
# Run all tests
./run_tests.sh

# Or via Xcode
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk
```

### 9.3 Pre-Commit Checklist

- [ ] Code compiles without warnings
- [ ] All tests pass
- [ ] No secrets or API keys in code
- [ ] No force-unwraps (`!`) in production code
- [ ] No `try!` in SwiftUI previews
- [ ] All `ObservableObject` classes have `@MainActor`
- [ ] All `print()` statements wrapped in `#if DEBUG`
- [ ] No UserDefaults for API keys
- [ ] Security guidelines followed

---

## 10. Getting Started

### 10.1 Setup Checklist

1. **Open Project**: `open VoiceInk.xcodeproj`
2. **Read Coding Guidelines**: Review `AGENTS.md`
3. **Build & Run**: ⌘R in Xcode
4. **Grant Permissions**:
   - Microphone access
   - Accessibility (for pasting at cursor)
   - Screen Recording (for context capture)
5. **Configure a Model**: Settings → AI Models → Download or configure cloud model
6. **Set Hotkey**: Settings → Keyboard → Set recording shortcut
7. **Test Recording**: Press hotkey, speak, release

### 10.2 Key Files to Read First

| File | Purpose |
|------|---------|
| `VoiceInk.swift` | App entry, dependency injection |
| `WhisperState.swift` | Central orchestrator - read this thoroughly |
| `AIEnhancementService.swift` | AI text enhancement pipeline |
| `TTSViewModel.swift` | TTS workspace logic |
| `TranscriptionModel.swift` | Model protocol hierarchy |
| `PowerModeSessionManager.swift` | Context-aware configuration |
| `KeychainManager.swift` | Secure credential storage |
| `AGENTS.md` | Coding standards and conventions |

### 10.3 Common Development Tasks

**Adding a new cloud transcription provider:**
1. Create `NewProviderTranscriptionService.swift` in `Services/CloudTranscription/`
2. Add case to `ModelProvider` enum
3. Add case to `CloudTranscriptionService.transcribe()` routing
4. Add API key management in `APIKeyManagementView`

**Adding a new AI enhancement provider:**
1. Add case to `AIProvider` enum in `AIService.swift`
2. Implement `baseURL`, `defaultModel`, `availableModels`
3. Add verification method if needed
4. Add UI in Settings

**Adding a new TTS provider:**
1. Create service implementing `TTSProvider` protocol
2. Add case to `TTSProviderType` enum
3. Register in `TTSViewModel.getProvider()`
4. Add UI controls in `TTSSettingsView`

---

## Appendix A: Notification Names

```swift
// Recording/Transcription
.transcriptionCreated
.transcriptionCompleted

// Navigation
.navigateToDestination
.openFileForTranscription
.showShortcutCheatSheet

// Settings
.AppSettingsDidChange
.aiProviderKeyChanged
.languageDidChange
.promptSelectionChanged
.enhancementToggleChanged
.powerModeConfigurationApplied
```

---

## Appendix B: UserDefaults Keys

```swift
// Settings
"RecorderType"                    // "mini" or "notch"
"hasCompletedOnboarding"
"enableAIEnhancementFeatures"
"enableAnnouncements"
"autoUpdateCheck"

// AI Enhancement
"isAIEnhancementEnabled"
"useClipboardContext"
"useScreenCaptureContext"
"customPrompts"
"selectedPromptId"
"selectedAIProvider"

// Transcription
"CurrentTranscriptionModel"
"SelectedLanguage"
"IsTextFormattingEnabled"
"AppendTrailingSpace"

// Power Mode
"powerModeConfigurationsV2"
"activeConfigurationId"
"powerModeUIFlag"

// Audio
"lastUsedMicrophoneDeviceID"

// Cleanup
"IsTranscriptionCleanupEnabled"
```

---

**Document Version:** 1.1
**Last Updated:** December 2025
**Maintainer:** VoiceInk Engineering Team

**Recent Updates:**
- **v1.1** (2025-12-27): Updated Whisper directory structure to reflect SOLID refactoring with new Protocols/, Providers/, Managers/, Processors/, Actors/, Coordinators/, and Models/ subdirectories.
