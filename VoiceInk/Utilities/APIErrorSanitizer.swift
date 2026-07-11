import Foundation

/// Produces user-safe API errors without exposing provider response bodies.
enum APIErrorSanitizer {
    static func statusMessage(statusCode: Int) -> String {
        String(
            format: NSLocalizedString(
                "The service request failed with status code %d.",
                comment: "Generic API failure containing only the HTTP status code"
            ),
            statusCode
        )
    }
}
