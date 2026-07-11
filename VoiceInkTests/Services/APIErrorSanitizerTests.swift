import XCTest
@testable import VoiceInk

final class APIErrorSanitizerTests: XCTestCase {
    func testStatusMessageContainsStatusCodeWithoutProviderContent() {
        let message = APIErrorSanitizer.statusMessage(statusCode: 401)

        XCTAssertTrue(message.contains("401"))
        XCTAssertFalse(message.contains("api_key"))
        XCTAssertFalse(message.contains("Bearer"))
    }
}
