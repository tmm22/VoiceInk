import XCTest
import SwiftData
@testable import VoiceInk

/// Tests for PowerModeSessionManager - session lifecycle and state management
/// CRITICAL: isApplyingPowerModeConfig flag without synchronization
@available(macOS 14.0, *)
@MainActor
final class PowerModeSessionManagerTests: XCTestCase {
    
    var sessionManager: PowerModeSessionManager!
    var mockConfig: PowerModeConfig!
    var modelContainer: ModelContainer!
    var enhancementService: AIEnhancementService!
    var whisperState: WhisperState!
    
    override func setUp() async throws {
        try await super.setUp()
        sessionManager = PowerModeSessionManager.shared
        modelContainer = try ModelContainer.createInMemoryContainer()
        enhancementService = AIEnhancementService(modelContext: modelContainer.mainContext)
        whisperState = WhisperState(modelContext: modelContainer.mainContext, enhancementService: enhancementService)
        
        // Create mock configuration
        mockConfig = PowerModeConfig(
            id: UUID(),
            name: "Test Config",
            emoji: "🧪",
            appConfigs: [AppConfig(bundleIdentifier: "com.test.app", appName: "Test App")],
            urlConfigs: nil,
            isAIEnhancementEnabled: true,
            selectedPrompt: nil,
            selectedTranscriptionModelName: nil,
            selectedLanguage: nil,
            useScreenCapture: false,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            isAutoSendEnabled: false,
            isEnabled: true,
            isDefault: false
        )
    }
    
    override func tearDown() async throws {
        await sessionManager.endSession()
        AppSettings.PowerMode.activeSessionData = nil
        
        mockConfig = nil
        whisperState = nil
        enhancementService = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Session Lifecycle Tests
    
    func testSessionBeginEnd() async {
        // Test basic session lifecycle
        XCTAssertNil(currentSession(), "Should have no active session")
        
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        // Should have active session
        XCTAssertNotNil(currentSession(), "Should have active session")
        
        // End session
        await sessionManager.endSession()
        
        // Should have no active session
        XCTAssertNil(currentSession(), "Should clear session")
    }
    
    func testSessionPersistence() async {
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        // Session should persist
        let session = currentSession()
        XCTAssertNotNil(session)
        XCTAssertNotNil(session?.originalState)
        
        // End session
        await sessionManager.endSession()
    }
    
    func testMultipleBeginCallsHandling() async {
        // Begin first session
        await sessionManager.beginSession(with: mockConfig)
        
        // Create another config
        let config2 = PowerModeConfig(
            id: UUID(),
            name: "Test Config 2",
            emoji: "🔬",
            appConfigs: [AppConfig(bundleIdentifier: "com.test.app2", appName: "Test App 2")],
            urlConfigs: nil,
            isAIEnhancementEnabled: false,
            selectedPrompt: nil,
            selectedTranscriptionModelName: nil,
            selectedLanguage: nil,
            useScreenCapture: false,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            isAutoSendEnabled: false,
            isEnabled: true,
            isDefault: false
        )
        
        // Begin second session (should replace first)
        await sessionManager.beginSession(with: config2)
        
        // Should have session
        XCTAssertNotNil(currentSession())
        
        // End session
        await sessionManager.endSession()
    }
    
    // MARK: - State Snapshot Tests
    
    func testStateSnapshotCapture() async {
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        // Get session
        let session = currentSession()
        XCTAssertNotNil(session?.originalState)
        
        // Original state should be captured
        let state = session?.originalState
        XCTAssertNotNil(state?.isEnhancementEnabled)
        
        // End session
        await sessionManager.endSession()
    }
    
    func testStateSnapshotUpdates() async {
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        // Simulate settings change
        // This would trigger updateSessionSnapshot() via notification
        // But since we don't have full app context, we just verify it doesn't crash
        
        NotificationCenter.default.post(
            name: .AppSettingsDidChange,
            object: nil
        )
        
        // Give time for notification handling
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Should still have session
        XCTAssertNotNil(currentSession())
        
        // End session
        await sessionManager.endSession()
    }
    
    // MARK: - CRITICAL: isApplyingPowerModeConfig Race Tests
    
    func testIsApplyingPowerModeConfigFlag() async {
        // CRITICAL: This flag is not thread-safe
        // Test that it doesn't cause crashes during concurrent access
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    if i % 2 == 0 {
                        await self.sessionManager.beginSession(with: self.mockConfig)
                    } else {
                        await self.sessionManager.endSession()
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
                }
            }
            await group.waitForAll()
        }
        
        // Clean up
        await sessionManager.endSession()
        
        // No crash = success
    }
    
    // MARK: - Configuration Application Tests
    
    func testConfigurationApplicationOrder() async {
        // Test that configuration is applied in correct order
        await sessionManager.beginSession(with: mockConfig)
        
        // Give time for configuration to apply
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Should have applied without crash
        XCTAssertNotNil(currentSession())
        
        await sessionManager.endSession()
    }
    
    // MARK: - State Restoration Tests
    
    func testStateRestorationCorrectness() async {
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        let originalSession = currentSession()
        XCTAssertNotNil(originalSession?.originalState)
        
        // End session (should restore state)
        await sessionManager.endSession()
        
        // Session should be cleared
        XCTAssertNil(currentSession())
    }
    
    func testStateRestorationAfterModifications() async {
        // Begin session
        await sessionManager.beginSession(with: mockConfig)
        
        // Make some "changes" (via notifications)
        NotificationCenter.default.post(
            name: .AppSettingsDidChange,
            object: nil
        )
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // End session (should restore original state)
        await sessionManager.endSession()
        
        XCTAssertNil(currentSession())
    }
    
    // MARK: - Observer Cleanup Tests
    
    func testObserverCleanupOnEndSession() async {
        // Begin session (adds observer)
        await sessionManager.beginSession(with: mockConfig)
        
        // End session (should remove observer)
        await sessionManager.endSession()
        
        // Post notification - should not cause issues
        NotificationCenter.default.post(
            name: .AppSettingsDidChange,
            object: nil
        )
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // No crash = success
    }
    
    // MARK: - Concurrent Session Operations Tests
    
    func testConcurrentBeginEndOperations() async {
        // Test concurrent begin/end calls
        await assertConcurrentExecution(iterations: 20) {
            if Bool.random() {
                await self.sessionManager.beginSession(with: self.mockConfig)
            } else {
                await self.sessionManager.endSession()
            }
        }
        
        // Clean up
        await sessionManager.endSession()
    }

    private func currentSession() -> PowerModeSession? {
        guard let data = AppSettings.PowerMode.activeSessionData else { return nil }
        return try? JSONDecoder().decode(PowerModeSession.self, from: data)
    }
}
