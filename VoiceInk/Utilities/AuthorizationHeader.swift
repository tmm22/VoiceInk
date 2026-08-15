import Foundation

/// A structure representing an authorization header for network requests.
struct AuthorizationHeader {
    /// The HTTP header field name (e.g., "Authorization", "xi-api-key").
    let header: String
    
    /// The value for the header field.
    let value: String
    
    /// Indicates whether the credential used was provided by a managed provisioning profile.
    let usedManagedCredential: Bool
}
