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

    func testRepeatedDictationsGetTheSameResultFromTheCachedPattern() throws {
        try insert(original: "voice ink, voiceink", replacement: "VoiceInk")

        let text = "Voice ink and voiceink, not voiceinks."
        let first = WordReplacementService.shared.applyReplacements(to: text, using: context)
        let second = WordReplacementService.shared.applyReplacements(to: text, using: context)

        XCTAssertEqual(first, "VoiceInk and VoiceInk, not voiceinks.")
        XCTAssertEqual(second, first)
    }

    func testEditedReplacementTextIsUsedWithAnAlreadyCompiledTrigger() throws {
        let replacement = WordReplacement(originalText: "teh", replacementText: "the")
        context.insert(replacement)
        try context.save()
        XCTAssertEqual(WordReplacementService.shared.applyReplacements(to: "teh end", using: context), "the end")

        replacement.replacementText = "THE"
        try context.save()

        XCTAssertEqual(WordReplacementService.shared.applyReplacements(to: "teh end", using: context), "THE end")
    }

    func testEachTriggerIsCompiledOnce() throws {
        let service = WordReplacementService.shared
        let trigger = "compile-once-\(UUID().uuidString)"

        let first = try XCTUnwrap(service.boundaryRegex(for: trigger))
        let second = try XCTUnwrap(service.boundaryRegex(for: trigger))

        XCTAssertTrue(first === second)
        XCTAssertTrue(first.options.contains(.caseInsensitive))
    }

    func testDifferentlyEncodedTriggersKeepSeparatePatterns() throws {
        let service = WordReplacementService.shared
        let suffix = UUID().uuidString
        // Canonically equivalent, so equal as Swift strings, but encoded differently.
        let precomposed = "caf\u{00E9}-\(suffix)"
        let decomposed = "cafe\u{0301}-\(suffix)"
        XCTAssertEqual(precomposed, decomposed)

        let first = try XCTUnwrap(service.boundaryRegex(for: precomposed))
        let second = try XCTUnwrap(service.boundaryRegex(for: decomposed))

        XCTAssertFalse(first === second)
        // Swift compares strings by canonical equivalence, so compare the encoded forms.
        XCTAssertNotEqual(Array(first.pattern.utf16), Array(second.pattern.utf16))
    }

    private func insert(original: String, replacement: String) throws {
        context.insert(WordReplacement(originalText: original, replacementText: replacement))
        try context.save()
    }
}
