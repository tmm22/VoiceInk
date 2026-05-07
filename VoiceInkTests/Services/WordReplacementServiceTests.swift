import XCTest
@testable import VoiceInk

@available(macOS 14.0, *)
@MainActor
final class WordReplacementServiceTests: XCTestCase {
    private var originalQuickRulesEnabled = false
    private var originalWordReplacements: [String: String] = [:]

    override func setUp() async throws {
        try await super.setUp()
        originalQuickRulesEnabled = AppSettings.QuickRules.isEnabled
        originalWordReplacements = AppSettings.Dictionary.wordReplacements
        AppSettings.QuickRules.isEnabled = false
        AppSettings.Dictionary.wordReplacements = [:]
    }

    override func tearDown() async throws {
        AppSettings.Dictionary.wordReplacements = originalWordReplacements
        AppSettings.QuickRules.isEnabled = originalQuickRulesEnabled
        try await super.tearDown()
    }

    func testPunctuationHeavyTermsUseBoundaries() {
        AppSettings.Dictionary.wordReplacements = [
            "C++": "Cpp"
        ]

        let result = WordReplacementService.shared.applyReplacements(to: "C++ works; C++17 does not.")

        XCTAssertEqual(result, "Cpp works; C++17 does not.")
    }

    func testCommaSeparatedVariantsPreferLongestMatch() {
        AppSettings.Dictionary.wordReplacements = [
            "new, new york": "NY"
        ]

        let result = WordReplacementService.shared.applyReplacements(to: "new york and new")

        XCTAssertEqual(result, "NY and NY")
    }

    func testStandaloneWordsDoNotReplaceInsideAlphanumericText() {
        AppSettings.Dictionary.wordReplacements = [
            "app": "application"
        ]

        let result = WordReplacementService.shared.applyReplacements(to: "happy app app2 2app app.")

        XCTAssertEqual(result, "happy application app2 2app application.")
    }
}
