import XCTest
@testable import VoiceInk

@MainActor
final class FileTranscriptionSessionPromptTests: XCTestCase {
    func testSavedPromptChangesApplyToNewSessionsWithoutChangingPreparedSession() async throws {
        let defaults = UserDefaults.standard
        let savedPrompts = defaults.object(forKey: "CustomLanguagePrompts")
        defer {
            if let savedPrompts { defaults.set(savedPrompts, forKey: "CustomLanguagePrompts") }
            else { defaults.removeObject(forKey: "CustomLanguagePrompts") }
        }
        let service = CapturingPromptService()
        let model = WhisperModel(
            name: "test", displayName: "Test", size: "0", supportedLanguages: ["en": "English"],
            description: "", speed: 1, accuracy: 1, ramUsage: 0
        )
        let configuration = TranscriptionRuntimeConfiguration(
            mode: ModeConfig(name: "Test", isAIEnhancementEnabled: false),
            model: model, language: "en", isRealtimeEnabled: false
        )
        defaults.set(["en": "first session terminology"], forKey: "CustomLanguagePrompts")
        let first = FileTranscriptionSession(service: service)
        _ = try await first.prepare(configuration: configuration)

        defaults.set(["en": "new session terminology"], forKey: "CustomLanguagePrompts")
        let second = FileTranscriptionSession(service: service)
        _ = try await second.prepare(configuration: configuration)
        let unusedAudioURL = URL(fileURLWithPath: "/unused-test-recording.wav")
        _ = try await first.transcribe(audioURL: unusedAudioURL)
        _ = try await second.transcribe(audioURL: unusedAudioURL)

        let contexts = await service.contexts
        XCTAssertEqual(contexts.map(\.prompt), ["first session terminology", "new session terminology"])
        XCTAssertEqual(contexts.map(\.language), ["en", "en"])
    }
}

private actor CapturingPromptService: TranscriptionService {
    private(set) var contexts: [TranscriptionRequestContext] = []

    func transcribe(
        audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext
    ) async throws -> String {
        contexts.append(context)
        return "test transcription"
    }
}
