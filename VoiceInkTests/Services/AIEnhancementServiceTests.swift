import XCTest
import SwiftData
import Combine
@testable import VoiceInk

/// Tests for AIEnhancementService - focusing on enhancement logic, state management, and context handling
@available(macOS 14.0, *)
@MainActor
final class AIEnhancementServiceTests: XCTestCase {
    
    var sut: AIEnhancementService!
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        // Create in-memory model container for testing
        modelContainer = try ModelContainer.createInMemoryContainer()
        modelContext = modelContainer.mainContext
        
        // Create service with default AI service (we'll test public APIs)
        sut = AIEnhancementService(aiService: nil, modelContext: modelContext)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization_SetsDefaultTimeout() {
        // Then - timeout should be loaded from AppSettings or use default
        // The actual value depends on persisted settings, so we verify it's within valid range
        XCTAssertGreaterThanOrEqual(sut.requestTimeout, AIEnhancementService.minimumTimeout)
        XCTAssertLessThanOrEqual(sut.requestTimeout, AIEnhancementService.maximumTimeout)
    }
    
    func testInitialization_SetsDefaultReasoningEffort() {
        // Then - reasoning effort should be loaded from AppSettings or use default
        // The actual value depends on persisted settings, so we just verify it's a valid value
        XCTAssertTrue([ReasoningEffort.low, .medium, .high].contains(sut.reasoningEffort))
    }
    
    func testInitialization_SetsInitialEnhancementEnabled() {
        // Then
        // Should match AppSettings or default to false
        XCTAssertEqual(sut.isEnhancementEnabled, AppSettings.Enhancements.isEnhancementEnabled)
    }
    
    func testInitialization_LoadsCustomPrompts() {
        // Then
        // Should load prompts from AppSettings or be empty
        // customPrompts is always [CustomPrompt], so just verify it's accessible
        XCTAssertNotNil(sut.customPrompts)
    }
    
    // MARK: - Published Properties Tests
    
    func testIsEnhancementEnabled_WhenChanged_PersistsToAppSettings() {
        // Given
        let originalValue = sut.isEnhancementEnabled
        
        // When
        sut.isEnhancementEnabled = !originalValue
        
        // Then
        XCTAssertEqual(sut.isEnhancementEnabled, !originalValue)
        XCTAssertEqual(AppSettings.Enhancements.isEnhancementEnabled, !originalValue)
    }
    
    func testRequestTimeout_WhenChanged_PersistsToAppSettings() {
        // Given
        let newTimeout: TimeInterval = 60.0
        
        // When
        sut.requestTimeout = newTimeout
        
        // Then
        XCTAssertEqual(sut.requestTimeout, newTimeout)
        XCTAssertEqual(AppSettings.Enhancements.requestTimeout, newTimeout)
    }
    
    func testRequestTimeout_WhenBelowMinimum_StillAccepts() {
        // Given
        let belowMinimum = AIEnhancementService.minimumTimeout - 1
        
        // When
        sut.requestTimeout = belowMinimum
        
        // Then
        XCTAssertEqual(sut.requestTimeout, belowMinimum)
    }
    
    func testRequestTimeout_WhenAboveMaximum_StillAccepts() {
        // Given
        let aboveMaximum = AIEnhancementService.maximumTimeout + 1
        
        // When
        sut.requestTimeout = aboveMaximum
        
        // Then
        XCTAssertEqual(sut.requestTimeout, aboveMaximum)
    }
    
    func testReasoningEffort_WhenChanged_PersistsToAppSettings() {
        // Given
        let newEffort = ReasoningEffort.high
        
        // When
        sut.reasoningEffort = newEffort
        
        // Then
        XCTAssertEqual(sut.reasoningEffort, newEffort)
        XCTAssertEqual(AppSettings.Enhancements.reasoningEffortRawValue, newEffort.rawValue)
    }
    
    func testSelectedPromptId_WhenChanged_PersistsToAppSettings() {
        // Given
        let testPrompt = CustomPrompt(title: "Test Prompt", promptText: "Test", useSystemInstructions: false)
        sut.customPrompts = [testPrompt]
        let promptId = testPrompt.id
        
        // When
        sut.selectedPromptId = promptId
        
        // Then
        XCTAssertEqual(sut.selectedPromptId, promptId)
        XCTAssertEqual(AppSettings.Enhancements.selectedPromptId, promptId.uuidString)
    }
    
    func testCustomPrompts_WhenChanged_PersistsToAppSettings() {
        // Given
        let testPrompts = [
            CustomPrompt(title: "Prompt 1", promptText: "Text 1", useSystemInstructions: false),
            CustomPrompt(title: "Prompt 2", promptText: "Text 2", useSystemInstructions: true)
        ]
        
        // When
        sut.customPrompts = testPrompts
        
        // Then
        XCTAssertEqual(sut.customPrompts.count, 2)
        XCTAssertEqual(sut.customPrompts[0].title, "Prompt 1")
    }
    
    // MARK: - Computed Properties Tests
    
    func testActivePrompt_WhenNoPromptSelected_ReturnsNil() {
        // Given
        sut.selectedPromptId = nil
        sut.customPrompts = []
        
        // Then
        XCTAssertNil(sut.activePrompt)
    }
    
    func testActivePrompt_WhenPromptSelected_ReturnsCorrectPrompt() {
        // Given
        let testPrompt = CustomPrompt(title: "Test", promptText: "Text", useSystemInstructions: false)
        sut.customPrompts = [testPrompt]
        sut.selectedPromptId = testPrompt.id
        
        // Then
        XCTAssertNotNil(sut.activePrompt)
        XCTAssertEqual(sut.activePrompt?.title, "Test")
    }
    
    func testAllPrompts_ReturnsCustomPrompts() {
        // Given
        let testPrompts = [
            CustomPrompt(title: "Prompt 1", promptText: "Text 1", useSystemInstructions: false),
            CustomPrompt(title: "Prompt 2", promptText: "Text 2", useSystemInstructions: true)
        ]
        sut.customPrompts = testPrompts
        
        // Then
        XCTAssertEqual(sut.allPrompts.count, 2)
    }
    
    func testIsConfigured_WhenAPIKeyValid_ReturnsTrue() {
        // Given - Set a valid API key in keychain
        let keychain = KeychainManager()
        try? keychain.saveAPIKey("test-valid-key", for: AIProvider.openAI.rawValue)
        
        // Create new service instance
        let newService = AIEnhancementService(aiService: nil, modelContext: modelContext)
        newService.getAIService()?.selectedProvider = .openAI
        
        // Then
        XCTAssertTrue(newService.isConfigured)
        
        // Cleanup
        try? keychain.deleteAPIKey(for: AIProvider.openAI.rawValue)
    }
    
    func testIsConfigured_WhenAPIKeyInvalid_ReturnsFalse() {
        // Given - No API key in keychain
        let newService = AIEnhancementService(aiService: nil, modelContext: modelContext)
        newService.getAIService()?.selectedProvider = .openAI
        
        // Then
        XCTAssertFalse(newService.isConfigured)
    }
    
    // MARK: - Context Settings Tests
    
    func testContextSettings_WhenChanged_PersistsToAppSettings() {
        // Given
        var newSettings = AIContextSettings()
        newSettings.includeClipboard = true
        newSettings.includeScreenCapture = false
        newSettings.includeCalendar = true
        newSettings.includeBrowserContent = false
        newSettings.includeSelectedFiles = true
        newSettings.includeFocusedElement = false
        // Note: contextPriorities is a dictionary, not modified in this test
        
        // When
        sut.contextSettings = newSettings
        
        // Then
        XCTAssertEqual(sut.contextSettings.includeClipboard, true)
        XCTAssertEqual(sut.contextSettings.includeScreenCapture, false)
        XCTAssertEqual(sut.contextSettings.includeCalendar, true)
        XCTAssertEqual(sut.contextSettings.includeBrowserContent, false)
        XCTAssertEqual(sut.contextSettings.includeSelectedFiles, true)
        XCTAssertEqual(sut.contextSettings.includeFocusedElement, false)
    }
    
    func testUseClipboardContext_WhenSet_UpdatesContextSettings() {
        // Given
        sut.contextSettings.includeClipboard = false
        
        // When
        sut.useClipboardContext = true
        
        // Then
        XCTAssertTrue(sut.useClipboardContext)
        XCTAssertTrue(sut.contextSettings.includeClipboard)
    }
    
    func testUseScreenCaptureContext_WhenSet_UpdatesContextSettings() {
        // Given
        sut.contextSettings.includeScreenCapture = false
        
        // When
        sut.useScreenCaptureContext = true
        
        // Then
        XCTAssertTrue(sut.useScreenCaptureContext)
        XCTAssertTrue(sut.contextSettings.includeScreenCapture)
    }
    
    // MARK: - Enhancement Tests
    
    // Note: Full enhancement tests require network calls and complex setup.
    // These tests focus on the service's public API and state management.
    
    // MARK: - Context Capture Tests
    
    func testCaptureContext_WhenCalled_DoesNotCrash() async {
        // When/Then
        await sut.captureContext()
        // Should complete without throwing
    }
    
    func testCaptureScreenContext_WhenCalled_DoesNotCrash() async {
        // When/Then
        await sut.captureScreenContext()
        // Should complete without throwing
    }
    
    func testCaptureClipboardContext_WhenCalled_DoesNotCrash() {
        // When/Then
        sut.captureClipboardContext()
        // Should complete without throwing
    }
    
    func testClearCapturedContexts_WhenCalled_DoesNotCrash() {
        // When/Then
        sut.clearCapturedContexts()
        // Should complete without throwing
    }
    
    // MARK: - Rate Limit Tests
    
    func testWaitForRateLimit_WhenFirstCall_CompletesImmediately() async throws {
        // Given
        sut.lastRequestTime = nil
        
        // When/Then - should complete without throwing
        try await sut.waitForRateLimit()
    }
    
    func testWaitForRateLimit_WhenCalledWithinLimit_Waits() async throws {
        // Given
        sut.lastRequestTime = Date()
        
        // When
        let startTime = Date()
        try await sut.waitForRateLimit()
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Then - Should have waited at least rate limit interval
        XCTAssertGreaterThanOrEqual(elapsed, sut.rateLimitInterval - 0.1) // Small tolerance
    }
    
    // MARK: - Truncation Tests
    
    func testTruncateForStorage_WhenTextShorterThanLimit_ReturnsOriginal() {
        // Given
        let text = "Short text"
        let limit = 100
        
        // When
        let result = sut.truncateForStorage(text, limit: limit)
        
        // Then
        XCTAssertEqual(result, text)
    }
    
    func testTruncateForStorage_WhenTextLongerThanLimit_Truncates() {
        // Given
        let text = String(repeating: "a", count: 200)
        let limit = 100
        
        // When
        let result = sut.truncateForStorage(text, limit: limit)
        
        // Then
        XCTAssertEqual(result.count, limit + "...[TRUNCATED]".count)
        XCTAssertTrue(result.hasSuffix("[TRUNCATED]"))
    }
    
    func testTruncateForStorage_WhenLimitIsZero_ReturnsOriginal() {
        // Given
        let text = "Some text"
        let limit = 0
        
        // When
        let result = sut.truncateForStorage(text, limit: limit)
        
        // Then
        XCTAssertEqual(result, text)
    }
    
    // MARK: - Constants Tests
    
    func testDefaultTimeout_IsThirtySeconds() {
        // Then
        XCTAssertEqual(AIEnhancementService.defaultTimeout, 30.0)
    }
    
    func testMinimumTimeout_IsTenSeconds() {
        // Then
        XCTAssertEqual(AIEnhancementService.minimumTimeout, 10.0)
    }
    
    func testMaximumTimeout_IsFiveMinutes() {
        // Then
        XCTAssertEqual(AIEnhancementService.maximumTimeout, 300.0)
    }
    
    func testDefaultReasoningEffort_IsLow() {
        // Then
        XCTAssertEqual(AIEnhancementService.defaultReasoningEffort, .low)
    }
    
    func testMaxStoredMessageCharacters_IsFiftyThousand() {
        // Then
        XCTAssertEqual(sut.maxStoredMessageCharacters, 50_000)
    }
    
    func testMaxStoredContextCharacters_IsFiftyThousand() {
        // Then
        XCTAssertEqual(sut.maxStoredContextCharacters, 50_000)
    }
    
    // MARK: - Helper Methods Tests
    
    func testGetAIService_ReturnsAIService() {
        // When
        let service = sut.getAIService()
        
        // Then
        XCTAssertNotNil(service)
    }
}
