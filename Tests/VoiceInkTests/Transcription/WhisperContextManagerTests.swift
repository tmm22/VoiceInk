import XCTest
@testable import VoiceInk

final class WhisperContextManagerTests: XCTestCase {
    private let modelURL = URL(fileURLWithPath: "/unused-model")
    private let audioURL = URL(fileURLWithPath: "/unused-audio")

    func testConcurrentWaitersSharePublishedContextWithoutReleasingIt() async throws {
        let loader = ControlledWhisperLoader()
        let manager = WhisperContextManager(contextLoader: { _ in try await loader.load() })
        let first = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        let second = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await manager.pendingLoadWaiterCount(for: "model") == 2 }
        let context = FakeManagedWhisperContext()
        await loader.completeNext(with: .success(context))
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertTrue(firstResult === context)
        XCTAssertTrue(secondResult === context)
        let cached = try await manager.loadContext(for: "model", modelURL: modelURL)
        XCTAssertTrue(cached === context)
        let releaseCount = await context.releaseCount
        XCTAssertEqual(releaseCount, 0)
        await manager.unloadContext(for: "model")
        let finalReleaseCount = await context.releaseCount
        XCTAssertEqual(finalReleaseCount, 1)
    }

    func testInvalidatedLoadReleasesOnceAndDoesNotRemoveReplacement() async throws {
        let loader = ControlledWhisperLoader()
        let manager = WhisperContextManager(contextLoader: { _ in try await loader.load() })
        let oldFirst = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        let oldSecond = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await manager.pendingLoadWaiterCount(for: "model") == 2 }
        await waitUntil { await loader.pendingCount == 1 }
        await manager.unloadContext(for: "model")
        let replacement = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await loader.pendingCount == 2 }
        let oldContext = FakeManagedWhisperContext()
        let newContext = FakeManagedWhisperContext()
        await loader.completeNext(with: .success(oldContext))
        await assertCancelled(oldFirst)
        await assertCancelled(oldSecond)
        await loader.completeNext(with: .success(newContext))
        let result = try await replacement.value
        XCTAssertTrue(result === newContext)
        let releaseCount = await oldContext.releaseCount
        let newReleaseCount = await newContext.releaseCount
        let loaded = await manager.isContextLoaded(for: "model")
        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(newReleaseCount, 0)
        XCTAssertTrue(loaded)
        await manager.unloadAllContexts()
    }

    func testFailedOldLoadDoesNotRemoveReplacement() async throws {
        let loader = ControlledWhisperLoader()
        let manager = WhisperContextManager(contextLoader: { _ in try await loader.load() })
        let old = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await loader.pendingCount == 1 }
        await manager.unloadContext(for: "model")
        let replacement = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await loader.pendingCount == 2 }
        await loader.completeNext(with: .failure(WhisperContextError.transcriptionFailed))
        do {
            _ = try await old.value
            XCTFail("Old load should fail")
        } catch WhisperContextError.transcriptionFailed {
            // Expected loader failure.
        }
        let context = FakeManagedWhisperContext()
        await loader.completeNext(with: .success(context))
        let result = try await replacement.value
        XCTAssertTrue(result === context)
        let loaded = await manager.isContextLoaded(for: "model")
        XCTAssertTrue(loaded)
        await manager.unloadAllContexts()
    }

    func testCancellingOneWaiterDoesNotCancelSharedLoad() async throws {
        let loader = ControlledWhisperLoader()
        let manager = WhisperContextManager(contextLoader: { _ in try await loader.load() })
        let cancelled = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        let survivor = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await waitUntil { await manager.pendingLoadWaiterCount(for: "model") == 2 }
        cancelled.cancel()
        let context = FakeManagedWhisperContext()
        await loader.completeNext(with: .success(context))
        await assertCancelled(cancelled)
        let result = try await survivor.value
        XCTAssertTrue(result === context)
        let releaseCount = await context.releaseCount
        XCTAssertEqual(releaseCount, 0)
        await manager.unloadAllContexts()
    }

    func testUnloadRetainsOldInferenceButReleasesIdleReplacementIndependently() async throws {
        let oldContext = FakeManagedWhisperContext(blockInference: true)
        let newContext = FakeManagedWhisperContext()
        let loader = ControlledWhisperLoader()
        let manager = WhisperContextManager(
            contextLoader: { _ in try await loader.load() }, sampleLoader: { _ in [0.25] }
        )
        let inference = Task {
            try await manager.performInference(modelName: "model", modelURL: modelURL,
                                               audioURL: audioURL, language: "en", prompt: "words")
        }
        await loader.completeNext(with: .success(oldContext))
        await waitUntil { await oldContext.inferenceCount == 1 }
        await manager.unloadContext(for: "model")
        let releaseDuringInference = await oldContext.releaseCount
        XCTAssertEqual(releaseDuringInference, 0)
        let replacement = Task { try await manager.loadContext(for: "model", modelURL: modelURL) }
        await loader.completeNext(with: .success(newContext))
        _ = try await replacement.value
        await manager.unloadAllContexts()
        let oldReleaseCount = await oldContext.releaseCount
        let newReleaseCount = await newContext.releaseCount
        XCTAssertEqual(oldReleaseCount, 0)
        XCTAssertEqual(newReleaseCount, 1, "Retirement belongs to a context generation, not its model name")
        await oldContext.finish()
        let result = try await inference.value
        XCTAssertEqual(result, "en:words")
        let finalReleaseCount = await oldContext.releaseCount
        XCTAssertEqual(finalReleaseCount, 1)
    }

    func testRetiredContextWaitsForEveryActiveInference() async throws {
        let context = FakeManagedWhisperContext(blockInference: true)
        let manager = WhisperContextManager(contextLoader: { _ in context }, sampleLoader: { _ in [0] })
        let first = Task {
            try await manager.performInference(modelName: "model", modelURL: modelURL,
                                               audioURL: audioURL, language: "en", prompt: "first")
        }
        await waitUntil { await context.inferenceCount == 1 }
        let second = Task {
            try await manager.performInference(modelName: "model", modelURL: modelURL,
                                               audioURL: audioURL, language: "fr", prompt: "second")
        }
        await waitUntil { await context.inferenceCount == 2 }
        await manager.unloadAllContexts()
        await context.finish()
        let firstResult = try await first.value
        XCTAssertEqual(firstResult, "en:first")
        let intermediateReleaseCount = await context.releaseCount
        XCTAssertEqual(intermediateReleaseCount, 0)
        await context.finish()
        let secondResult = try await second.value
        XCTAssertEqual(secondResult, "fr:second")
        let finalReleaseCount = await context.releaseCount
        XCTAssertEqual(finalReleaseCount, 1)
    }

    func testCancelledInferenceReleasesRetiredContextAfterWorkFinishes() async throws {
        let context = FakeManagedWhisperContext(blockInference: true)
        let manager = WhisperContextManager(contextLoader: { _ in context }, sampleLoader: { _ in [0] })
        let inference = Task {
            try await manager.performInference(modelName: "model", modelURL: modelURL,
                                               audioURL: audioURL, language: nil, prompt: nil)
        }
        await waitUntil { await context.inferenceCount == 1 }
        inference.cancel()
        await manager.unloadAllContexts()
        let releaseDuringInference = await context.releaseCount
        XCTAssertEqual(releaseDuringInference, 0)
        await context.finish()
        await assertCancelled(inference)
        let releaseCount = await context.releaseCount
        XCTAssertEqual(releaseCount, 1)
    }

    func testFailedSampleReadReleasesRetiredContext() async throws {
        let context = FakeManagedWhisperContext()
        let samples = SampleReadGate()
        let manager = WhisperContextManager(
            contextLoader: { _ in context }, sampleLoader: { _ in try await samples.read() }
        )
        let inference = Task {
            try await manager.performInference(modelName: "model", modelURL: modelURL,
                                               audioURL: audioURL, language: nil, prompt: nil)
        }
        await waitUntil { await samples.hasStarted }
        await manager.unloadAllContexts()
        let releaseDuringRead = await context.releaseCount
        XCTAssertEqual(releaseDuringRead, 0)
        await samples.fail()
        do {
            _ = try await inference.value
            XCTFail("Sample read should fail")
        } catch WhisperContextError.transcriptionFailed {
            // Expected sample-reader failure.
        }
        let releaseCount = await context.releaseCount
        let inferenceCount = await context.inferenceCount
        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(inferenceCount, 0)
    }

    func testSwitchingKeepsTheTargetModelsLiveContextAndRetiresOthers() async throws {
        let kept = FakeManagedWhisperContext()
        let other = FakeManagedWhisperContext()
        let manager = WhisperContextManager(contextLoader: { url in
            url.lastPathComponent == "kept" ? kept : other
        })
        let keptURL = URL(fileURLWithPath: "/models/kept")
        let prewarmed = try await manager.loadContext(for: "kept", modelURL: keptURL)
        _ = try await manager.loadContext(for: "other", modelURL: URL(fileURLWithPath: "/models/other"))

        await manager.unloadAllContexts(except: "kept")
        let reused = try await manager.loadContext(for: "kept", modelURL: keptURL)
        XCTAssertTrue(reused === prewarmed, "A prewarmed context must survive switching to its own model")
        let keptReleases = await kept.releaseCount
        let otherReleases = await other.releaseCount
        let otherLoaded = await manager.isContextLoaded(for: "other")
        XCTAssertEqual(keptReleases, 0)
        XCTAssertEqual(otherReleases, 1)
        XCTAssertFalse(otherLoaded)
        await manager.unloadAllContexts()
        let finalKeptReleases = await kept.releaseCount
        XCTAssertEqual(finalKeptReleases, 1)
    }

    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for test synchronization", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    private func assertCancelled<T>(_ task: Task<T, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation", file: file, line: line)
        } catch is CancellationError {
            // Expected cancellation.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private actor ControlledWhisperLoader {
    private var pending: [CheckedContinuation<any ManagedWhisperContext, Error>] = []
    private var results: [Result<any ManagedWhisperContext, Error>] = []
    var pendingCount: Int { pending.count }

    func load() async throws -> any ManagedWhisperContext {
        if !results.isEmpty { return try results.removeFirst().get() }
        // Intentionally ignore cancellation to reproduce native model loading that
        // completes after unload. The manager must retire that returned context.
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func completeNext(with result: Result<any ManagedWhisperContext, Error>) {
        if pending.isEmpty { results.append(result) }
        else { pending.removeFirst().resume(with: result) }
    }
}

private actor FakeManagedWhisperContext: ManagedWhisperContext {
    private let blockInference: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var releaseCount = 0
    private(set) var inferenceCount = 0

    init(blockInference: Bool = false) { self.blockInference = blockInference }

    func transcribe(samples: [Float], language: String?, prompt: String?) async throws -> String {
        inferenceCount += 1
        if blockInference { await withCheckedContinuation { continuations.append($0) } }
        return "\(language ?? "auto"):\(prompt ?? "")"
    }

    func releaseResources() { releaseCount += 1 }
    func finish() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private actor SampleReadGate {
    private var continuation: CheckedContinuation<[Float], Error>?
    var hasStarted: Bool { continuation != nil }
    func read() async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() {
        continuation?.resume(throwing: WhisperContextError.transcriptionFailed)
        continuation = nil
    }
}
