import Foundation
import OSLog

/// The sole owner of local Whisper contexts and their inference lifetimes.
actor WhisperContextManager {
    // All mutable generation state is accessed only by this manager actor.
    private final class Generation {
        let task: Task<any ManagedWhisperContext, Error>
        var context: (any ManagedWhisperContext)?
        var isInvalidated = false
        var didReleaseResult = false
        var activeInferenceCount = 0
        var loadWaiterCount = 0

        deinit { task.cancel() }

        init(modelURL: URL, loader: @escaping ContextLoader) {
            task = Task { try await loader(modelURL) }
        }
    }

    typealias ContextLoader = @Sendable (URL) async throws -> any ManagedWhisperContext
    typealias SampleLoader = @Sendable (URL) async throws -> [Float]

    static let shared = WhisperContextManager()

    private var generations: [String: Generation] = [:]
    private let contextLoader: ContextLoader
    private let sampleLoader: SampleLoader
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "WhisperContextManager")

    init(
        contextLoader: @escaping ContextLoader = { try await WhisperContext.createContext(path: $0.path) },
        sampleLoader: @escaping SampleLoader = { audioURL in
            try await Task.detached(priority: .userInitiated) {
                try AudioSampleReader.readPCM16LE(from: audioURL)
            }.value
        }
    ) {
        self.contextLoader = contextLoader
        self.sampleLoader = sampleLoader
    }

    func loadContext(for modelName: String, modelURL: URL) async throws -> any ManagedWhisperContext {
        let generation = try await loadGeneration(for: modelName, modelURL: modelURL)
        try Task.checkCancellation()
        guard !generation.isInvalidated, let context = generation.context else {
            throw CancellationError()
        }
        return context
    }

    private func loadGeneration(for modelName: String, modelURL: URL) async throws -> Generation {
        try Task.checkCancellation()
        let generation: Generation
        if let existing = generations[modelName] {
            generation = existing
        } else {
            generation = Generation(modelURL: modelURL, loader: contextLoader)
            generations[modelName] = generation
        }

        generation.loadWaiterCount += 1
        defer { generation.loadWaiterCount -= 1 }
        let context: any ManagedWhisperContext
        do {
            context = try await generation.task.value
        } catch {
            // A failed old load must never remove a replacement generation.
            if generations[modelName] === generation {
                generations[modelName] = nil
            }
            if error is CancellationError {
                logger.notice("Whisper context load for \(modelName, privacy: .public) was cancelled before completion")
            } else {
                logger.error("Failed to load Whisper context for \(modelName, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)")
            }
            throw error
        }

        // Keep publication distinct from invalidation. Every waiter on a successful
        // generation receives the same live context, including after publication.
        if generation.context == nil {
            generation.context = context
        }
        guard !generation.isInvalidated else {
            await releaseIfRetired(generation)
            throw CancellationError()
        }
        // Cancelling one waiter does not cancel a shared load or discard its cache.
        // The cancelled waiter finishes after the shared loader completes.
        try Task.checkCancellation()
        return generation
    }

    func performInference(
        modelName: String,
        modelURL: URL,
        audioURL: URL,
        language: String?,
        prompt: String?
    ) async throws -> String {
        let generation = try await loadGeneration(for: modelName, modelURL: modelURL)
        try Task.checkCancellation()
        // Unload may run while loadGeneration returns across an actor suspension.
        // Acquire the inference lifetime without another suspension after this check.
        guard !generation.isInvalidated, let context = generation.context else {
            throw CancellationError()
        }
        generation.activeInferenceCount += 1

        do {
            let samples = try await sampleLoader(audioURL)
            try Task.checkCancellation()
            let transcription = try await context.transcribe(samples: samples, language: language, prompt: prompt)
            try Task.checkCancellation()
            await finishInference(generation)
            return transcription
        } catch {
            await finishInference(generation)
            throw error
        }
    }

    /// Also used to synchronize race tests without scheduler-dependent sleeps.
    func pendingLoadWaiterCount(for modelName: String) -> Int {
        generations[modelName]?.loadWaiterCount ?? 0
    }

    func isContextLoaded(for modelName: String) -> Bool {
        generations[modelName]?.context != nil
    }

    func unloadContext(for modelName: String) async {
        guard let generation = generations.removeValue(forKey: modelName) else { return }
        invalidate(generation)
        await releaseIfRetired(generation)
    }

    func unloadAllContexts() async {
        await unloadAllContexts(except: nil)
    }

    /// Retires every model except `keptModelName`, so switching to an already prewarmed model reuses
    /// its live generation instead of unloading and rebuilding it.
    func unloadAllContexts(except keptModelName: String?) async {
        // Detach and invalidate the entire snapshot before any release suspends.
        // Loads started afterward belong to a new generation and remain untouched.
        let retiredNames = generations.keys.filter { $0 != keptModelName }
        let retired = retiredNames.compactMap { generations.removeValue(forKey: $0) }
        for generation in retired {
            invalidate(generation)
        }
        for generation in retired {
            await releaseIfRetired(generation)
        }
    }

    private func invalidate(_ generation: Generation) {
        generation.isInvalidated = true
        generation.task.cancel()
    }

    private func finishInference(_ generation: Generation) async {
        generation.activeInferenceCount -= 1
        await releaseIfRetired(generation)
    }

    private func releaseIfRetired(_ generation: Generation) async {
        guard generation.isInvalidated,
              generation.activeInferenceCount == 0,
              !generation.didReleaseResult,
              let context = generation.context else { return }
        // Claim release before awaiting so other waiters cannot release it twice.
        generation.didReleaseResult = true
        await context.releaseResources()
    }
}

enum WhisperContextError: LocalizedError {
    case transcriptionFailed

    var errorDescription: String? {
        String(localized: "Whisper transcription failed")
    }
}
