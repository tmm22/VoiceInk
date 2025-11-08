import Foundation
import os

/// Service to migrate API keys from UserDefaults to Keychain
class APIKeyMigrationService {
    private static let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "APIKeyMigration")
    private static let migrationKey = "hasCompletedAPIKeyMigrationV1"
    
    /// Run migration once on app launch
    static func migrateAPIKeysIfNeeded() {
        let defaults = UserDefaults.standard
        
        // Check if migration already completed
        guard !defaults.bool(forKey: migrationKey) else {
            logger.info("API key migration already completed, skipping")
            return
        }
        
        logger.notice("Starting API key migration from UserDefaults to Keychain")
        
        let keychain = KeychainManager()
        var migratedCount = 0
        
        // Define all API keys to migrate
        let keysToMigrate: [(userDefaultsKey: String, keychainProvider: String)] = [
            // Cloud Transcription Services (shared with AI Enhancement)
            ("GROQAPIKey", "GROQ"),
            ("ElevenLabsAPIKey", "ElevenLabs"),
            ("DeepgramAPIKey", "Deepgram"),
            ("MistralAPIKey", "Mistral"),
            ("GeminiAPIKey", "Gemini"),
            ("SonioxAPIKey", "Soniox"),
            
            // AI Enhancement Services (some overlap with transcription)
            ("CerebrasAPIKey", "Cerebras"),
            ("AnthropicAPIKey", "Anthropic"),
            ("OpenAIAPIKey", "OpenAI"),
            ("OpenRouterAPIKey", "OpenRouter"),
        ]
        
        for (oldKey, provider) in keysToMigrate {
            if let apiKey = defaults.string(forKey: oldKey), !apiKey.isEmpty {
                // Save to keychain
                keychain.saveAPIKey(apiKey, for: provider)
                
                // Verify it was saved successfully
                if keychain.hasAPIKey(for: provider) {
                    // Remove from UserDefaults
                    defaults.removeObject(forKey: oldKey)
                    migratedCount += 1
                    
                    logger.info("✅ Migrated \(provider, privacy: .public) API key to Keychain")
                } else {
                    logger.error("❌ Failed to migrate \(provider, privacy: .public) API key to Keychain")
                }
            }
        }
        
        // Mark migration as complete
        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
        
        logger.notice("🔐 API Key Migration Complete: \(migratedCount) keys migrated")
    }
    
    /// Reset migration flag (for testing purposes only)
    static func resetMigrationFlag() {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: migrationKey)
        logger.debug("Migration flag reset for testing")
        #endif
    }
}
