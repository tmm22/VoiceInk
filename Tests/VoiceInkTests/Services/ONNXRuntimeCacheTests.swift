import XCTest
@testable import VoiceInk

private let modelKey = "model"

/// Single-flight and generation rules behind the FastConformer / SenseVoice record-start prepare.
final class ONNXRuntimeCacheTests: XCTestCase {
    func testPrepareAndTranscribeShareOneBuildAndCacheItsRuntime() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let prepare = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        let secondPrepare = Task {
            try await cache.prepare(modelKey) { try await gate.build() }
        }
        let transcribe = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { cache.inFlightRequestCount(for: modelKey) == 3 }
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))

        let runtime = FakeONNXRuntime()
        await gate.completeNext(with: .success(runtime))
        let prepared = try await prepare.value
        let preparedAgain = try await secondPrepare.value
        let transcribed = try await transcribe.value
        XCTAssertTrue(prepared === runtime)
        XCTAssertTrue(preparedAgain === runtime)
        XCTAssertTrue(transcribed === runtime)
        XCTAssertTrue(cache.hasCachedRuntime(for: modelKey))
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)

        let cached = try await cache.transcribe(modelKey) { try await gate.build() }
        XCTAssertTrue(cached === runtime)
        let startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 1, "A transcription that follows a prepare must never build a second session")
    }

    func testInvalidationDiscardsAnInFlightBuildButStillServesItsWaiters() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        // Scoped so the waiter's task handle, which retains its result, is gone before the release check.
        func runInvalidatedBuild() async throws -> WeakONNXRuntime {
            let waiter = Task {
                try await cache.transcribe(modelKey) { try await gate.build() }
            }
            await waitUntil { await gate.pendingCount == 1 }
            cache.invalidateAll()
            XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)
            XCTAssertEqual(cache.runningDetachedBuildCount, 1)

            let runtime = FakeONNXRuntime()
            await gate.completeNext(with: .success(runtime))
            let served = try await waiter.value
            XCTAssertTrue(served === runtime, "A caller already waiting keeps the runtime it waited for")
            XCTAssertFalse(
                cache.hasCachedRuntime(for: modelKey), "A build that finishes after cleanup is never cached")
            XCTAssertEqual(cache.runningDetachedBuildCount, 0)
            return WeakONNXRuntime(runtime)
        }

        let discarded = try await runInvalidatedBuild()
        await waitUntil { discarded.value == nil }
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
    }

    func testOldCompletionNeverReplacesOrRemovesANewerBuild() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let old = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        cache.invalidate(modelKey)
        let replacement = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { await gate.pendingCount == 2 }

        let oldRuntime = FakeONNXRuntime()
        let newRuntime = FakeONNXRuntime()
        await gate.completeNext(with: .success(oldRuntime))
        let oldResult = try await old.value
        XCTAssertTrue(oldResult === oldRuntime)
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey), "The invalidated build must not be cached")
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 1, "The newer build must stay registered")

        await gate.completeNext(with: .success(newRuntime))
        let newResult = try await replacement.value
        XCTAssertTrue(newResult === newRuntime)
        let cached = try await cache.prepare(modelKey) { try await gate.build() }
        XCTAssertTrue(cached === newRuntime)
        let startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 2)
    }

    func testFailedOldBuildDoesNotRemoveItsReplacement() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let old = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        cache.invalidateAll()
        let replacement = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { await gate.pendingCount == 2 }

        await gate.completeNext(with: .failure(ONNXBuildFailure(label: "old")))
        await assertFailure(old, label: "old")
        XCTAssertEqual(
            cache.inFlightRequestCount(for: modelKey), 1, "A failed old build must not remove the newer one")
        XCTAssertEqual(cache.runningDetachedBuildCount, 0)

        let joiner = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { cache.inFlightRequestCount(for: modelKey) == 2 }
        let runtime = FakeONNXRuntime()
        await gate.completeNext(with: .success(runtime))
        let replacementResult = try await replacement.value
        let joinerResult = try await joiner.value
        XCTAssertTrue(replacementResult === runtime)
        XCTAssertTrue(joinerResult === runtime)
        let startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 2)
    }

    func testPrepareNeverStacksABuildOnInvalidatedBuildsStillRunning() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let aborted = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        cache.invalidateAll()

        // The aborted recording's build cannot be interrupted, so the next prepares start nothing.
        for key in [modelKey, "another-model"] {
            do {
                _ = try await cache.prepare(key) { try await gate.build() }
                XCTFail("A prepare must not start a build while an invalidated one is still running")
            } catch is ONNXRuntimeBuildDeferredError {
                // Expected: deferred to the build that is still running.
            }
        }
        var startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 1)
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)

        // A transcription still gets its runtime straight away, exactly as it did before prepares existed.
        let transcribe = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { await gate.pendingCount == 2 }
        await gate.completeNext(with: .success(FakeONNXRuntime()))
        _ = try await aborted.value
        XCTAssertEqual(cache.runningDetachedBuildCount, 0)
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
        let runtime = FakeONNXRuntime()
        await gate.completeNext(with: .success(runtime))
        let transcribed = try await transcribe.value
        XCTAssertTrue(transcribed === runtime)

        // Once nothing invalidated is running any more, prepares build again.
        cache.invalidateAll()
        let prepared = try await cache.prepare(modelKey) { FakeONNXRuntime() }
        XCTAssertFalse(prepared === runtime)
        XCTAssertTrue(cache.hasCachedRuntime(for: modelKey))
        startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 2)
    }

    func testInvalidationCancelsAPrepareThatHasNotStartedItsBuild() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        // The prepare was requested, then cleanup ran before it got to register its build.
        let epochAtRequest = cache.invalidationEpoch
        cache.invalidateAll()
        XCTAssertNotEqual(cache.invalidationEpoch, epochAtRequest)
        do {
            _ = try await cache.runtime(for: modelKey, request: .prepare(epoch: epochAtRequest)) {
                try await gate.build()
            }
            XCTFail("A prepare overtaken by cleanup must not start a build")
        } catch is ONNXRuntimeBuildDeferredError {
            // Expected: nothing may be cached behind the cleanup.
        }
        var startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 0)
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)

        // Invalidating a single model counts too.
        let epochBeforeSingleInvalidation = cache.invalidationEpoch
        cache.invalidate("another-model")
        XCTAssertNotEqual(cache.invalidationEpoch, epochBeforeSingleInvalidation)

        // A prepare requested after the cleanup builds normally, and the overtaken one may share its result.
        let runtime = FakeONNXRuntime()
        let prepared = try await cache.prepare(modelKey) { runtime }
        let shared = try await cache.runtime(for: modelKey, request: .prepare(epoch: epochAtRequest)) {
            try await gate.build()
        }
        XCTAssertTrue(prepared === runtime)
        XCTAssertTrue(shared === runtime)
        startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 0)
    }

    func testFailedBuildCachesNothingAndTheNextRequestBuildsAgain() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        do {
            _ = try await cache.prepare(modelKey) { throw ONNXBuildFailure(label: "prepare") }
            XCTFail("The build should fail")
        } catch let failure as ONNXBuildFailure {
            XCTAssertEqual(failure.label, "prepare")
        }
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)
        XCTAssertEqual(cache.runningDetachedBuildCount, 0)

        let runtime = FakeONNXRuntime()
        let rebuilt = try await cache.transcribe(modelKey) { runtime }
        XCTAssertTrue(rebuilt === runtime)
        XCTAssertTrue(cache.hasCachedRuntime(for: modelKey))
    }

    func testOnlyATranscriptionRetriesAfterAJoinedBuildFails() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let prepare = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        let transcribe = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        let secondPrepare = Task {
            try await cache.prepare(modelKey) { try await gate.build() }
        }
        await waitUntil { cache.inFlightRequestCount(for: modelKey) == 3 }

        await gate.completeNext(with: .failure(ONNXBuildFailure(label: "prepare")))
        await assertFailure(prepare, label: "prepare")
        await assertFailure(secondPrepare, label: "prepare")

        // The transcription builds once more for itself and reports the error of that attempt.
        await waitUntil { await gate.pendingCount == 1 }
        await gate.completeNext(with: .failure(ONNXBuildFailure(label: "transcribe")))
        await assertFailure(transcribe, label: "transcribe")
        let startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 2, "One shared attempt plus one retry, never a third")
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
        XCTAssertEqual(cache.inFlightRequestCount(for: modelKey), 0)
    }

    func testTranscriptionThatStartedTheBuildDoesNotRetryItsOwnFailure() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let transcribe = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { await gate.pendingCount == 1 }
        await gate.completeNext(with: .failure(ONNXBuildFailure(label: "transcribe")))
        await assertFailure(transcribe, label: "transcribe")
        let startedBuilds = await gate.startedCount
        XCTAssertEqual(startedBuilds, 1, "A transcription reports its own build failure once, as it always has")
    }

    func testRetryAfterJoinedFailureCanSucceedAndIsCached() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let gate = ONNXBuildGate()
        let prepare = Task { try await cache.prepare(modelKey) { try await gate.build() } }
        await waitUntil { await gate.pendingCount == 1 }
        let transcribe = Task {
            try await cache.transcribe(modelKey) { try await gate.build() }
        }
        await waitUntil { cache.inFlightRequestCount(for: modelKey) == 2 }

        await gate.completeNext(with: .failure(ONNXBuildFailure(label: "prepare")))
        await assertFailure(prepare, label: "prepare")
        await waitUntil { await gate.pendingCount == 1 }
        let runtime = FakeONNXRuntime()
        await gate.completeNext(with: .success(runtime))
        let transcribed = try await transcribe.value
        XCTAssertTrue(transcribed === runtime)
        XCTAssertTrue(cache.hasCachedRuntime(for: modelKey))
    }

    func testInvalidatingOneModelLeavesOthersCached() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        let kept = FakeONNXRuntime()
        _ = try await cache.prepare("kept") { kept }
        _ = try await cache.prepare("dropped") { FakeONNXRuntime() }

        cache.invalidate("dropped")
        cache.invalidate("never-built")
        XCTAssertFalse(cache.hasCachedRuntime(for: "dropped"))
        XCTAssertTrue(cache.hasCachedRuntime(for: "kept"))
        XCTAssertEqual(cache.runningDetachedBuildCount, 0, "Only builds that were running count as detached")
        let reused = try await cache.transcribe("kept") { FakeONNXRuntime() }
        XCTAssertTrue(reused === kept)
    }

    func testInvalidateAllReleasesCachedRuntimes() async throws {
        let cache = ONNXRuntimeCache<FakeONNXRuntime>()
        func cacheRuntime() async throws -> WeakONNXRuntime {
            let runtime = try await cache.prepare(modelKey) { FakeONNXRuntime() }
            return WeakONNXRuntime(runtime)
        }

        let cached = try await cacheRuntime()
        XCTAssertNotNil(cached.value, "The cache owns the runtime between a recording's build and its cleanup")
        cache.invalidateAll()
        await waitUntil { cached.value == nil }
        XCTAssertFalse(cache.hasCachedRuntime(for: modelKey))
        XCTAssertEqual(cache.runningDetachedBuildCount, 0)
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

    private func assertFailure(
        _ task: Task<FakeONNXRuntime, Error>, label: String, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Expected the build to fail", file: file, line: line)
        } catch let failure as ONNXBuildFailure {
            XCTAssertEqual(failure.label, label, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private extension ONNXRuntimeCache {
    /// A record-start prepare requested right now.
    func prepare(_ key: String, build: @escaping Builder) async throws -> Runtime {
        try await runtime(for: key, request: .prepare(epoch: invalidationEpoch), build: build)
    }

    func transcribe(_ key: String, build: @escaping Builder) async throws -> Runtime {
        try await runtime(for: key, request: .transcribe, build: build)
    }
}

private final class FakeONNXRuntime: Sendable {}

private struct ONNXBuildFailure: Error {
    let label: String
}

private final class WeakONNXRuntime: @unchecked Sendable {
    private(set) weak var value: FakeONNXRuntime?

    init(_ value: FakeONNXRuntime) {
        self.value = value
    }
}

/// Stands in for a slow session build so tests control exactly when each one finishes.
private actor ONNXBuildGate {
    private var pending: [CheckedContinuation<FakeONNXRuntime, Error>] = []
    private(set) var startedCount = 0
    var pendingCount: Int { pending.count }

    func build() async throws -> FakeONNXRuntime {
        startedCount += 1
        // Ignores cancellation on purpose, like a native session build that cannot be interrupted.
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func completeNext(with result: Result<FakeONNXRuntime, Error>) {
        // A missed synchronisation has already failed the test; do not also trap the hosted process.
        guard !pending.isEmpty else {
            XCTFail("No build is waiting to be completed")
            return
        }
        pending.removeFirst().resume(with: result)
    }
}
