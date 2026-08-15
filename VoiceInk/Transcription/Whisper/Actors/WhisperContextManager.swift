import Foundation
import OSLog

/// The sole owner of local Whisper contexts and their inference lifetimes.
actor WhisperContextManager {
    private final class ContextLoad: @unchecked Sendable {
        let task: Task<WhisperContext, Error>
        var isInvalidated = false
        var didReleaseResult = false

        init(modelURL: URL) {
            task = Task {
                try await WhisperContext.createContext(path: modelURL.path)
            }
        }
    }

    static let shared = WhisperContextManager()

    private var contexts: [String: WhisperContext] = [:]
    private var contextLoads: [String: ContextLoad] = [:]
    private var activeInferenceCounts: [String: Int] = [:]
    private var retiringContexts: [String: [WhisperContext]] = [:]
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperContextManager")

    private init() {}

    func loadContext(for modelName: String, modelURL: URL) async throws -> WhisperContext {
        if let context = contexts[modelName] {
            return context
        }

        let load: ContextLoad
        if let existingLoad = contextLoads[modelName] {
            load = existingLoad
        } else {
            load = ContextLoad(modelURL: modelURL)
            contextLoads[modelName] = load
        }

        do {
            let context = try await load.task.value
            guard contextLoads[modelName] === load, !load.isInvalidated else {
                if !load.didReleaseResult {
                    load.didReleaseResult = true
                    await context.releaseResources()
                }
                throw CancellationError()
            }

            contexts[modelName] = context
            contextLoads[modelName] = nil
            logger.info("Loaded Whisper context for \(modelName, privacy: .public)")
            return context
        } catch {
            if contextLoads[modelName] === load {
                contextLoads[modelName] = nil
            }
            logger.error("Failed to load Whisper context for \(modelName, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)")
            throw error
        }
    }

    func performInference(
        modelName: String,
        modelURL: URL,
        audioURL: URL,
        language: String?,
        prompt: String?
    ) async throws -> String {
        let context = try await loadContext(for: modelName, modelURL: modelURL)
        activeInferenceCounts[modelName, default: 0] += 1

        do {
            let samples = try await Task.detached(priority: .userInitiated) {
                try AudioSampleReader.readPCM16LE(from: audioURL)
            }.value
            await context.setLanguage(language)
            await context.setPrompt(prompt ?? "")

            guard await context.fullTranscribe(samples: samples) else {
                throw WhisperContextError.transcriptionFailed
            }

            let transcription = await context.getTranscription()
            await finishInference(for: modelName)
            return transcription
        } catch {
            await finishInference(for: modelName)
            throw error
        }
    }

    func isContextLoaded(for modelName: String) -> Bool {
        contexts[modelName] != nil
    }

    func updatePrompt(_ prompt: String, for modelName: String) async {
        await contexts[modelName]?.setPrompt(prompt)
    }

    func unloadContext(for modelName: String) async {
        invalidateLoad(for: modelName)
        await retireContext(for: modelName)
    }

    func unloadAllContexts() async {
        let loadingModelNames = Array(contextLoads.keys)
        for modelName in loadingModelNames {
            invalidateLoad(for: modelName)
        }
        for modelName in Array(contexts.keys) {
            await retireContext(for: modelName)
        }
    }

    private func invalidateLoad(for modelName: String) {
        guard let load = contextLoads.removeValue(forKey: modelName) else { return }
        load.isInvalidated = true
        load.task.cancel()
    }

    private func retireContext(for modelName: String) async {
        guard let context = contexts.removeValue(forKey: modelName) else { return }
        if activeInferenceCounts[modelName, default: 0] > 0 {
            retiringContexts[modelName, default: []].append(context)
        } else {
            await context.releaseResources()
        }
    }

    private func finishInference(for modelName: String) async {
        let remaining = max(0, activeInferenceCounts[modelName, default: 1] - 1)
        if remaining == 0 {
            activeInferenceCounts[modelName] = nil
            for context in retiringContexts.removeValue(forKey: modelName) ?? [] {
                await context.releaseResources()
            }
        } else {
            activeInferenceCounts[modelName] = remaining
        }
    }
}

enum WhisperContextError: LocalizedError {
    case transcriptionFailed

    var errorDescription: String? {
        String(localized: "Whisper transcription failed")
    }
}
