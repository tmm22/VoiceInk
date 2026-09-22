import Foundation
import LLMkit
import XCTest
@testable import VoiceInk

final class LLMKitStreamingProviderTests: XCTestCase {
    private let model = CloudModel(
        name: "test-model", displayName: "Test", description: "", provider: .cartesia,
        isMultilingual: true, supportedLanguages: [:])

    func testForwardsEventsAndConnectionParameters() async throws {
        let client = FakeStreamingClient()
        let provider = makeProvider(client)
        try await provider.connect(model: model, language: "fr")
        XCTAssertEqual(client.connection?.model, "test-model")
        XCTAssertEqual(client.connection?.language, "fr")
        XCTAssertEqual(client.connection?.customVocabulary, [])

        var iterator = provider.transcriptionEvents.makeAsyncIterator()
        client.continuation.yield(.sessionStarted)
        client.continuation.yield(.partial(text: "partial"))
        client.continuation.yield(.committed(text: "final"))
        client.continuation.yield(.error("test failure"))
        client.continuation.finish()

        // The finite fake stream ensures failures terminate instead of hanging the suite.
        let started = await iterator.next()
        let partial = await iterator.next()
        let committed = await iterator.next()
        let error = await iterator.next()
        let ended = await iterator.next()
        guard case .sessionStarted? = started else { return XCTFail("Missing session event") }
        guard case .partial(let text)? = partial else { return XCTFail("Missing partial") }
        XCTAssertEqual(text, "partial")
        guard case .committed(let text)? = committed else { return XCTFail("Missing committed") }
        XCTAssertEqual(text, "final")
        guard case .error(let error)? = error,
              case StreamingTranscriptionError.serverError(let message) = error else {
            return XCTFail("Missing mapped error")
        }
        XCTAssertEqual(message, "test failure")
        XCTAssertNil(ended)
        await provider.disconnect()
    }

    func testNaturalEndAfterCommitEmitsFinalizationAcknowledgement() async throws {
        let client = FakeStreamingClient()
        let provider = makeProvider(client)
        try await provider.connect(model: model, language: nil)
        try await provider.commit()
        client.continuation.yield(.committed(text: "complete"))
        client.continuation.finish()

        var texts: [String] = []
        for await event in provider.transcriptionEvents {
            if case .committed(let text) = event { texts.append(text) }
        }
        XCTAssertEqual(texts, ["complete", ""])
        XCTAssertEqual(client.commitCount, 1)
        await provider.disconnect()
    }

    func testDisconnectAfterCommitDoesNotAcknowledgeFinalization() async throws {
        let client = FakeStreamingClient()
        let provider = makeProvider(client)
        try await provider.connect(model: model, language: nil)
        try await provider.commit()
        await provider.disconnect()

        var committedCount = 0
        for await event in provider.transcriptionEvents {
            if case .committed = event { committedCount += 1 }
        }
        XCTAssertEqual(committedCount, 0)
        XCTAssertEqual(client.disconnectCount, 1)
    }

    func testIdleForwardingDoesNotRetainProviderAndDisconnectsClient() async throws {
        let client = FakeStreamingClient()
        let disconnected = expectation(description: "Client disconnected on provider deallocation")
        client.onDisconnect = { disconnected.fulfill() }
        var provider: TestStreamingProvider? = makeProvider(client)
        weak var weakProvider: TestStreamingProvider?
        weakProvider = provider
        try await provider?.connect(model: model, language: nil)

        // Wait until the task has actually forwarded an event, then leave it awaiting more.
        var iterator = try XCTUnwrap(provider).transcriptionEvents.makeAsyncIterator()
        client.continuation.yield(.sessionStarted)
        _ = await iterator.next()
        provider = nil

        // Forwarding may still be returning from yield on another executor. Wait for
        // deallocation rather than depending on which executor resumes first.
        await fulfillment(of: [disconnected], timeout: 2)
        XCTAssertNil(weakProvider)
        // If retention regresses, fail without leaving the iterator suspended forever.
        if let retainedProvider = weakProvider { await retainedProvider.disconnect() }
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testFailedConnectMapsErrorAndDisconnectsWhenRequested() async {
        let client = FakeStreamingClient()
        client.connectError = LLMKitError.timeout
        let provider = makeProvider(client)
        do {
            try await provider.connect(model: model, language: nil)
            XCTFail("Expected connection failure")
        } catch {
            guard case StreamingTranscriptionError.timeout = error else {
                return XCTFail("Unexpected error: \(type(of: error))")
            }
        }
        XCTAssertEqual(client.disconnectCount, 1)
        // A provider whose stream ends with the client's must end it on a failed connect too,
        // without relying on a later disconnect. Bounded so a regression fails instead of hanging.
        let ended = await Self.streamEnds(provider.transcriptionEvents, within: .seconds(2))
        XCTAssertTrue(ended, "Failed connect must finish the app-facing stream")
        await provider.disconnect()
    }

    /// True when the stream finishes without yielding before the deadline.
    static func streamEnds(
        _ stream: AsyncStream<VoiceInk.StreamingTranscriptionEvent>, within limit: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() == nil
            }
            group.addTask {
                try? await Task.sleep(for: limit)  // Cancelled when the stream answers first.
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
    }

    func testMissingCredentialNeverConnectsClient() async {
        let client = FakeStreamingClient()
        let provider = TestStreamingProvider(
            client: client, apiKeyProviderName: "Test", modelContext: nil, apiKeyLookup: { _ in nil })
        do {
            try await provider.connect(model: model, language: nil)
            XCTFail("Expected missing credential")
        } catch {
            guard case StreamingTranscriptionError.missingAPIKey = error else {
                return XCTFail("Unexpected error: \(type(of: error))")
            }
        }
        XCTAssertNil(client.connection)
    }

    func testCancelledConnectPreservesCancellationAndStopsForwarding() async {
        let client = FakeStreamingClient()
        client.connectError = CancellationError()
        let provider = makeProvider(client)
        do {
            try await provider.connect(model: model, language: nil)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(client.disconnectCount, 1)
        await provider.disconnect()
        var events = 0
        for await _ in provider.transcriptionEvents { events += 1 }
        XCTAssertEqual(events, 0)
    }

    func testFailedConnectKeepsVendorCleanupPolicyAndReleasesProvider() async {
        let client = FakeStreamingClient()
        client.connectError = LLMKitError.timeout
        let disconnected = expectation(description: "Failed client cleaned up on deallocation")
        client.onDisconnect = { disconnected.fulfill() }
        var provider: LLMKitStreamingProvider<FakeStreamingClient>? = LLMKitStreamingProvider(
            client: client, apiKeyProviderName: "Test", modelContext: nil,
            apiKeyLookup: { _ in "fake-test-credential" })
        weak var weakProvider: LLMKitStreamingProvider<FakeStreamingClient>?
        weakProvider = provider
        do {
            try await provider?.connect(model: model, language: nil)
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error is StreamingTranscriptionError)
        }
        // Only Gemini requests immediate disconnect in its connect-failure hook.
        XCTAssertEqual(client.disconnectCount, 0)
        provider = nil
        XCTAssertNil(weakProvider)
        await fulfillment(of: [disconnected], timeout: 2)
    }

    func testSendAndCommitMapErrors() async {
        let client = FakeStreamingClient()
        client.operationError = LLMKitError.timeout
        let provider = makeProvider(client)
        do {
            try await provider.sendAudioChunk(Data([0, 0]))
            XCTFail("Expected send failure")
        } catch {
            guard case StreamingTranscriptionError.timeout = error else { return XCTFail("Unmapped send error") }
        }
        do {
            try await provider.commit()
            XCTFail("Expected commit failure")
        } catch {
            guard case StreamingTranscriptionError.timeout = error else { return XCTFail("Unmapped commit error") }
        }
    }

    private func makeProvider(_ client: FakeStreamingClient) -> TestStreamingProvider {
        TestStreamingProvider(
            client: client, apiKeyProviderName: "Test", modelContext: nil,
            apiKeyLookup: { _ in "fake-test-credential" })
    }
}

/// Exercises the same base-class finalization hooks used by Cartesia, without opening a socket.
private final class TestStreamingProvider: LLMKitStreamingProvider<FakeStreamingClient> {
    private let lock = NSLock()
    private var requestedFinalization = false
    override var finishesEventsWhenClientStreamEnds: Bool { true }
    override var disconnectsClientOnConnectFailure: Bool { true }
    override func willConnect() { lock.withLock { requestedFinalization = false } }
    override func willCommit() { lock.withLock { requestedFinalization = true } }
    override func clientEventStreamDidEnd() {
        if lock.withLock({ requestedFinalization }) { yield(.committed(text: "")) }
    }
}

private final class FakeStreamingClient: LLMkit.StreamingTranscriptionProvider {
    let transcriptionEvents: AsyncStream<LLMkit.StreamingTranscriptionEvent>
    let continuation: AsyncStream<LLMkit.StreamingTranscriptionEvent>.Continuation
    var connection: LLMKitStreamingConnection?
    var connectError: Error?
    var operationError: Error?
    var onDisconnect: (() -> Void)?
    private let lock = NSLock()
    private var disconnections = 0
    private(set) var commitCount = 0
    var disconnectCount: Int { lock.withLock { disconnections } }

    init() {
        (transcriptionEvents, continuation) = AsyncStream.makeStream()
    }

    func connect(apiKey: String, model: String, language: String?, customVocabulary: [String]) async throws {
        connection = LLMKitStreamingConnection(model: model, language: language, customVocabulary: customVocabulary)
        if let connectError { throw connectError }
    }

    func sendAudioChunk(_ data: Data) async throws {
        if let operationError { throw operationError }
    }

    func commit() async throws {
        commitCount += 1
        if let operationError { throw operationError }
    }

    func disconnect() async {
        lock.withLock { disconnections += 1 }
        continuation.finish()
        onDisconnect?()
    }
}
