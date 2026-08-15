import XCTest
@testable import VoiceInk

@available(macOS 14.0, *)
final class AIProviderURLValidationTests: XCTestCase {
    func testHTTPSURLIsAccepted() {
        XCTAssertTrue(SecureEndpointValidator.isAllowed("https://api.example.com/v1/chat/completions"))
    }

    func testRemoteHTTPURLIsRejected() {
        XCTAssertFalse(SecureEndpointValidator.isAllowed("http://api.example.com/v1/chat/completions"))
    }

    func testLoopbackHTTPURLsAreAccepted() {
        XCTAssertTrue(SecureEndpointValidator.isAllowed("http://localhost:11434/api/chat"))
        XCTAssertTrue(SecureEndpointValidator.isAllowed("http://127.0.0.1:11434/api/chat"))
        XCTAssertTrue(SecureEndpointValidator.isAllowed("http://[::1]:11434/api/chat"))
    }

    func testLookalikeAndMalformedURLsAreRejected() {
        XCTAssertFalse(SecureEndpointValidator.isAllowed("http://localhost.example.com/v1"))
        XCTAssertFalse(SecureEndpointValidator.isAllowed("not a url"))
        XCTAssertFalse(SecureEndpointValidator.isAllowed("file:///tmp/provider"))
    }
}
