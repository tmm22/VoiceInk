import Foundation

enum SecureEndpointValidator {
    /// Remote endpoints must use TLS. Plain HTTP is accepted only for an on-device loopback service.
    static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host != nil
        case "http":
            guard let host = url.host?.lowercased() else { return false }
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        default:
            return false
        }
    }

    static func isAllowed(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return isAllowed(url)
    }
}
