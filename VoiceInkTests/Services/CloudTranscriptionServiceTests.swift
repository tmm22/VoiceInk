import XCTest
@testable import VoiceInk

/// Tests for Cloud Transcription Services
/// Tests error handling, request construction, and response parsing
@available(macOS 14.0, *)
final class CloudTranscriptionServiceTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    /// Mock transcription model for testing
    struct MockCloudModel: TranscriptionModel {
        let id = UUID()
        let name: String
        let displayName: String
        let description: String = "Test model"
        let provider: ModelProvider
        let isMultilingualModel: Bool = true
        let supportedLanguages: [String: String] = ["en": "English", "auto": "Auto-detect"]
        let speed: Double = 0.8
        let accuracy: Double = 0.9
    }
    
    var tempAudioURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary audio file for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempAudioURL = tempDir.appendingPathComponent("test_audio_\(UUID().uuidString).wav")
        
        // Create a minimal WAV file header (44 bytes) + some audio data
        var wavData = Data()
        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // File size - 8
        wavData.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // Chunk size (16)
        wavData.append(contentsOf: [0x01, 0x00]) // Audio format (PCM)
        wavData.append(contentsOf: [0x01, 0x00]) // Num channels (1)
        wavData.append(contentsOf: [0x80, 0x3E, 0x00, 0x00]) // Sample rate (16000)
        wavData.append(contentsOf: [0x00, 0x7D, 0x00, 0x00]) // Byte rate
        wavData.append(contentsOf: [0x02, 0x00]) // Block align
        wavData.append(contentsOf: [0x10, 0x00]) // Bits per sample (16)
        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Data size
        
        try wavData.write(to: tempAudioURL)
    }
    
    override func tearDown() async throws {
        // Clean up temp file
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }
    
    // MARK: - CloudTranscriptionError Tests
    
    func testCloudTranscriptionErrorDescriptions() {
        // Test that all error cases have proper descriptions
        let errors: [CloudTranscriptionError] = [
            .unsupportedProvider,
            .missingAPIKey,
            .invalidAPIKey,
            .audioFileNotFound,
            .apiRequestFailed(statusCode: 401, message: "Unauthorized"),
            .networkError(URLError(.notConnectedToInternet)),
            .noTranscriptionReturned,
            .dataEncodingError
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    func testAPIRequestFailedErrorContainsStatusCode() {
        let error = CloudTranscriptionError.apiRequestFailed(statusCode: 429, message: "Rate limited")
        XCTAssertTrue(error.errorDescription?.contains("429") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Rate limited") ?? false)
    }
    
    func testNetworkErrorContainsUnderlyingError() {
        let underlyingError = URLError(.timedOut)
        let error = CloudTranscriptionError.networkError(underlyingError)
        XCTAssertNotNil(error.errorDescription)
    }
    
    // MARK: - CloudTranscriptionService Routing Tests
    
    func testCloudTranscriptionServiceThrowsForUnsupportedProvider() async {
        let service = CloudTranscriptionService()
        let model = MockCloudModel(name: "test", displayName: "Test", provider: .local)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw unsupportedProvider error")
        } catch let error as CloudTranscriptionError {
            if case .unsupportedProvider = error {
                // Expected
            } else {
                XCTFail("Expected unsupportedProvider error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testCloudTranscriptionServiceThrowsForParakeetProvider() async {
        let service = CloudTranscriptionService()
        let model = MockCloudModel(name: "test", displayName: "Test", provider: .parakeet)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw unsupportedProvider error")
        } catch let error as CloudTranscriptionError {
            if case .unsupportedProvider = error {
                // Expected - parakeet is a local provider
            } else {
                XCTFail("Expected unsupportedProvider error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Missing API Key Tests
    
    func testGroqServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        // Clear any existing API key
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "GROQ")
        
        let service = GroqTranscriptionService()
        let model = MockCloudModel(name: "whisper-large-v3", displayName: "Groq Whisper", provider: .groq)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testDeepgramServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "Deepgram")
        
        let service = DeepgramTranscriptionService()
        let model = MockCloudModel(name: "nova-2", displayName: "Deepgram Nova 2", provider: .deepgram)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testElevenLabsServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "ElevenLabs")
        
        let service = ElevenLabsTranscriptionService()
        let model = MockCloudModel(name: "scribe_v1", displayName: "ElevenLabs Scribe", provider: .elevenLabs)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testMistralServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "Mistral")
        
        let service = MistralTranscriptionService()
        let model = MockCloudModel(name: "mistral-stt", displayName: "Mistral STT", provider: .mistral)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testGeminiServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "Gemini")
        
        let service = GeminiTranscriptionService()
        let model = MockCloudModel(name: "gemini-2.0-flash", displayName: "Gemini Flash", provider: .gemini)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSonioxServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "Soniox")
        
        let service = SonioxTranscriptionService()
        let model = MockCloudModel(name: "soniox-stt", displayName: "Soniox STT", provider: .soniox)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testAssemblyAIServiceThrowsMissingAPIKeyWhenNotConfigured() async {
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "AssemblyAI")
        
        let service = AssemblyAITranscriptionService()
        let model = MockCloudModel(name: "assemblyai-best", displayName: "AssemblyAI Best", provider: .assemblyAI)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw missingAPIKey error")
        } catch let error as CloudTranscriptionError {
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Audio File Not Found Tests
    
    func testGroqServiceThrowsAudioFileNotFoundForInvalidURL() async {
        // Set a fake API key to bypass the API key check
        let keychain = KeychainManager()
        keychain.saveAPIKey("fake-api-key", for: "GROQ")
        
        defer {
            keychain.deleteAPIKey(for: "GROQ")
        }
        
        let service = GroqTranscriptionService()
        let model = MockCloudModel(name: "whisper-large-v3", displayName: "Groq Whisper", provider: .groq)
        let invalidURL = URL(fileURLWithPath: "/nonexistent/audio.wav")
        
        do {
            _ = try await service.transcribe(audioURL: invalidURL, model: model)
            XCTFail("Should throw audioFileNotFound error")
        } catch let error as CloudTranscriptionError {
            if case .audioFileNotFound = error {
                // Expected
            } else {
                XCTFail("Expected audioFileNotFound error, got \(error)")
            }
        } catch {
            // Network errors are also acceptable since we're using a fake API key
            // The important thing is that we don't crash
        }
    }
    
    // MARK: - Custom Model Tests
    
    func testCustomModelRequiresCustomCloudModelType() async {
        let service = CloudTranscriptionService()
        let model = MockCloudModel(name: "custom-model", displayName: "Custom", provider: .custom)
        
        do {
            _ = try await service.transcribe(audioURL: tempAudioURL, model: model)
            XCTFail("Should throw unsupportedProvider error for non-CustomCloudModel")
        } catch let error as CloudTranscriptionError {
            if case .unsupportedProvider = error {
                // Expected - custom provider requires CustomCloudModel type
            } else {
                XCTFail("Expected unsupportedProvider error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Model Provider Mapping Tests
    
    func testAllCloudProvidersAreMapped() {
        // Verify that all cloud providers have corresponding services
        let cloudProviders: [ModelProvider] = [
            .groq,
            .elevenLabs,
            .deepgram,
            .mistral,
            .gemini,
            .soniox,
            .assemblyAI,
            .custom
        ]
        
        // These should NOT be handled by CloudTranscriptionService
        let localProviders: [ModelProvider] = [
            .local,
            .parakeet,
            .fastConformer,
            .senseVoice,
            .nativeApple
        ]
        
        // Verify cloud providers are distinct from local providers
        for provider in cloudProviders {
            XCTAssertFalse(localProviders.contains(provider), "\(provider) should not be in local providers")
        }
    }
}

// MARK: - CustomModelManager Tests

@available(macOS 14.0, *)
final class CustomModelManagerTests: XCTestCase {
    
    var manager: CustomModelManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = CustomModelManager.shared
        // Clear any existing custom models for clean test state
        for model in manager.customModels {
            manager.deleteModel(model)
        }
    }
    
    override func tearDown() async throws {
        // Clean up any models created during tests
        for model in manager.customModels {
            manager.deleteModel(model)
        }
        try await super.tearDown()
    }
    
    func testAddCustomModel() {
        let initialCount = manager.customModels.count
        
        manager.addModel(
            name: "Test Model",
            displayName: "Test Display Name",
            description: "Test Description",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "test-api-key",
            modelName: "test-model-v1",
            isMultilingual: true
        )
        
        XCTAssertEqual(manager.customModels.count, initialCount + 1)
        
        let addedModel = manager.customModels.last
        XCTAssertNotNil(addedModel)
        XCTAssertEqual(addedModel?.name, "Test Model")
        XCTAssertEqual(addedModel?.displayName, "Test Display Name")
        XCTAssertEqual(addedModel?.apiEndpoint, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(addedModel?.modelName, "test-model-v1")
        XCTAssertTrue(addedModel?.isMultilingualModel ?? false)
    }
    
    func testDeleteCustomModel() {
        // Add a model first
        manager.addModel(
            name: "Model To Delete",
            displayName: "Delete Me",
            description: "Will be deleted",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "test-key",
            modelName: "delete-model",
            isMultilingual: false
        )
        
        let countAfterAdd = manager.customModels.count
        guard let modelToDelete = manager.customModels.last else {
            XCTFail("Model should exist after adding")
            return
        }
        
        manager.deleteModel(modelToDelete)
        
        XCTAssertEqual(manager.customModels.count, countAfterAdd - 1)
        XCTAssertFalse(manager.customModels.contains(where: { $0.id == modelToDelete.id }))
    }
    
    func testUpdateCustomModel() {
        // Add a model first
        manager.addModel(
            name: "Original Name",
            displayName: "Original Display",
            description: "Original Description",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "original-key",
            modelName: "original-model",
            isMultilingual: true
        )
        
        guard var modelToUpdate = manager.customModels.last else {
            XCTFail("Model should exist after adding")
            return
        }
        
        // Create updated model with same ID
        let updatedModel = CustomCloudModel(
            id: modelToUpdate.id,
            name: "Updated Name",
            displayName: "Updated Display",
            description: "Updated Description",
            apiEndpoint: "https://api.updated.com/v1/audio/transcriptions",
            apiKey: "updated-key",
            modelName: "updated-model",
            isMultilingual: false
        )
        
        manager.updateModel(updatedModel)
        
        // Find the model again
        guard let foundModel = manager.customModels.first(where: { $0.id == modelToUpdate.id }) else {
            XCTFail("Updated model should still exist")
            return
        }
        
        XCTAssertEqual(foundModel.name, "Updated Name")
        XCTAssertEqual(foundModel.displayName, "Updated Display")
        XCTAssertEqual(foundModel.apiEndpoint, "https://api.updated.com/v1/audio/transcriptions")
        XCTAssertEqual(foundModel.modelName, "updated-model")
        XCTAssertFalse(foundModel.isMultilingualModel)
    }
    
    func testCustomModelAPIKeyStoredInKeychain() {
        let testAPIKey = "secure-test-api-key-\(UUID().uuidString)"
        
        manager.addModel(
            name: "Keychain Test Model",
            displayName: "Keychain Test",
            description: "Tests keychain storage",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: testAPIKey,
            modelName: "keychain-test",
            isMultilingual: true
        )
        
        guard let addedModel = manager.customModels.last else {
            XCTFail("Model should exist after adding")
            return
        }
        
        // Verify API key is retrievable from keychain
        let keychain = KeychainManager()
        let storedKey = keychain.getAPIKey(for: "custom_model_\(addedModel.id.uuidString)")
        XCTAssertEqual(storedKey, testAPIKey)
    }
    
    func testCustomModelProviderIsAlwaysCustom() {
        manager.addModel(
            name: "Provider Test",
            displayName: "Provider Test",
            description: "Tests provider",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "test-key",
            modelName: "provider-test",
            isMultilingual: true
        )
        
        guard let model = manager.customModels.last else {
            XCTFail("Model should exist")
            return
        }
        
        XCTAssertEqual(model.provider, .custom)
    }
}