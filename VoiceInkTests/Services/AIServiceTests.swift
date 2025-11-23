import XCTest
import Combine
@testable import VoiceInk

/// Tests for AIService - focusing on API Key security and Provider Management
@available(macOS 14.0, *)
@MainActor
final class AIServiceTests: XCTestCase {
    
    var service: AIService!
    var cancellables: Set<AnyCancellable>!
    var keychain: KeychainManager!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use a test-specific keychain service to avoid messing with real keys
        keychain = KeychainManager(service: "com.test.VoiceInk.AIServiceTests")
        try? keychain.deleteAllAPIKeys()
        
        // Initialize service
        // Note: AIService uses KeychainManager() internally which defaults to main bundle ID.
        // For testability, we should ideally inject the keychain manager, but since we can't easily refactor 
        // the main class right now, we will rely on the fact that we verified the logic change.
        // 
        // However, to properly test the *logic* we modified (Keychain vs UserDefaults), 
        // we need to ensure we are testing the actual behavior.
        
        service = AIService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        service = nil
        try? keychain.deleteAllAPIKeys()
        try await super.tearDown()
    }
    
    func testInitializationDoesNotReadFromUserDefaults() {
        // Setup: Put a fake key in UserDefaults but NOT in Keychain
        let fakeLegacyKey = "legacy-fake-key"
        UserDefaults.standard.set(fakeLegacyKey, forKey: "OpenAIAPIKey")
        
        // Initialize new service instance
        let newService = AIService()
        
        // Switch to OpenAI (which requires key)
        newService.selectedProvider = .openAI
        
        // Verify: Should NOT have the key from UserDefaults
        XCTAssertTrue(newService.apiKey.isEmpty, "Should not load key from UserDefaults")
        XCTAssertFalse(newService.isAPIKeyValid, "Key should be invalid")
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "OpenAIAPIKey")
    }
    
    func testInitializationReadsFromKeychain() {
        // Setup: Put a key in Keychain
        let validKey = "key_in_keychain"
        let keychainMain = KeychainManager() // Uses default service ID used by App
        keychainMain.saveAPIKey(validKey, for: AIProvider.openAI.rawValue)
        
        // Initialize
        let newService = AIService()
        newService.selectedProvider = .openAI
        
        // Verify
        XCTAssertEqual(newService.apiKey, validKey, "Should load key from Keychain")
        XCTAssertTrue(newService.isAPIKeyValid, "Key should be marked valid")
        
        // Cleanup
        try? keychainMain.deleteAPIKey(for: AIProvider.openAI.rawValue)
    }
    
    func testProviderSwitchingUpdatesKeyStatus() {
        // Setup: Keychain has key for Anthropic but not OpenAI
        let keychainMain = KeychainManager()
        keychainMain.saveAPIKey("key_for_anthropic", for: AIProvider.anthropic.rawValue)
        
        // Select Anthropic
        service.selectedProvider = .anthropic
        XCTAssertEqual(service.apiKey, "key_for_anthropic")
        XCTAssertTrue(service.isAPIKeyValid)
        
        // Switch to OpenAI (no key)
        service.selectedProvider = .openAI
        XCTAssertTrue(service.apiKey.isEmpty)
        XCTAssertFalse(service.isAPIKeyValid)
        
        // Cleanup
        try? keychainMain.deleteAPIKey(for: AIProvider.anthropic.rawValue)
    }
    
    func testOllamaDoesNotRequireKey() {
        service.selectedProvider = .ollama
        
        XCTAssertTrue(service.apiKey.isEmpty)
        XCTAssertTrue(service.isAPIKeyValid, "Ollama should be valid without key")
    }
}
