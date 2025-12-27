# Cloud Transcription Service Registry Pattern Design

## Current State Analysis

### ✅ Well-Designed Components

The `CloudTranscriptionService` already implements a proper registry pattern that follows SOLID principles:

```swift
class CloudTranscriptionService: TranscriptionService {
    private var providers: [ModelProvider: any CloudTranscriptionProvider] = [:]

    init(providers: [any CloudTranscriptionProvider] = [
        GroqTranscriptionService(),
        ElevenLabsTranscriptionService(),
        // ... other providers
    ]) {
        providers.forEach { register($0) }
    }

    func register(_ provider: any CloudTranscriptionProvider) {
        providers[provider.supportedProvider] = provider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let provider = providers[model.provider] else {
            throw CloudTranscriptionError.unsupportedProvider
        }
        return try await provider.transcribe(audioURL: audioURL, model: model)
    }
}
```

**Benefits:**
- ✅ **Open/Closed Principle**: New providers can be added without modifying existing code
- ✅ **Dependency Inversion**: Depends on abstractions (`CloudTranscriptionProvider`)
- ✅ **Single Responsibility**: Only handles provider registration and delegation
- ✅ **Registry Pattern**: Clean provider lookup by `ModelProvider` enum

### ❌ SOLID Principle Violations

Despite the well-designed `CloudTranscriptionService`, there are violations in other parts of the codebase:

#### 1. WhisperState+ModelQueries.swift - Model Availability Checks

```swift
extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        return allAvailableModels.filter { model in
            switch model.provider {  // ❌ OCP Violation
            case .local:
                return availableModels.contains { $0.name == model.name }
            case .groq:
                return keychain.hasAPIKey(for: "GROQ")  // ❌ Hardcoded strings
            case .elevenLabs:
                return keychain.hasAPIKey(for: "ElevenLabs")
            // ... 10+ more cases
            }
        }
    }
}
```

**Problems:**
- **Open/Closed Principle Violation**: Adding a new provider requires modifying this switch statement
- **Hardcoded Strings**: API key names are hardcoded instead of being provider-specific
- **Mixed Concerns**: Model availability logic is scattered across different provider types

#### 2. CloudModelCardRowView.swift - Provider Key Mapping

```swift
private var providerKey: String {
    switch model.provider {  // ❌ OCP Violation
    case .groq:
        return "GROQ"
    case .elevenLabs:
        return "ElevenLabs"
    // ... more cases
    default:
        return model.provider.rawValue
    }
}
```

**Problems:**
- **Open/Closed Principle Violation**: New providers require switch statement modification
- **Inconsistent Mapping**: Some use custom strings, others use `rawValue`

#### 3. CloudModelCardRowView.swift - AI Service Provider Selection

```swift
switch model.provider {  // ❌ OCP Violation
case .groq:
    aiService.selectedProvider = .groq
case .elevenLabs:
    aiService.selectedProvider = .elevenLabs
// ... more cases
}
```

## Proposed Registry Pattern Solution

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    ModelCapabilityRegistry                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              ProviderCapabilities                    │    │
│  │  ┌─────────────────────────────────────────────────┐ │    │
│  │  │        ModelAvailabilityChecker                 │ │    │
│  │  │                                                 │ │    │
│  │  │  - checkAvailability(model) -> Bool             │ │    │
│  │  │  - getAPIKeyName() -> String                    │ │    │
│  │  │  - getAIServiceProvider() -> AIProvider?        │ │    │
│  │  └─────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Registry: [ModelProvider: ProviderCapabilities]           │
└─────────────────────────────────────────────────────────────┘
```

### 1. ProviderCapabilities Protocol

```swift
protocol ProviderCapabilities {
    var supportedProvider: ModelProvider { get }

    /// Checks if a model is available/usable
    func checkAvailability(model: any TranscriptionModel) -> Bool

    /// Returns the API key name for Keychain storage
    func getAPIKeyName() -> String

    /// Returns the corresponding AI service provider (if applicable)
    func getAIServiceProvider() -> AIProvider?
}
```

### 2. ModelCapabilityRegistry

```swift
@MainActor
class ModelCapabilityRegistry {
    private var capabilities: [ModelProvider: ProviderCapabilities] = [:]

    init() {
        // Register all provider capabilities
        register(LocalModelCapabilities())
        register(GroqModelCapabilities())
        register(ElevenLabsModelCapabilities())
        // ... register other providers
    }

    func register(_ capability: ProviderCapabilities) {
        capabilities[capability.supportedProvider] = capability
    }

    func getCapabilities(for provider: ModelProvider) -> ProviderCapabilities? {
        capabilities[provider]
    }

    func isModelAvailable(_ model: any TranscriptionModel) -> Bool {
        guard let capability = capabilities[model.provider] else {
            return false
        }
        return capability.checkAvailability(model: model)
    }

    func getAPIKeyName(for provider: ModelProvider) -> String? {
        capabilities[provider]?.getAPIKeyName()
    }

    func getAIServiceProvider(for provider: ModelProvider) -> AIProvider? {
        capabilities[provider]?.getAIServiceProvider()
    }
}
```

### 3. Provider-Specific Capability Implementations

#### Local Model Capabilities
```swift
class LocalModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .local

    func checkAvailability(model: any TranscriptionModel) -> Bool {
        // Check if model file exists in WhisperState.availableModels
        // This would need access to WhisperState or a model file manager
        return true // Simplified for example
    }

    func getAPIKeyName() -> String {
        // Local models don't need API keys
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil // Local models don't use AI service
    }
}
```

#### Cloud Provider Capabilities
```swift
class GroqModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .groq

    func checkAvailability(model: any TranscriptionModel) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "GROQ"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .groq
    }
}
```

### 4. Updated WhisperState+ModelQueries

```swift
extension WhisperState {
    private static let capabilityRegistry = ModelCapabilityRegistry()

    var usableModels: [any TranscriptionModel] {
        return allAvailableModels.filter { model in
            Self.capabilityRegistry.isModelAvailable(model)
        }
    }
}
```

### 5. Updated CloudModelCardRowView

```swift
private var providerKey: String {
    guard let keyName = WhisperState.capabilityRegistry.getAPIKeyName(for: model.provider) else {
        return model.provider.rawValue
    }
    return keyName
}

private func verifyAPIKey() {
    // ... existing code ...

    if let aiProvider = WhisperState.capabilityRegistry.getAIServiceProvider(for: model.provider) {
        aiService.selectedProvider = aiProvider
    } else {
        // Handle case where provider doesn't have AI service mapping
        isVerifying = false
        verificationStatus = .failure
        return
    }

    // ... rest of verification logic ...
}
```

## Benefits of Registry Pattern Solution

### ✅ SOLID Principles Compliance

1. **Open/Closed Principle**: New providers can be added by implementing `ProviderCapabilities` without modifying existing code
2. **Single Responsibility**: Each capability class handles only its provider's logic
3. **Dependency Inversion**: High-level modules depend on abstractions, not concretions
4. **Interface Segregation**: `ProviderCapabilities` is focused and minimal

### ✅ Maintainability Improvements

- **Centralized Logic**: All provider-specific behavior is in one place per provider
- **Consistent API**: All providers implement the same interface
- **Testable**: Each capability can be unit tested independently
- **Type Safe**: No more string literals or switch statements

### ✅ Extensibility

Adding a new cloud transcription provider requires only:
1. Create new `XxxTranscriptionService` class
2. Create new `XxxModelCapabilities` class
3. Register both in their respective registries

No existing code needs to be modified!

## Migration Strategy

### Phase 1: Create Registry Infrastructure
1. Implement `ProviderCapabilities` protocol
2. Create `ModelCapabilityRegistry` class
3. Implement capability classes for existing providers

### Phase 2: Update Model Queries
1. Replace switch statement in `WhisperState+ModelQueries.usableModels`
2. Update any other switch statements on `ModelProvider` for availability checks

### Phase 3: Update UI Components
1. Update `CloudModelCardRowView` to use registry
2. Update any other UI components that map providers to keys/services

### Phase 4: Testing & Validation
1. Ensure all existing functionality works
2. Add tests for new registry pattern
3. Verify new provider addition doesn't break existing code

## Implementation Priority

1. **High Priority**: Model availability checks (affects core functionality)
2. **Medium Priority**: UI provider mapping (affects user experience)
3. **Low Priority**: AI service provider mapping (affects API key verification)

This registry pattern will make the codebase much more maintainable and extensible while following SOLID principles.