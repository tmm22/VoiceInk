import SwiftData
import XCTest
@testable import VoiceInk

@available(macOS 14.0, *)
@MainActor
final class WordReplacementServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WordReplacement.self, configurations: configuration)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testPunctuationHeavyTermsUseBoundaries() throws {
        try insert(original: "C++", replacement: "Cpp")

        let result = WordReplacementService.shared.applyReplacements(
            to: "C++ works; C++17 does not.",
            using: context
        )

        XCTAssertEqual(result, "Cpp works; C++17 does not.")
    }

    func testCommaSeparatedVariantsPreferLongestMatch() throws {
        try insert(original: "new, new york", replacement: "NY")

        let result = WordReplacementService.shared.applyReplacements(
            to: "new york and new",
            using: context
        )

        XCTAssertEqual(result, "NY and NY")
    }

    func testStandaloneWordsDoNotReplaceInsideAlphanumericText() throws {
        try insert(original: "app", replacement: "application")

        let result = WordReplacementService.shared.applyReplacements(
            to: "happy app app2 2app app.",
            using: context
        )

        XCTAssertEqual(result, "happy application app2 2app application.")
    }

    private func insert(original: String, replacement: String) throws {
        context.insert(WordReplacement(originalText: original, replacementText: replacement))
        try context.save()
    }
}
