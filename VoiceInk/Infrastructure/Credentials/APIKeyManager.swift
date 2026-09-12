import Foundation
import os

/// Manages API keys using secure Keychain storage.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "APIKeyManager")
    private let keychain = KeychainService.shared

    /// Provider to Keychain identifier mapping.
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "speechmatics": "speechmaticsAPIKey",
        "assemblyai": "assemblyAIAPIKey",
        "xai": "xaiAPIKey",
        "cartesia": "cartesiaAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey",
    ]

    private init() {}

    // MARK: - Secret Storage Policy

    /// API keys are bearer credentials: they stay on this device (no iCloud
    /// Keychain sync) and are readable only after first unlock, matching the
    /// posture the license secrets already use.
    private let accessibility = KeychainService.Accessibility.afterFirstUnlockThisDeviceOnly

    private func saveSecret(_ value: String, forKey identifier: String) -> Bool {
        let saved = keychain.save(value, forKey: identifier, syncable: false, accessibility: accessibility)
        // A user-initiated write is the right moment to retire the shared iCloud
        // copy: the new value lives device-locally here, and the old synced value
        // is stale after this write anyway. This deletion does propagate to every
        // device, so a Mac that has not yet read (and locally migrated) this key
        // loses the synced copy and needs it re-entered — but that only happens
        // on an explicit user save, not on a background read.
        if saved { keychain.delete(forKey: identifier, syncable: true) }
        return saved
    }

    /// Reads a secret, copying any legacy iCloud-synced value into
    /// device-local, after-first-unlock storage the first time it is seen. The
    /// synced copy is left in place so other devices can migrate it too; it is
    /// removed only when the user next saves this key.
    private func readSecret(forKey identifier: String) -> String? {
        if let local = keychain.getString(forKey: identifier, syncable: false) {
            return local
        }
        guard let legacy = keychain.getString(forKey: identifier, syncable: true) else { return nil }
        if keychain.save(legacy, forKey: identifier, syncable: false, accessibility: accessibility) {
            logger.info("Copied synced keychain secret to device-local storage: \(identifier, privacy: .public)")
        }
        return legacy
    }

    private func deleteSecret(forKey identifier: String) -> Bool {
        let localDeleted = keychain.delete(forKey: identifier, syncable: false)
        let syncedDeleted = keychain.delete(forKey: identifier, syncable: true)
        return localDeleted && syncedDeleted
    }

    private func secretExists(forKey identifier: String) -> Bool {
        keychain.exists(forKey: identifier, syncable: false) || keychain.exists(forKey: identifier, syncable: true)
    }

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = saveSecret(key, forKey: keyIdentifier)
        if success {
            logger.info(
                "Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)"
            )
        }
        return success
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return readSecret(forKey: keyIdentifier)
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = deleteSecret(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return secretExists(forKey: keyIdentifier)
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = saveSecret(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        return readSecret(forKey: keyIdentifier)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = deleteSecret(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    // MARK: - Custom AI Provider API Keys

    @discardableResult
    func saveCustomAIProviderAPIKey(_ key: String, forProviderId providerId: UUID) -> Bool {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        let success = saveSecret(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom AI provider: \(providerId.uuidString, privacy: .public)")
        }
        return success
    }

    func getCustomAIProviderAPIKey(forProviderId providerId: UUID) -> String? {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        return readSecret(forKey: keyIdentifier)
    }

    @discardableResult
    func deleteCustomAIProviderAPIKey(forProviderId providerId: UUID) -> Bool {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        let success = deleteSecret(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom AI provider: \(providerId.uuidString, privacy: .public)")
        }
        return success
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

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }

    private func customAIProviderKeyIdentifier(for providerId: UUID) -> String {
        "customAIProvider_\(providerId.uuidString)_APIKey"
    }
}
