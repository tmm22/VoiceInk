import Foundation
import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class StreamingVocabularyAndCartesiaTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        // Same shape as the app's in-memory dictionary store.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: VocabularyWord.self, configurations: configuration)
    }

    override func tearDown() async throws {
        container = nil
    }

    func testVocabularyIsTrimmedDeduplicatedAndLimited() throws {
        let context = container.mainContext
        for word in ["alpha", " Alpha ", "", "   ", "beta", "gamma"] {
            context.insert(VocabularyWord(word: word))
        }
        try context.save()
        let logger = AppLogger.transcription
        // Store collation decides which spelling of a duplicate wins; the contract is uniqueness.
        let all = DictionaryVocabulary.terms(from: context, limit: nil, logger: logger)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map { $0.lowercased() }), ["alpha", "beta", "gamma"])
        XCTAssertTrue(all.allSatisfy { $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && !$0.isEmpty })
        XCTAssertEqual(DictionaryVocabulary.terms(from: context, limit: 2, logger: logger).count, 2)
        XCTAssertEqual(DictionaryVocabulary.terms(from: nil, limit: nil, logger: logger), [])
    }

    func testRealCartesiaProviderSendsNoLanguageOrVocabulary() throws {
        let provider = CartesiaStreamingProvider(modelContext: container.mainContext)
        let model = CloudModel(
            name: "ink-2", displayName: "Ink", description: "", provider: .cartesia,
            isMultilingual: true, supportedLanguages: [:])
        let parameters = provider.connectionParameters(model: model, language: "fr")
        XCTAssertEqual(parameters.model, "ink-2")
        XCTAssertNil(parameters.language)
        XCTAssertEqual(parameters.customVocabulary, [])
        XCTAssertTrue(provider.finishesEventsWhenClientStreamEnds)
    }

    func testRealCartesiaProviderAcknowledgesOnlyARequestedFinalization() async throws {
        let provider = CartesiaStreamingProvider(modelContext: container.mainContext)
        // Stream end without commit (for example, a dropped socket) is not a successful finalization.
        provider.willConnect()
        provider.clientEventStreamDidEnd()
        // After commit, the stream end is Cartesia's finalization acknowledgement.
        provider.willCommit()
        provider.clientEventStreamDidEnd()
        // A new connection resets the request.
        provider.willConnect()
        provider.clientEventStreamDidEnd()
        // The client never connected, so this closes nothing on the network.
        await provider.disconnect()

        // Bounded: the stream is already finished, so this must return promptly.
        let collector = Task {
            var committed: [String] = []
            for await event in provider.transcriptionEvents {
                if case .committed(let text) = event { committed.append(text) }
            }
            return committed
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(2))
            collector.cancel()
        }
        let committed = await collector.value
        timeout.cancel()
        XCTAssertEqual(committed, [""], "Exactly one acknowledgement, for the commit")
    }
}
