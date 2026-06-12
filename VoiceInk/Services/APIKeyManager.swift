import Foundation
import os

/// Abstraction over Keychain storage so API key handling can be unit tested.
protocol KeychainStoring: AnyObject {
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool
    func getString(forKey key: String) -> String?
    @discardableResult
    func delete(forKey key: String) -> Bool
}

extension KeychainService: KeychainStoring {
    func save(_ value: String, forKey key: String) -> Bool {
        save(value, forKey: key, syncable: true)
    }

    func getString(forKey key: String) -> String? {
        getString(forKey: key, syncable: true)
    }

    func delete(forKey key: String) -> Bool {
        delete(forKey: key, syncable: true)
    }
}

/// Manages API keys using secure Keychain storage with automatic migration from UserDefaults.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "APIKeyManager")
    private let keychain: any KeychainStoring
    private let userDefaults: UserDefaults

    /// v3: re-runs migration once for users whose v2 flag was set even though some
    /// Keychain saves failed (the old code marked migration complete unconditionally,
    /// which would strand legacy plaintext keys now that runtime fallback is removed).
    private let migrationCompletedKey = "APIKeyMigrationToKeychainCompleted_v3"

    /// Provider to Keychain identifier mapping (iOS compatible for iCloud sync).
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey"
    ]

    /// Legacy UserDefaults to Keychain key mapping for migration.
    private static let userDefaultsToKeychainMapping: [String: String] = [
        "GROQAPIKey": "groqAPIKey",
        "DeepgramAPIKey": "deepgramAPIKey",
        "CerebrasAPIKey": "cerebrasAPIKey",
        "GeminiAPIKey": "geminiAPIKey",
        "MistralAPIKey": "mistralAPIKey",
        "ElevenLabsAPIKey": "elevenLabsAPIKey",
        "SonioxAPIKey": "sonioxAPIKey",
        "OpenAIAPIKey": "openAIAPIKey",
        "AnthropicAPIKey": "anthropicAPIKey",
        "OpenRouterAPIKey": "openRouterAPIKey"
    ]

    /// Internal initializer allows dependency injection for unit tests.
    /// Production code must use `APIKeyManager.shared`.
    init(keychain: any KeychainStoring = KeychainService.shared, userDefaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)")
            // Clean up any remaining UserDefaults entries (both old and new format)
            cleanupUserDefaultsForProvider(provider)
        }
        return success
    }

    /// Retrieves an API key for a provider. Retrieval is Keychain-only;
    /// legacy UserDefaults keys are handled exclusively by the migration path.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)

        if let key = keychain.getString(forKey: keyIdentifier), !key.isEmpty {
            return key
        }

        return nil
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.delete(forKey: keyIdentifier)
        cleanupUserDefaultsForProvider(provider)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        return getAPIKey(forProvider: provider) != nil
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        return keychain.getString(forKey: keyIdentifier)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model")
        }
        return success
    }

    // MARK: - Migration

    /// Migrates API keys from UserDefaults to Keychain on first run.
    /// The completion flag is only set when every key migrated successfully,
    /// so failed keys remain in UserDefaults and are retried on the next launch.
    private func migrateFromUserDefaultsIfNeeded() {
        if userDefaults.bool(forKey: migrationCompletedKey) {
            return
        }

        logger.info("Starting API key migration")
        var migratedCount = 0
        var allSucceeded = true

        for (oldKey, newKey) in Self.userDefaultsToKeychainMapping {
            if let value = userDefaults.string(forKey: oldKey), !value.isEmpty {
                // The Keychain is the source of truth: if a (possibly newer) value
                // already exists there, keep it and just drop the legacy plaintext copy.
                if let existing = keychain.getString(forKey: newKey), !existing.isEmpty {
                    userDefaults.removeObject(forKey: oldKey)
                    continue
                }
                if keychain.save(value, forKey: newKey) {
                    // Only remove the legacy key after the Keychain save succeeded
                    userDefaults.removeObject(forKey: oldKey)
                    migratedCount += 1
                } else {
                    allSucceeded = false
                    logger.error("Failed to migrate \(oldKey, privacy: .public); will retry on next launch")
                }
            }
        }

        if !migrateCustomModelAPIKeys() {
            allSucceeded = false
        }

        if allSucceeded {
            userDefaults.set(true, forKey: migrationCompletedKey)
            logger.info("Migration completed. Migrated \(migratedCount, privacy: .public) API keys.")
        } else {
            logger.error("Migration incomplete (\(migratedCount, privacy: .public) keys migrated); will retry on next launch")
        }
    }

    /// Migrates custom model API keys from UserDefaults.
    /// - Returns: `true` when every Keychain save succeeded (or there was nothing to migrate).
    private func migrateCustomModelAPIKeys() -> Bool {
        guard let data = userDefaults.data(forKey: "customCloudModels") else {
            return true
        }

        struct LegacyCustomCloudModel: Codable {
            let id: UUID
            let apiKey: String
        }

        do {
            let legacyModels = try JSONDecoder().decode([LegacyCustomCloudModel].self, from: data)
            var allSucceeded = true
            for model in legacyModels where !model.apiKey.isEmpty {
                let keyIdentifier = customModelKeyIdentifier(for: model.id)
                // Keychain is the source of truth; never overwrite an existing value.
                if let existing = keychain.getString(forKey: keyIdentifier), !existing.isEmpty {
                    continue
                }
                if !keychain.save(model.apiKey, forKey: keyIdentifier) {
                    allSucceeded = false
                    logger.error("Failed to migrate custom model API key; will retry on next launch")
                }
            }
            // Note: the plaintext `customCloudModels` blob itself is rewritten without
            // embedded API keys by CustomModelManager.loadCustomModels() on its first
            // load, so the keys are stripped from disk as soon as custom models are used.
            return allSucceeded
        } catch {
            logger.error("Failed to decode legacy custom models: \(AppLogger.errorMetadata(error), privacy: .public)")
            // Decoding failures are permanent; retrying would fail identically,
            // so they do not block migration completion.
            return true
        }
    }

    // MARK: - Key Identifier Helpers

    /// Returns Keychain identifier for a provider (case-insensitive).
    private func keychainIdentifier(forProvider provider: String) -> String {
        let lowercased = provider.lowercased()
        if let mapped = Self.providerToKeychainKey[lowercased] {
            return mapped
        }
        return "\(lowercased)APIKey"
    }

    /// Returns old UserDefaults key for provider (pre-Keychain format).
    private func oldUserDefaultsKey(forProvider provider: String) -> String {
        switch provider.lowercased() {
        case "groq":
            return "GROQAPIKey"
        case "deepgram":
            return "DeepgramAPIKey"
        case "cerebras":
            return "CerebrasAPIKey"
        case "gemini":
            return "GeminiAPIKey"
        case "mistral":
            return "MistralAPIKey"
        case "elevenlabs":
            return "ElevenLabsAPIKey"
        case "soniox":
            return "SonioxAPIKey"
        case "openai":
            return "OpenAIAPIKey"
        case "anthropic":
            return "AnthropicAPIKey"
        case "openrouter":
            return "OpenRouterAPIKey"
        default:
            return "\(provider)APIKey"
        }
    }

    /// Cleans up UserDefaults entries for a provider.
    private func cleanupUserDefaultsForProvider(_ provider: String) {
        userDefaults.removeObject(forKey: oldUserDefaultsKey(forProvider: provider))
    }

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }
}
