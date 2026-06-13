import XCTest
@testable import VoiceInk

/// Tests for AIProvider.validateSecureURL - HTTPS enforcement for credentialed endpoints.
@available(macOS 14.0, *)
final class AIProviderURLValidationTests: XCTestCase {

    func testHTTPSURLIsAccepted() throws {
        let url = try AIProvider.validateSecureURL("https://api.example.com/v1/chat/completions")
        XCTAssertEqual(url.scheme, "https")
    }

    func testHTTPURLIsRejected() {
        XCTAssertThrowsError(try AIProvider.validateSecureURL("http://api.example.com/v1/chat/completions")) { error in
            guard case AIServiceURLError.insecureURL = error else {
                return XCTFail("Expected insecureURL error, got \(error)")
            }
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }

    func testHTTPLocalhostIsAllowedWhenLocalhostAllowed() throws {
        // The Ollama provider intentionally allows local http endpoints
        let url = try AIProvider.validateSecureURL("http://localhost:11434/api/chat", allowLocalhost: true)
        XCTAssertEqual(url.host, "localhost")
    }

    func testHTTPLocalhostIsRejectedWhenLocalhostNotAllowed() {
        XCTAssertThrowsError(try AIProvider.validateSecureURL("http://localhost:11434/api/chat")) { error in
            guard case AIServiceURLError.insecureURL = error else {
                return XCTFail("Expected insecureURL error, got \(error)")
            }
        }
    }

    func testHTTPRemoteHostIsRejectedEvenWhenLocalhostAllowed() {
        XCTAssertThrowsError(try AIProvider.validateSecureURL("http://evil.example.com/v1", allowLocalhost: true)) { error in
            guard case AIServiceURLError.insecureURL = error else {
                return XCTFail("Expected insecureURL error, got \(error)")
            }
        }
    }

    func testUnparseableURLIsRejected() {
        XCTAssertThrowsError(try AIProvider.validateSecureURL("not a url")) { error in
            XCTAssertTrue(error is AIServiceURLError)
        }
    }
}
