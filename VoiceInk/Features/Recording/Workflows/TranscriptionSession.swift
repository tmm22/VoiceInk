import Foundation
import os

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(configuration: TranscriptionRuntimeConfiguration) async throws -> ((Data) -> Void)?

    /// Called after recording stops. Returns the final transcribed text.
    func transcribe(audioURL: URL) async throws -> String

    /// Cancel the session and clean up resources.
    func cancel()

    /// Forces finalization through the complete on-disk recording.
    func requireBatchFallback()
}

// MARK: - File-Based Session

/// File-based session: records to file, uploads after stop.
@MainActor
final class FileTranscriptionSession: TranscriptionSession {
    private let service: TranscriptionService
    private var model: (any TranscriptionModel)?
    private var context: TranscriptionRequestContext = .currentDefaults

    init(service: TranscriptionService) {
        self.service = service
    }

    func prepare(configuration: TranscriptionRuntimeConfiguration) async throws -> ((Data) -> Void)? {
        self.model = configuration.model
        self.context = configuration.requestContext.scoped(to: configuration.model)
        return nil
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }
        return try await service.transcribe(audioURL: audioURL, model: model, context: context)
    }

    func cancel() {
        // No-op for file-based transcription
    }

    func requireBatchFallback() {}
}

// MARK: - Streaming Session

/// Streaming session with automatic fallback to file-based upload on failure.
@MainActor
final class StreamingTranscriptionSession: TranscriptionSession {
    private let streamingService: StreamingTranscriptionService
    private let fallbackService: TranscriptionService
    private var model: (any TranscriptionModel)?
    private var context: TranscriptionRequestContext = .currentDefaults
    private var streamingFailed = false
    /// Set by `cancel()`; a cancelled session never starts a batch upload.
    private var wasCancelled = false
    private var startupTask: Task<Void, Never>?
    private var startupTaskID: UUID?
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    func prepare(configuration: TranscriptionRuntimeConfiguration) async throws -> ((Data) -> Void)? {
        let model = configuration.model
        let context = configuration.requestContext.scoped(to: model)

        self.model = model
        self.context = context
        wasCancelled = false
        logger.notice("Streaming session prepare model=\(model.displayName, privacy: .public)")

        // Return callback immediately; WebSocket connects in background
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        startupTask?.cancel()
        let taskID = UUID()
        startupTaskID = taskID
        startupTask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                if self.startupTaskID == taskID {
                    self.startupTask = nil
                    self.startupTaskID = nil
                }
            }
            guard !Task.isCancelled else { return }

            do {
                let start = Date()
                try await self.streamingService.startStreaming(model: model, context: context)
                guard !Task.isCancelled else {
                    self.streamingService.cancel()
                    return
                }
                self.logger.notice(
                    "Streaming session connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s"
                )
            } catch is CancellationError {
                self.streamingService.cancel()
            } catch {
                guard !Task.isCancelled else { return }
                let desc = error.localizedDescription
                self.logger.error("❌ Failed to start streaming, will fall back to batch: \(desc, privacy: .public)")
                self.streamingFailed = true
            }
        }

        return callback
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        if !streamingFailed {
            do {
                let start = Date()
                logger.notice("Streaming stop/transcribe started model=\(model.displayName, privacy: .public)")
                let result = try await streamingService.stopAndFinalize()
                switch result {
                case .finalized(let text):
                    logger.notice(
                        "Streaming transcript received elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)"
                    )
                    return text
                case .requiresBatchFallback:
                    logger.notice("Streaming provider requested full batch transcription")
                case .timedOut(let partialText):
                    return try await Self.transcribeAfterStreamingTimeout(
                        partialText: partialText,
                        canTranscribeInBatch: Self.supportsBatchFallback(model),
                        fallback: { [fallbackService, context] in
                            try await fallbackService.transcribe(audioURL: audioURL, model: model, context: context)
                        },
                        logger: logger
                    )
                }
            } catch is CancellationError {
                // A cancelled session must not fall through to a batch upload.
                startupTask?.cancel()
                startupTask = nil
                startupTaskID = nil
                streamingService.cancel()
                throw CancellationError()
            } catch {
                logger.error("❌ Streaming failed, falling back to batch: \(AppLogger.errorMetadata(error), privacy: .public)")
                startupTask?.cancel()
                startupTask = nil
                startupTaskID = nil
                streamingService.cancel()
            }
        } else {
            startupTask?.cancel()
            startupTask = nil
            startupTaskID = nil
            streamingService.cancel()
        }

        // Streaming errors caused by a cancel (for example a disconnect during commit) are not
        // failures to recover from.
        if wasCancelled || Task.isCancelled {
            throw CancellationError()
        }
        let fallbackStart = Date()
        logger.notice(
            "Using batch fallback for \(model.displayName, privacy: .public) file=\(audioURL.lastPathComponent, privacy: .public)"
        )
        let text = try await fallbackService.transcribe(audioURL: audioURL, model: model, context: context)
        logger.notice(
            "Batch fallback completed elapsed=\(Date().timeIntervalSince(fallbackStart), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)"
        )
        return text
    }

    func cancel() {
        wasCancelled = true
        startupTask?.cancel()
        startupTask = nil
        startupTaskID = nil
        streamingService.cancel()
    }

    /// A stream that missed its final acknowledgement may be truncated, so transcribe the complete
    /// recording instead. If that also fails, keep the previous behaviour and return whatever the
    /// stream committed, rather than turning a partial transcript into a failure.
    static func transcribeAfterStreamingTimeout(
        partialText: String,
        canTranscribeInBatch: Bool,
        fallback: () async throws -> String,
        logger: Logger
    ) async throws -> String {
        guard canTranscribeInBatch else {
            logger.warning("Streaming-only provider missed its final commit; using committed text chars=\(partialText.count, privacy: .public)")
            return partialText
        }
        try Task.checkCancellation()
        do {
            let text = try await fallback()
            logger.notice("Batch transcription replaced a timed-out stream chars=\(text.count, privacy: .public)")
            return text
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw CancellationError() }
            logger.error(
                "Batch fallback after streaming timeout failed; using committed streaming text chars=\(partialText.count, privacy: .public) error=\(AppLogger.errorMetadata(error), privacy: .public)"
            )
            return partialText
        }
    }

    /// Streaming-only cloud providers (for example Cartesia) have no batch endpoint to fall back to.
    static func supportsBatchFallback(_ model: any TranscriptionModel) -> Bool {
        !(CloudProviderRegistry.provider(for: model.provider)?.isStreamingOnly ?? false)
    }

    /// Cloud services wrap cancellation in their own network error.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case CloudTranscriptionError.networkError(let underlying) = error { return isCancellation(underlying) }
        return false
    }

    func requireBatchFallback() {
        streamingFailed = true
        startupTask?.cancel()
        startupTask = nil
        startupTaskID = nil
        streamingService.cancel()
    }
}
