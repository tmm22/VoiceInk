import Foundation
import Security

/// Legacy TTS-workspace Keychain facade.
///
/// This is a thin forwarding shim over `KeychainService` using the login-keychain namespace keyed
/// by the bundle identifier, which is where the TTS providers' API keys have always been stored.
/// New code should use `KeychainService` directly; this type only exists so existing secrets keep
/// resolving under their original `kSecAttrService` string.
class KeychainManager {
    // MARK: - Properties
    static let shared = KeychainManager()
    private let store: KeychainService

    // MARK: - Initialization
    init(service: String = Bundle.main.bundleIdentifier ?? "com.tmm22.VoiceLinkCommunity",
         accessGroup: String? = nil) {
        store = KeychainService(namespace: .loginKeychain(service: service, accessGroup: accessGroup))
    }

    // MARK: - Error Types
    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedData
        case unhandledError(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unexpectedData:
                return "Unexpected data format in keychain"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Public Methods

    /// Save API key to keychain
    func saveAPIKey(_ key: String, for provider: String) throws {
        // Data(key.utf8) never fails for valid Swift strings
        let status = store.store(data: Data(key.utf8), forKey: provider, accessibility: .whenUnlocked)
        try Self.check(status)
    }

    /// Get API key from keychain
    func getAPIKey(for provider: String) -> String? {
        store.getString(forKey: provider)
    }

    /// Delete API key from keychain
    func deleteAPIKey(for provider: String) throws {
        let status = store.remove(forKey: provider)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Delete all API keys
    func deleteAllAPIKeys() throws {
        for provider in getAllProviders() {
            try deleteAPIKey(for: provider)
        }

        let status = store.removeAll()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Check if API key exists
    func hasAPIKey(for provider: String) -> Bool {
        guard let key = getAPIKey(for: provider), !key.isEmpty else {
            return false
        }
        return true
    }

    /// Check if a Keychain item exists without reading the secret value.
    func containsAPIKeyItem(for provider: String) -> Bool {
        store.exists(forKey: provider)
    }

    /// Get all stored providers
    func getAllProviders() -> [String] {
        store.allKeys()
    }

    // MARK: - Private Methods

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - Keychain Manager Extensions
extension KeychainManager {
    /// Migrate API keys from UserDefaults (for upgrades from older versions)
    func migrateFromUserDefaults() {
        let providers = ["ElevenLabs", "OpenAI", "Google", "AssemblyAI"]

        for provider in providers {
            let key = "apiKey_\(provider)"
            if let apiKey = AppSettings.string(forKey: key) {
                do {
                    try saveAPIKey(apiKey, for: provider)
                    // Remove from UserDefaults after successful migration
                    AppSettings.removeValue(forKey: key)
                } catch {
                    AppLogger.storage.error("Failed to migrate legacy API key for \(provider, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)")
                }
            }
        }
    }

    /// Validate API key format with provider-specific patterns
    static func isValidAPIKey(_ key: String, for provider: String? = nil) -> Bool {
        guard !key.isEmpty && key.count >= 20 && key.count <= 200 else {
            return false
        }

        // Provider-specific validation if specified
        if let provider = provider {
            switch provider {
            case "OpenAI":
                // OpenAI keys: sk-proj-xxx or sk-xxx format (48-51 chars after prefix)
                return key.hasPrefix("sk-") && key.count >= 43
            case "ElevenLabs":
                // ElevenLabs keys: 32+ alphanumeric characters
                return key.count >= 32 && key.range(of: "^[a-zA-Z0-9]{32,}$", options: .regularExpression) != nil
            case "Google":
                // Google API keys: 39 characters, alphanumeric with dashes/underscores
                return key.count >= 30 && key.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil
            default:
                break
            }
        }

        // Generic validation for unknown providers
        return true
    }

    /// Get formatted provider name for display
    static func formattedProviderName(_ provider: String) -> String {
        switch provider {
        case "ElevenLabs":
            return "ElevenLabs"
        case "OpenAI":
            return "OpenAI"
        case "Google":
            return "Google Cloud"
        default:
            return provider
        }
    }
}

// MARK: - Secure String Extension
extension String {
    /// Create a masked version of the API key for display
    var maskedAPIKey: String {
        guard count > 8 else {
            return String(repeating: "•", count: count)
        }

        let prefixCount = 4
        let suffixCount = 4
        let prefix = self.prefix(prefixCount)
        let suffix = self.suffix(suffixCount)
        let maskedMiddle = String(repeating: "•", count: count - prefixCount - suffixCount)

        return "\(prefix)\(maskedMiddle)\(suffix)"
    }

    /// Check if string looks like an API key
    var looksLikeAPIKey: Bool {
        // Check for common API key patterns
        let patterns = [
            "^sk-[a-zA-Z0-9]{48}$",  // OpenAI pattern
            "^[a-zA-Z0-9]{32,}$",     // Generic alphanumeric
            "^[a-zA-Z0-9-_]{20,}$"    // With dashes and underscores
        ]

        for pattern in patterns {
            if self.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
