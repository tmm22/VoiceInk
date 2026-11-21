import Foundation

// MARK: - Shared ONNX runtime cache

/// Thrown to a record-start prepare that must not start a session build: either a cleanup landed after
/// the prepare was requested, or invalidated builds are still running and it would stack on top of them.
/// Harmless: the transcription builds the runtime itself, as before.
struct ONNXRuntimeBuildDeferredError: Error {}

/// Single-flight, generation-safe cache for a model's ONNX runtime (the session plus the metadata and
/// tokenizer built with it), keyed by model name. Shared by the FastConformer and SenseVoice services.
///
/// - Concurrent requests for one model share a single identity-tracked build, so a record-start
///   prepare and the transcription that follows never construct two sessions.
/// - `invalidate(_:)` / `invalidateAll()` detach in-flight builds. A build that finishes afterwards is
///   still handed to the callers already awaiting it, but it is never cached and is released once they
///   are done with it. It can neither replace nor remove a newer build for the same model.
/// - An invalidation also cancels prepares that were requested before it but have not started their
///   build yet, so nothing a cleanup was meant to cover can be cached after it.
/// - Session builds cannot be interrupted, so a prepare never starts one while detached builds are still
///   running. Repeatedly aborted recordings therefore cannot pile up builds of a large model.
/// - A failed build caches nothing, so the next request builds again.
final class ONNXRuntimeCache<Runtime>: @unchecked Sendable {
    typealias Builder = @Sendable () async throws -> Runtime

    enum Request {
        /// Record-start warm-up, carrying the `invalidationEpoch` read when it was requested. Shares a
        /// cached runtime or an in-flight build, but only starts a build if nothing has been invalidated
        /// since that epoch and no detached build is still running.
        case prepare(epoch: Int)
        /// A transcription that needs the runtime now. If it joined a build someone else started and
        /// that build fails, it builds once more so it surfaces the error of its own attempt.
        case transcribe

        fileprivate var retriesJoinedFailure: Bool {
            if case .transcribe = self { return true }
            return false
        }
    }

    /// Reference identity is the generation of one build.
    private final class Generation: Sendable {}

    /// Carries a runtime out of its build task. ONNX Runtime sessions are safe to share across threads
    /// but are not annotated `Sendable`.
    private struct Built: @unchecked Sendable {
        let runtime: Runtime
    }

    private struct InFlightBuild {
        let generation: Generation
        let task: Task<Built, Error>
        var requestCount: Int
    }

    private enum Lookup {
        case cached(Runtime)
        case building(Task<Built, Error>, joined: Bool)
    }

    // Guards the state below. Never held while a runtime is being built.
    private let lock = NSLock()
    private var runtimes: [String: Runtime] = [:]
    private var inFlightBuilds: [String: InFlightBuild] = [:]
    /// Builds that were invalidated while running and have not finished yet.
    private var detachedBuildCount = 0
    /// Incremented by every invalidation.
    private var epoch = 0

    deinit {
        for build in inFlightBuilds.values {
            build.task.cancel()
        }
    }

    /// Returns the cached runtime for `key`, joins the build already in flight for it, or starts one.
    func runtime(for key: String, request: Request, build: @escaping Builder) async throws -> Runtime {
        try await runtime(
            for: key, request: request, retryingJoinedFailure: request.retriesJoinedFailure, build: build)
    }

    /// Changes with every invalidation. A prepare reads it at the moment it is requested (for the
    /// registry, on the main actor that also runs cleanup) and passes it in `Request.prepare`.
    var invalidationEpoch: Int {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    /// Drops the cached runtime for `key` and detaches any build in flight for it.
    func invalidate(_ key: String) {
        lock.lock()
        let releasedRuntime = runtimes.removeValue(forKey: key)
        let detachedBuild = inFlightBuilds.removeValue(forKey: key)
        if detachedBuild != nil {
            detachedBuildCount += 1
        }
        epoch &+= 1
        lock.unlock()
        // Released after unlocking so tearing a session down never extends the critical section.
        withExtendedLifetime((releasedRuntime, detachedBuild)) {}
    }

    /// Drops every cached runtime and detaches every build in flight.
    func invalidateAll() {
        lock.lock()
        let releasedRuntimes = runtimes
        let detachedBuilds = inFlightBuilds
        runtimes.removeAll()
        inFlightBuilds.removeAll()
        detachedBuildCount += detachedBuilds.count
        epoch &+= 1
        lock.unlock()
        // Released after unlocking so tearing sessions down never extends the critical section.
        withExtendedLifetime((releasedRuntimes, detachedBuilds)) {}
    }

    func hasCachedRuntime(for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[key] != nil
    }

    /// Callers that started or joined the build currently in flight for `key`; 0 when there is none.
    /// Also used to synchronize race tests without scheduler-dependent sleeps.
    func inFlightRequestCount(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlightBuilds[key]?.requestCount ?? 0
    }

    /// Invalidated builds that are still running. Also used to synchronize race tests.
    var runningDetachedBuildCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return detachedBuildCount
    }

    private func runtime(
        for key: String,
        request: Request,
        retryingJoinedFailure: Bool,
        build: @escaping Builder
    ) async throws -> Runtime {
        switch try lookUpOrStartBuild(for: key, request: request, build: build) {
        case .cached(let runtime):
            return runtime
        case .building(let task, let joined):
            do {
                return try await task.value.runtime
            } catch {
                guard joined, retryingJoinedFailure else { throw error }
                return try await runtime(for: key, request: request, retryingJoinedFailure: false, build: build)
            }
        }
    }

    private func lookUpOrStartBuild(for key: String, request: Request, build: @escaping Builder) throws -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        if let runtime = runtimes[key] {
            return .cached(runtime)
        }
        if let existing = inFlightBuilds[key] {
            inFlightBuilds[key]?.requestCount += 1
            return .building(existing.task, joined: true)
        }
        if case .prepare(let requestEpoch) = request, requestEpoch != epoch || detachedBuildCount > 0 {
            throw ONNXRuntimeBuildDeferredError()
        }

        let generation = Generation()
        // Unstructured so the build outlives any single caller and runs off the caller's actor.
        // The task cannot finish before it is registered: finishing needs the lock held here.
        let task = Task<Built, Error> { [weak self] in
            do {
                let runtime = try await build()
                self?.finishBuild(generation, for: key, runtime: runtime)
                return Built(runtime: runtime)
            } catch {
                self?.finishBuild(generation, for: key, runtime: nil)
                throw error
            }
        }
        inFlightBuilds[key] = InFlightBuild(generation: generation, task: task, requestCount: 1)
        return .building(task, joined: false)
    }

    private func finishBuild(_ generation: Generation, for key: String, runtime: Runtime?) {
        lock.lock()
        defer { lock.unlock() }
        guard inFlightBuilds[key]?.generation === generation else {
            // Invalidated while it ran: never cached, and whatever replaced it is left untouched.
            detachedBuildCount -= 1
            return
        }
        inFlightBuilds[key] = nil
        if let runtime {
            runtimes[key] = runtime
        }
    }
}
