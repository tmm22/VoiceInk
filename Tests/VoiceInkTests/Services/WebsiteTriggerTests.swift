import XCTest
@testable import VoiceInk

@MainActor
final class WebsiteTriggerTests: XCTestCase {
    func testMatchingUsesTheHostAndPathSegments() throws {
        let target = try XCTUnwrap(ModeManager.target(ofBrowserURL: "https://mail.example.com:8443/inbox/new?q=other.org"))
        XCTAssertTrue(ModeManager.trigger("example.com:8443/inbox", matches: target))
        XCTAssertFalse(ModeManager.trigger("example.com:443/inbox", matches: target))
        XCTAssertFalse(ModeManager.trigger("example.com/in", matches: target))
        XCTAssertFalse(ModeManager.trigger("other.org", matches: target))
        XCTAssertFalse(ModeManager.trigger("ample.com", matches: target))
    }
}
