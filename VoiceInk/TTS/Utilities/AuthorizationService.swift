import Foundation

/// Service for providing authorization headers for TTS and AI services
@MainActor
class AuthorizationService {
    private let keychain: KeychainManager
    private let managedProvisioningClient: ManagedProvisioningClient

    init(
        keychain: KeychainManager = KeychainManager(),
        managedProvisioningClient: ManagedProvisioningClient? = nil
    ) {
        self.keychain = keychain
        self.managedProvisioningClient = managedProvisioningClient ?? .shared
    }

    /// Get authorization header for a provider
    /// - Parameters:
    ///   - provider: The provider name (e.g., "OpenAI", "ElevenLabs")
    ///   - headerType: The type of authorization header needed
    /// - Returns: AuthorizationHeader with the appropriate credentials
    func authorizationHeader(for provider: String, headerType: HeaderType) async throws -> AuthorizationHeader {
        // Try Keychain first
        if let key = keychain.getAPIKey(for: provider), !key.isEmpty {
            let (header, value) = headerType.authorizationPair(for: key)
            return AuthorizationHeader(header: header, value: value, usedManagedCredential: false)
        }

        // Fall back to managed credentials
        guard let providerType = providerType(for: provider) else {
            throw AuthorizationError.unsupportedProvider(provider)
        }

        let credential = try await managedProvisioningClient.credential(for: providerType)
        guard let credential = credential else {
            throw AuthorizationError.noManagedCredential(provider)
        }

        let (header, value) = headerType.authorizationPair(for: credential.token)
        return AuthorizationHeader(header: header, value: value, usedManagedCredential: true)
    }

    /// Whether managed provisioning is enabled and configured.
    var hasManagedProvisioningConfiguration: Bool {
        managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }

    /// Invalidate a managed credential if one was used and found to be unauthorized.
    func invalidateManagedCredential(for provider: Voice.ProviderType) {
        managedProvisioningClient.invalidateCredential(for: provider)
    }

    /// Convert string provider name to Voice.ProviderType
    private func providerType(for providerName: String) -> Voice.ProviderType? {
        switch providerName {
        case "ElevenLabs":
            return .elevenLabs
        case "OpenAI":
            return .openAI
        case "Google":
            return .google
        default:
            return nil
        }
    }
}

/// Defines different types of authorization headers used by various providers
enum HeaderType {
    /// Standard Bearer token authorization (most common)
    case bearer
    /// API key with custom header name
    case apiKey(header: String)
    /// Custom header with prefix
    case custom(header: String, prefix: String)

    func authorizationPair(for token: String) -> (header: String, value: String) {
        switch self {
        case .bearer:
            return ("Authorization", "Bearer \(token)")
        case .apiKey(let header):
            return (header, token)
        case .custom(let header, let prefix):
            return (header, "\(prefix)\(token)")
        }
    }
}

/// Convenience extension for common provider header types
extension HeaderType {
    static var openAI: HeaderType { .bearer }
    static var elevenLabs: HeaderType { .apiKey(header: "xi-api-key") }
    static var google: HeaderType { .apiKey(header: "X-Goog-Api-Key") }
}

/// Authorization-related errors
enum AuthorizationError: Error, LocalizedError {
    case unsupportedProvider(String)
    case noManagedCredential(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Provider '\(provider)' is not supported for managed credentials"
        case .noManagedCredential(let provider):
            return "No managed credential available for provider '\(provider)'"
        }
    }
}
