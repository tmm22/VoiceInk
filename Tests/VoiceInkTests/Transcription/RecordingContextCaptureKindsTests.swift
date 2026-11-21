import XCTest
@testable import VoiceInk

extension ModeConfig {
    /// A mode for context-capture tests. Every context flag defaults to off so each test opts in.
    static func contextCaptureTestMode(
        aiEnhancement: Bool = true,
        enabled: Bool = true,
        provider: String? = AIProvider.openAI.rawValue,
        clipboard: Bool = false,
        selectedText: Bool = false,
        screen: Bool = false
    ) -> ModeConfig {
        ModeConfig(
            name: "Test",
            isAIEnhancementEnabled: aiEnhancement,
            useClipboardContext: clipboard,
            useSelectedTextContext: selectedText,
            useScreenCapture: screen,
            selectedAIProvider: provider,
            isEnabled: enabled
        )
    }
}

/// Which context kinds a recording captures must follow what an enabled mode can actually put in an
/// enhancement prompt, and nothing that a mode could consume may be skipped.
final class RecordingContextCaptureKindsTests: XCTestCase {
    private typealias Kinds = RecordingContextCaptureKinds

    private func needed(
        _ modes: [ModeConfig], canEnhance: Bool = true, smartPunctuation: Bool = false
    ) -> RecordingContextCaptureKinds {
        Kinds.needed(for: modes, canEnhance: canEnhance, pastesWithSmartPunctuation: smartPunctuation)
    }

    // MARK: - Kinds needed when a recording starts

    func testDictationOnlySetupCapturesOnlyTheClipboard() {
        let dictation = ModeConfig.contextCaptureTestMode(aiEnhancement: false, provider: nil)
        XCTAssertEqual(needed([dictation]), [.clipboard])
        XCTAssertEqual(needed([]), [.clipboard])
    }

    func testContextFlagsOnAModeWithoutAIEnhancementAreNotNeeded() {
        let mode = ModeConfig.contextCaptureTestMode(aiEnhancement: false, selectedText: true, screen: true)
        XCTAssertEqual(needed([mode]), [.clipboard])
    }

    func testEnabledAIModeNeedsExactlyTheKindsItUses() {
        XCTAssertEqual(needed([.contextCaptureTestMode(selectedText: true)]), [.clipboard, .selectedText])
        XCTAssertEqual(needed([.contextCaptureTestMode(screen: true)]), [.clipboard, .screen])
        XCTAssertEqual(needed([.contextCaptureTestMode(clipboard: true)]), [.clipboard])
    }

    func testEveryEnabledModeCountsNotOnlyTheFirst() {
        let modes = [
            ModeConfig.contextCaptureTestMode(aiEnhancement: false, provider: nil),
            ModeConfig.contextCaptureTestMode(selectedText: true),
            ModeConfig.contextCaptureTestMode(screen: true),
        ]
        XCTAssertEqual(needed(modes), .all)
    }

    func testDisabledModeIsIgnored() {
        let disabled = ModeConfig.contextCaptureTestMode(enabled: false, selectedText: true, screen: true)
        XCTAssertEqual(needed([disabled]), [.clipboard])
    }

    func testVoiceInkRefineModeNeverNeedsContext() {
        let refine = ModeConfig.contextCaptureTestMode(
            provider: AIProvider.voiceInkRefine.rawValue, clipboard: true, selectedText: true, screen: true)
        XCTAssertEqual(needed([refine]), [.clipboard])
    }

    func testMissingOrUnknownProviderIsTreatedAsAbleToConsumeContext() {
        let noProvider = ModeConfig.contextCaptureTestMode(provider: nil, selectedText: true, screen: true)
        XCTAssertEqual(needed([noProvider]), .all)

        let unknownProvider = ModeConfig.contextCaptureTestMode(provider: "Retired Provider", selectedText: true)
        XCTAssertEqual(needed([unknownProvider]), [.clipboard, .selectedText])
    }

    func testEveryNonRefineProviderCanConsumeContext() {
        for provider in AIProvider.allCases where provider != .voiceInkRefine {
            let mode = ModeConfig.contextCaptureTestMode(provider: provider.rawValue, selectedText: true, screen: true)
            XCTAssertEqual(needed([mode]), .all, "\(provider.rawValue)")
        }
    }

    func testRecordingThatCannotEnhanceNeedsNothing() {
        let mode = ModeConfig.contextCaptureTestMode(clipboard: true, selectedText: true, screen: true)
        XCTAssertEqual(needed([mode], canEnhance: false), [])
    }

    func testSmartPunctuationKeepsSelectedTextCaptureWhateverTheModesUse() {
        let dictation = ModeConfig.contextCaptureTestMode(aiEnhancement: false, provider: nil)
        XCTAssertEqual(needed([dictation], smartPunctuation: true), [.clipboard, .selectedText])
        XCTAssertEqual(needed([], canEnhance: false, smartPunctuation: true), [.selectedText])
        XCTAssertEqual(
            needed([.contextCaptureTestMode(screen: true)], smartPunctuation: true), .all,
            "Smart Punctuation adds to what the modes need")
    }

    // MARK: - Kinds that may still be captured after the start

    func testScreenIsAlwaysCapturableAfterStart() {
        for isRecording in [true, false] {
            for isUnchanged in [true, false] {
                let kinds = Kinds.screen.capturableAfterStart(
                    isRecording: isRecording, isFrontmostApplicationUnchanged: isUnchanged)
                XCTAssertEqual(kinds, [.screen])
            }
        }
    }

    func testSelectedTextIsCapturableAfterStartOnlyWhileRecordingInTheSameApplication() {
        let missing: RecordingContextCaptureKinds = [.selectedText, .screen]
        XCTAssertEqual(
            missing.capturableAfterStart(isRecording: true, isFrontmostApplicationUnchanged: true),
            [.selectedText, .screen])
        XCTAssertEqual(
            missing.capturableAfterStart(isRecording: false, isFrontmostApplicationUnchanged: true),
            [.screen], "A capture that can press Copy must not start once the result may be pasted")
        XCTAssertEqual(
            missing.capturableAfterStart(isRecording: true, isFrontmostApplicationUnchanged: false),
            [.screen], "Another application's selection is not this recording's context")
        XCTAssertEqual(
            Kinds.selectedText.capturableAfterStart(isRecording: false, isFrontmostApplicationUnchanged: false),
            [])
    }
}
