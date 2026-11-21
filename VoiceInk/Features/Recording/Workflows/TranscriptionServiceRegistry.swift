import Foundation
import SwiftData
import SwiftUI
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    // Optional backing instead of `lazy var`, so `cleanup()` can skip services that were never used
    // rather than constructing them just to clear empty caches.
    // Readable (not writable) outside the type so tests can assert nothing was created.
    private(set) var cachedFluidAudioTranscriptionService: FluidAudioTranscriptionService?
    private(set) var cachedFastConformerTranscriptionService: FastConformerTranscriptionService?
    private(set) var cachedSenseVoiceTranscriptionService: SenseVoiceTranscriptionService?
    private var cachedTranscribeCppTranscriptionService: TranscribeCppTranscriptionService?

    var fluidAudioTranscriptionService: FluidAudioTranscriptionService {
        if let cachedFluidAudioTranscriptionService {
            return cachedFluidAudioTranscriptionService
        }
        let service = FluidAudioTranscriptionService()
        cachedFluidAudioTranscriptionService = service
        return service
    }

    var fastConformerTranscriptionService: FastConformerTranscriptionService {
        if let cachedFastConformerTranscriptionService {
            return cachedFastConformerTranscriptionService
        }
        let service = FastConformerTranscriptionService(
            modelsDirectory: ONNXLocalModelManager.shared.modelsDirectory(for: .fastConformer)
        )
        cachedFastConformerTranscriptionService = service
        return service
    }

    var senseVoiceTranscriptionService: SenseVoiceTranscriptionService {
        if let cachedSenseVoiceTranscriptionService {
            return cachedSenseVoiceTranscriptionService
        }
        let service = SenseVoiceTranscriptionService(
            modelsDirectory: ONNXLocalModelManager.shared.modelsDirectory(for: .senseVoice)
        )
        cachedSenseVoiceTranscriptionService = service
        return service
    }

    var transcribeCppTranscriptionService: TranscribeCppTranscriptionService {
        if let cachedTranscribeCppTranscriptionService {
            return cachedTranscribeCppTranscriptionService
        }
        let service = TranscribeCppTranscriptionService()
        cachedTranscribeCppTranscriptionService = service
        return service
    }

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .transcribeCpp:
            return transcribeCppTranscriptionService
        case .fastConformer:
            return fastConformerTranscriptionService
        case .senseVoice:
            return senseVoiceTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(
        audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext = .currentDefaults
    ) async throws -> String {
        let service = service(for: model.provider)
        logger.debug(
            "Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)"
        )
        return try await service.transcribe(audioURL: audioURL, model: model, context: context.scoped(to: model))
    }

    /// Loads the runtime for `model` without transcribing anything, so the first real request
    /// skips model load. Cloud and Apple providers load per request, and the ONNX and TranscribeCpp
    /// runtimes are built for one recording at record start (see `prepareONNXRuntimeIfNeeded(for:)`)
    /// and released after it, so all of those are intentionally left alone here.
    func prewarm(model: any TranscriptionModel) async throws {
        switch model.provider {
        case .whisper:
            try await localTranscriptionService.prepareModel(model)
        case .fluidAudio:
            try await fluidAudioTranscriptionService.prepareModels(for: model)
        default:
            logger.debug("No prewarm path for provider \(model.provider.rawValue, privacy: .public)")
        }
    }

    /// Builds the ONNX session for FastConformer / SenseVoice models at record start so the
    /// post-recording transcription does not pay for it. No-op for every other provider.
    func prepareONNXRuntimeIfNeeded(for model: any TranscriptionModel) async {
        do {
            // The epoch is read here, on the main actor that also runs `cleanup()`, before the build
            // moves off it: a cleanup from this point on cancels the prepare instead of racing it.
            switch model.provider {
            case .fastConformer:
                let service = fastConformerTranscriptionService
                try await service.prepare(model, requestedAt: service.invalidationEpoch)
            case .senseVoice:
                let service = senseVoiceTranscriptionService
                try await service.prepare(model, requestedAt: service.invalidationEpoch)
            default:
                return
            }
        } catch {
            // Harmless: nothing was cached, so transcription builds the session and reports errors itself.
            logger.notice(
                "ONNX runtime was not prepared for \(model.name, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }

    /// Creates a streaming or file-based session for the resolved transcription configuration.
    func createSession(
        for configuration: TranscriptionRuntimeConfiguration, onPartialTranscript: ((String) -> Void)? = nil
    ) -> TranscriptionSession {
        let model = configuration.model

        if shouldUseRealtimeTranscription(for: configuration) {
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    /// Whether the resolved transcription configuration should use real-time transcription.
    func shouldUseRealtimeTranscription(for configuration: TranscriptionRuntimeConfiguration) -> Bool {
        configuration.isRealtimeEnabled
    }

    /// Releases loaded runtimes. Touches only services that already exist, never creating one.
    /// Drops ONNX sessions built by `prepareONNXRuntimeIfNeeded(for:)` when the recording they were
    /// built for ends without transcribing, so nothing stays resident while idle. Never constructs
    /// a service.
    func releaseONNXRuntimes() {
        cachedFastConformerTranscriptionService?.cleanup()
        cachedSenseVoiceTranscriptionService?.cleanup()
    }

    func cleanup() async {
        await cachedFluidAudioTranscriptionService?.cleanup()
        cachedFastConformerTranscriptionService?.cleanup()
        cachedSenseVoiceTranscriptionService?.cleanup()
        cachedTranscribeCppTranscriptionService?.cleanup()
    }
}
