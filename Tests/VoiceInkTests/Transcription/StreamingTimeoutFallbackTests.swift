import os
import SwiftData
import XCTest
@testable import VoiceInk

/// Exercises the real `StreamingTranscriptionService` stop path and `StreamingTranscriptionSession`
/// with a fake provider: a missed final commit prefers the batch transcript, a user cancel never
/// turns into a fallback upload.
@MainActor
final class StreamingTimeoutFallbackTests: XCTestCase {
    private let logger = Logger(subsystem: "VoiceInkTests", category: "StreamingTimeoutFallback")
    private struct FallbackFailure: Error {}
    private var container: ModelContainer!
    private let model = CloudModel(
        name: "fake-stream", displayName: "Fake", description: "", provider: .deepgram,
        isMultilingual: true, supportedLanguages: [:])

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: VocabularyWord.self, configurations: configuration)
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: - Service stop path

    func testMissedFinalCommitReportsTimeoutInsteadOfFinalText() async throws {
        let provider = FakeStopProvider()
        let service = makeService(provider, timeout: .milliseconds(50))
        try await service.startStreaming(model: model, context: .currentDefaults)
        let result = try await service.stopAndFinalize()
        XCTAssertEqual(result, .timedOut(partialText: ""))
    }

    func testAcknowledgedCommitStillFinalizes() async throws {
        let provider = FakeStopProvider()
        provider.onCommit = { [unowned provider] in provider.emit(.committed(text: "complete")) }
        let service = makeService(provider, timeout: .seconds(5))
        try await service.startStreaming(model: model, context: .currentDefaults)
        let result = try await service.stopAndFinalize()
        XCTAssertEqual(result, .finalized(text: "complete"))
    }

    func testCancelDuringFinalWaitThrowsInsteadOfReportingTimeout() async throws {
        let provider = FakeStopProvider()
        let service = makeService(provider, timeout: .seconds(30))
        provider.onCommit = { Task { @MainActor in service.cancel() } }
        try await service.startStreaming(model: model, context: .currentDefaults)
        let started = ContinuousClock.now
        do {
            _ = try await service.stopAndFinalize()
            XCTFail("A cancelled stop must not produce a result")
        } catch is CancellationError {
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "Cancel must end the wait, not the deadline")
        }
    }

    // MARK: - Session

    func testCancelledSessionNeverStartsBatchFallback() async throws {
        let provider = FakeStopProvider()
        let service = makeService(provider, timeout: .seconds(30))
        provider.onCommit = { Task { @MainActor in service.cancel() } }
        let fallback = CountingTranscriptionService()
        let session = StreamingTranscriptionSession(streamingService: service, fallbackService: fallback)
        _ = try await session.prepare(configuration: TranscriptionRuntimeConfiguration(
            mode: ModeConfig(name: "Test", isAIEnhancementEnabled: false),
            model: model, language: "en", isRealtimeEnabled: true))
        try await waitUntil { service.isActive }
        do {
            _ = try await session.transcribe(audioURL: URL(fileURLWithPath: "/unused.wav"))
            XCTFail("Cancelled session must throw")
        } catch is CancellationError {
            // Expected.
        }
        let calls = await fallback.calls
        XCTAssertEqual(calls, 0, "A user cancel must not upload the recording")
    }

    func testCommitFailingBecauseOfCancelNeverStartsBatchFallback() async throws {
        let provider = FakeStopProvider()
        let service = makeService(provider, timeout: .seconds(30))
        let fallback = CountingTranscriptionService()
        let session = StreamingTranscriptionSession(streamingService: service, fallbackService: fallback)
        // The user cancels while commit is in flight; the disconnect makes commit throw.
        provider.commitError = StreamingTranscriptionError.notConnected
        provider.onCommit = { session.cancel() }
        _ = try await session.prepare(configuration: TranscriptionRuntimeConfiguration(
            mode: ModeConfig(name: "Test", isAIEnhancementEnabled: false),
            model: model, language: "en", isRealtimeEnabled: true))
        try await waitUntil { service.isActive }
        do {
            _ = try await session.transcribe(audioURL: URL(fileURLWithPath: "/unused.wav"))
            XCTFail("Cancelled session must throw")
        } catch is CancellationError {
            // Expected.
        }
        let calls = await fallback.calls
        XCTAssertEqual(calls, 0, "A cancel that breaks the commit must not upload the recording")
    }

    func testTimedOutSessionUsesBatchTranscript() async throws {
        let provider = FakeStopProvider()
        let service = makeService(provider, timeout: .milliseconds(50))
        let fallback = CountingTranscriptionService(result: "full recording")
        let session = StreamingTranscriptionSession(streamingService: service, fallbackService: fallback)
        _ = try await session.prepare(configuration: TranscriptionRuntimeConfiguration(
            mode: ModeConfig(name: "Test", isAIEnhancementEnabled: false),
            model: model, language: "en", isRealtimeEnabled: true))
        try await waitUntil { service.isActive }
        let text = try await session.transcribe(audioURL: URL(fileURLWithPath: "/unused.wav"))
        XCTAssertEqual(text, "full recording")
        let calls = await fallback.calls
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Fallback decision

    func testFailedBatchKeepsCommittedStreamingText() async throws {
        let text = try await StreamingTranscriptionSession.transcribeAfterStreamingTimeout(
            partialText: "first half", canTranscribeInBatch: true,
            fallback: { throw FallbackFailure() }, logger: logger)
        XCTAssertEqual(text, "first half", "A failed fallback must not discard what the stream delivered")
    }

    func testStreamingOnlyProviderSkipsBatchAttempt() async throws {
        var attempts = 0
        let text = try await StreamingTranscriptionSession.transcribeAfterStreamingTimeout(
            partialText: "partial", canTranscribeInBatch: false,
            fallback: { attempts += 1; return "unused" }, logger: logger)
        XCTAssertEqual(text, "partial")
        XCTAssertEqual(attempts, 0)
        let cartesia = CloudModel(
            name: "ink", displayName: "Ink", description: "", provider: .cartesia,
            isMultilingual: true, supportedLanguages: [:])
        XCTAssertFalse(StreamingTranscriptionSession.supportsBatchFallback(cartesia))
        XCTAssertTrue(StreamingTranscriptionSession.supportsBatchFallback(model))
    }

    func testWrappedCancellationIsNotConvertedIntoPartialText() async {
        for failure: Error in [
            CancellationError(), URLError(.cancelled), CloudTranscriptionError.networkError(URLError(.cancelled)),
        ] {
            do {
                _ = try await StreamingTranscriptionSession.transcribeAfterStreamingTimeout(
                    partialText: "first half", canTranscribeInBatch: true,
                    fallback: { throw failure }, logger: logger)
                XCTFail("Cancellation must propagate for \(failure)")
            } catch is CancellationError {
                // Expected.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func makeService(_ provider: FakeStopProvider, timeout: Duration) -> StreamingTranscriptionService {
        StreamingTranscriptionService(
            modelContext: container.mainContext, finalizationTimeout: timeout, providerFactory: { _ in provider })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Streaming did not connect in time")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class FakeStopProvider: StreamingTranscriptionProvider {
    private let continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation
    let transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    var onCommit: () -> Void = {}
    var commitError: Error?

    init() {
        (transcriptionEvents, continuation) = AsyncStream.makeStream()
    }

    func emit(_ event: StreamingTranscriptionEvent) { continuation.yield(event) }
    func connect(model: any TranscriptionModel, language: String?) async throws {}
    func sendAudioChunk(_ data: Data) async throws {}
    func commit() async throws {
        onCommit()
        if let commitError { throw commitError }
    }
    func disconnect() async { continuation.finish() }
}

private actor CountingTranscriptionService: TranscriptionService {
    private(set) var calls = 0
    private let result: String

    init(result: String = "batch") { self.result = result }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> String
    {
        calls += 1
        return result
    }
}
