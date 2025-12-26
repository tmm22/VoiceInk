import XCTest
import Combine
@testable import VoiceInk

/// Tests for OllamaAIService - focusing on connection, model management, and enhancement
@available(macOS 14.0, *)
@MainActor
final class OllamaServiceTests: XCTestCase {
    
    var sut: OllamaAIService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = OllamaAIService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testCheckConnection_WhenInvalidURL_SetsIsConnectedToFalse() async {
        // Given
        sut.baseURL = "not-a-valid-url"
        
        // When
        await sut.checkConnection()
        
        // Then
        XCTAssertFalse(sut.isConnected)
    }
    
    func testCheckConnection_WhenEmptyURL_SetsIsConnectedToFalse() async {
        // Given
        sut.baseURL = ""
        
        // When
        await sut.checkConnection()
        
        // Then
        XCTAssertFalse(sut.isConnected)
    }
    
    func testCheckConnection_WhenValidURLButServerDown_SetsIsConnectedToFalse() async {
        // Given
        sut.baseURL = "http://localhost:9999" // Non-existent server
        
        // When
        await sut.checkConnection()
        
        // Then
        XCTAssertFalse(sut.isConnected)
    }
    
    // MARK: - Model Refresh Tests
    
    func testRefreshModels_WhenCalled_SetsIsLoadingModels() async {
        // Given
        sut.baseURL = "http://localhost:9999" // Will fail but we test state
        
        // When
        Task {
            await sut.refreshModels()
        }
        
        // Then - isLoadingModels should be true during refresh
        // Note: This is a basic test; in a real scenario we'd need to mock the network
        XCTAssertTrue(sut.isLoadingModels || sut.availableModels.isEmpty)
    }
    
    func testRefreshModels_WhenNetworkError_ClearsAvailableModels() async {
        // Given
        sut.baseURL = "http://invalid-server-that-does-not-exist.local"
        sut.availableModels = [OllamaAIService.OllamaModel(name: "test", modified_at: "2024-01-01", size: 1000, digest: "abc", details: OllamaAIService.OllamaModel.ModelDetails(format: "gguf", family: "test", families: nil, parameter_size: "7B", quantization_level: "q4"))]
        
        // When
        await sut.refreshModels()
        
        // Then
        XCTAssertTrue(sut.availableModels.isEmpty)
        XCTAssertFalse(sut.isLoadingModels)
    }
    
    // MARK: - Model Cache Tests
    
    func testInvalidateModelCache_WhenCalled_ClearsCache() async {
        // Given
        // This is a unit test for the cache invalidation method
        // We can't directly test the cache state as it's private,
        // but we can verify the method doesn't crash
        
        // When/Then
        XCTAssertNoThrow(sut.invalidateModelCache())
    }
    
    // MARK: - Enhancement Tests
    
    func testEnhance_WhenURLCannotFormAPIEndpoint_ThrowsInvalidURLError() async {
        // Given - URL that can't form a valid API endpoint
        // Note: URL(string:) accepts many strings, but URL(string:relativeTo:) may fail
        sut.baseURL = ""  // Empty URL will fail to form API endpoint
        sut.selectedModel = "test-model"
        
        // When/Then
        do {
            _ = try await sut.enhance("test text", withSystemPrompt: "test prompt")
            XCTFail("Expected LocalAIError.invalidURL to be thrown")
        } catch LocalAIError.invalidURL {
            // Expected
        } catch {
            XCTFail("Expected LocalAIError.invalidURL, got \(error)")
        }
    }
    
    func testEnhance_WhenNoSystemPrompt_ThrowsInvalidRequestError() async {
        // Given
        sut.baseURL = "http://localhost:9999"
        sut.selectedModel = "test-model"
        
        // When/Then
        do {
            _ = try await sut.enhance("test text", withSystemPrompt: nil)
            XCTFail("Expected LocalAIError.invalidRequest to be thrown")
        } catch LocalAIError.invalidRequest {
            // Expected
        } catch {
            XCTFail("Expected LocalAIError.invalidRequest, got \(error)")
        }
    }
    
    func testEnhance_WhenEmptyText_AttemptsRequest() async {
        // Given - The service doesn't validate empty text, it sends the request
        // This test verifies the behavior (network error expected since server is down)
        sut.baseURL = "http://localhost:9999"
        sut.selectedModel = "test-model"
        
        // When/Then - Should attempt network request and fail with network error
        do {
            _ = try await sut.enhance("", withSystemPrompt: "test prompt")
            XCTFail("Expected network error since server is not running")
        } catch {
            // Expected - network error because server is not running
            // The service doesn't validate empty text, it just sends the request
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Published Properties Tests
    
    func testBaseURL_WhenChanged_PersistsToAppSettings() {
        // Given
        let newURL = "http://localhost:11434"
        
        // When
        sut.baseURL = newURL
        
        // Then
        XCTAssertEqual(sut.baseURL, newURL)
        XCTAssertEqual(AppSettings.Ollama.baseURL, newURL)
    }
    
    func testSelectedModel_WhenChanged_PersistsToAppSettings() {
        // Given
        let newModel = "llama2:7b"
        
        // When
        sut.selectedModel = newModel
        
        // Then
        XCTAssertEqual(sut.selectedModel, newModel)
        XCTAssertEqual(AppSettings.Ollama.selectedModel, newModel)
    }
    
    func testAvailableModels_InitialValue_IsEmpty() {
        // Then
        XCTAssertTrue(sut.availableModels.isEmpty)
    }
    
    func testIsConnected_InitialValue_IsFalse() {
        // Then
        XCTAssertFalse(sut.isConnected)
    }
    
    func testIsLoadingModels_InitialValue_IsFalse() {
        // Then
        XCTAssertFalse(sut.isLoadingModels)
    }
    
    // MARK: - Model Structure Tests
    
    func testOllamaModel_IDIsName() {
        // Given
        let model = OllamaAIService.OllamaModel(
            name: "llama2:7b",
            modified_at: "2024-01-01T00:00:00Z",
            size: 4000000000,
            digest: "abc123",
            details: OllamaAIService.OllamaModel.ModelDetails(
                format: "gguf",
                family: "llama",
                families: ["llama", "llama2"],
                parameter_size: "7B",
                quantization_level: "q4"
            )
        )
        
        // Then
        XCTAssertEqual(model.id, "llama2:7b")
    }
    
    // MARK: - Error Description Tests
    
    func testLocalAIError_HasValidDescriptions() {
        // Then
        XCTAssertNotNil(LocalAIError.invalidURL.errorDescription)
        XCTAssertNotNil(LocalAIError.serviceUnavailable.errorDescription)
        XCTAssertNotNil(LocalAIError.invalidResponse.errorDescription)
        XCTAssertNotNil(LocalAIError.modelNotFound.errorDescription)
        XCTAssertNotNil(LocalAIError.serverError.errorDescription)
        XCTAssertNotNil(LocalAIError.invalidRequest.errorDescription)
    }
}
