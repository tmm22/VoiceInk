import Foundation
import SwiftData
import os

private enum StreamingFinalizationWait {
    case provider(AsyncStream<String>)
    case committedEvent(AsyncStream<Void>)
}

/// Manages a streaming transcription lifecycle: buffers audio chunks, sends them to the provider, and collects the final text.
@MainActor
class StreamingTranscriptionService {

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "StreamingTranscriptionService")
    private var provider: StreamingTranscriptionProvider?
    private var sendTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private let chunkSource = AudioChunkSource()
    private var state: StreamingState = .idle
    private var committedSegments: [String] = []
    private let modelContext: ModelContext
    private let fluidAudioService: FluidAudioTranscriptionService?
    private var onPartialTranscript: ((String) -> Void)?
    private let metrics = StreamingMetrics()
    private var stopStartedAt: Date?
    private var firstPartialLogged = false
    private var firstCommitLogged = false
    private let finalizationTimeout: Duration
    /// Test seam; production always creates the provider from the model.
    private let providerFactory: ((any TranscriptionModel) -> StreamingTranscriptionProvider)?

    init(
        modelContext: ModelContext, fluidAudioService: FluidAudioTranscriptionService? = nil,
        onPartialTranscript: ((String) -> Void)? = nil, finalizationTimeout: Duration = .seconds(10),
        providerFactory: ((any TranscriptionModel) -> StreamingTranscriptionProvider)? = nil
    ) {
        self.modelContext = modelContext
        self.fluidAudioService = fluidAudioService
        self.onPartialTranscript = onPartialTranscript
        self.finalizationTimeout = finalizationTimeout
        self.providerFactory = providerFactory
    }

    deinit {
        onPartialTranscript = nil
        sendTask?.cancel()
        eventConsumerTask?.cancel()
        chunkSource.finish()
        commitSignal?.finish()
    }

    /// Signal used to notify `waitForFinalCommit` when a new committed segment arrives.
    private var commitSignal: AsyncStream<Void>.Continuation?

    /// Whether the streaming connection is fully established and actively sending.
    var isActive: Bool { state == .streaming || state == .committing }

    /// Start a streaming transcription session for the given model.
    func startStreaming(model: any TranscriptionModel, context: TranscriptionRequestContext) async throws {
        let start = Date()
        state = .connecting
        committedSegments = []
        metrics.reset()
        firstPartialLogged = false
        firstCommitLogged = false

        let provider = providerFactory?(model) ?? createProvider(for: model)
        self.provider = provider

        let selectedLanguage = context.language ?? "auto"
        logger.notice(
            "Streaming start requested model=\(model.displayName, privacy: .public) language=\(selectedLanguage, privacy: .public)"
        )

        try await provider.connect(model: model, language: selectedLanguage)

        // If cancel() was called while we were awaiting the connection, tear down immediately.
        if state == .cancelled {
            await provider.disconnect()
            self.provider = nil
            return
        }

        state = .streaming
        startSendLoop()
        startEventConsumer()

        logger.notice(
            "Streaming connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s"
        )
    }

    /// Buffers an audio chunk for sending. Safe to call from the recorder processing queue.
    nonisolated func sendAudioChunk(_ data: Data) {
        metrics.recordReceived(data.count)
        if !chunkSource.send(data) {
            metrics.recordDropped(data.count)
        }
    }

    /// Stops streaming and follows the provider's requested finalization path.
    func stopAndFinalize() async throws -> StreamingStopResult {
        guard let provider = provider, state == .streaming else {
            throw StreamingTranscriptionError.notConnected
        }

        if provider.stopDisposition == .useBatchFallback {
            logger.notice("Streaming provider requested full batch fallback")
            state = .done
            await cleanupStreaming()
            return .requiresBatchFallback
        }

        state = .committing
        stopStartedAt = Date()
        let beforeDrain = metrics.snapshot()
        logger.notice(
            "Streaming stop requested receivedChunks=\(beforeDrain.receivedChunks, privacy: .public) sentChunks=\(beforeDrain.sentChunks, privacy: .public) droppedChunks=\(beforeDrain.droppedChunks, privacy: .public) receivedBytes=\(beforeDrain.receivedBytes, privacy: .public) sentBytes=\(beforeDrain.sentBytes, privacy: .public) droppedBytes=\(beforeDrain.droppedBytes, privacy: .public)"
        )

        // Finish the chunk source so the send loop drains remaining chunks and exits naturally.
        await drainRemainingChunks()
        try throwIfCancelled()

        // Providers with a documented terminal acknowledgement expose an authoritative
        // full-transcript stream. All other providers retain the existing committed-event behavior.
        let finalizationWait: StreamingFinalizationWait
        if let finalizationEvents = provider.finalizationEvents {
            finalizationWait = .provider(finalizationEvents)
        } else {
            // Set up the commit signal BEFORE sending commit to avoid a race with the response.
            let (signalStream, signalContinuation) = AsyncStream.makeStream(of: Void.self)
            self.commitSignal = signalContinuation
            finalizationWait = .committedEvent(signalStream)
        }

        // Send commit to finalize any remaining audio
        do {
            try await provider.commit()
        } catch {
            // `cancel()` disconnects the provider, which can make an in-flight commit throw.
            try throwIfCancelled()
            commitSignal?.finish()
            commitSignal = nil
            logger.error("Failed to send commit: \(AppLogger.errorMetadata(error), privacy: .public)")
            state = .failed
            await cleanupStreaming()
            throw error
        }

        let finalText: String
        switch finalizationWait {
        case .provider(let events):
            let finalization = await waitForExplicitFinalization(events: events)
            // `cancel()` ends the wait early; a user cancel is neither a timeout nor a fallback request.
            try throwIfCancelled()
            guard finalization.received else {
                logger.warning("Provider did not confirm full stream finalization; using batch fallback")
                state = .done
                await cleanupStreaming()
                return .requiresBatchFallback
            }
            finalText = finalization.text
        case .committedEvent(let signalStream):
            let commit = await waitForFinalCommit(signalStream: signalStream)
            // `cancel()` finishes the commit signal; do not mistake that for a missed deadline.
            try throwIfCancelled()
            guard commit.received else {
                logger.warning("Provider did not acknowledge the final commit; preferring batch fallback")
                state = .done
                await cleanupStreaming()
                return .timedOut(partialText: commit.text)
            }
            finalText = commit.text
        }
        if let stopStartedAt {
            logger.notice(
                "Streaming stop completed elapsed=\(Date().timeIntervalSince(stopStartedAt), format: .fixed(precision: 3), privacy: .public)s finalChars=\(finalText.count, privacy: .public)"
            )
        }

        state = .done
        await cleanupStreaming()

        return .finalized(text: finalText)
    }

    /// `cancel()` already tore the session down; stop finalizing without starting any fallback.
    private func throwIfCancelled() throws {
        if state == .cancelled {
            logger.notice("Streaming stop abandoned because the session was cancelled")
            throw CancellationError()
        }
    }

    /// Cancels the streaming session without waiting for results.
    func cancel() {
        state = .cancelled
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()

        // Clean up commit signal if waiting
        commitSignal?.finish()
        commitSignal = nil

        let providerToDisconnect = provider
        provider = nil

        Task {
            await providerToDisconnect?.disconnect()
        }

        committedSegments = []
        logger.notice("Streaming cancelled")
    }

    // MARK: - Private

    private func createProvider(for model: any TranscriptionModel) -> StreamingTranscriptionProvider {
        if model.provider == .fluidAudio {
            if FluidAudioModelManager.isNemotronModel(named: model.name) {
                return FluidAudioNemotronStreamingProvider()
            }

            if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
                return FluidAudioUnifiedStreamingProvider()
            }

            guard let fluidAudioService else {
                fatalError(
                    "FluidAudioTranscriptionService required for FluidAudio streaming. Ensure it is passed to StreamingTranscriptionService."
                )
            }
            return FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        }
        guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider),
            let streamingProvider = cloudProvider.makeStreamingProvider(modelContext: modelContext)
        else {
            fatalError(
                "Unsupported streaming provider: \(model.provider). Check shouldUseRealtimeTranscription() before calling startStreaming()."
            )
        }
        return streamingProvider
    }

    /// Consumes audio chunks from the AsyncStream and sends them to the provider.
    private func startSendLoop() {
        let source = chunkSource
        let provider = provider
        let metrics = metrics
        let logger = logger

        sendTask = Task.detached {
            for await chunk in source.stream {
                do {
                    try await provider?.sendAudioChunk(chunk)
                    metrics.recordSent(chunk.count)
                } catch {
                    let errorType = String(describing: type(of: error))
                    logger.error("Failed to send audio chunk type=\(errorType, privacy: .public)")
                }
            }
        }
    }

    /// Finishes the chunk source and waits for the send loop to process all remaining buffered chunks.
    private func drainRemainingChunks() async {
        let start = Date()
        chunkSource.finish()
        await sendTask?.value
        sendTask = nil
        let snapshot = metrics.snapshot()
        logger.notice(
            "Streaming drain finished elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s receivedChunks=\(snapshot.receivedChunks, privacy: .public) sentChunks=\(snapshot.sentChunks, privacy: .public) droppedChunks=\(snapshot.droppedChunks, privacy: .public) receivedBytes=\(snapshot.receivedBytes, privacy: .public) sentBytes=\(snapshot.sentBytes, privacy: .public) droppedBytes=\(snapshot.droppedBytes, privacy: .public)"
        )
    }

    /// Consumes transcription events throughout the session, accumulating committed segments.
    private func startEventConsumer() {
        guard let provider = provider else { return }
        let events = provider.transcriptionEvents

        eventConsumerTask = Task.detached { [weak self] in
            for await event in events {
                guard let self = self else { break }
                switch event {
                case .committed(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !self.firstCommitLogged {
                            self.firstCommitLogged = true
                            let elapsed = self.stopStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                            self.logger.notice(
                                "Streaming first committed event chars=\(trimmed.count, privacy: .public) stopElapsed=\(elapsed, format: .fixed(precision: 3), privacy: .public)s"
                            )
                        }
                        if !trimmed.isEmpty {
                            self.committedSegments.append(trimmed)
                        }
                        // Refresh the live preview so it keeps showing the full running transcript
                        // after a commit (instead of resetting to empty until the next partial).
                        if self.state == .streaming {
                            self.onPartialTranscript?(self.committedSegments.joined(separator: " "))
                        }
                        if self.state == .committing {
                            self.commitSignal?.yield()
                        }
                    }
                case .partial(let text):
                    await MainActor.run {
                        if !self.firstPartialLogged {
                            self.firstPartialLogged = true
                            self.logger.notice("Streaming first partial event chars=\(text.count, privacy: .public)")
                        }
                        if self.state == .streaming {
                            let prefix = self.committedSegments.joined(separator: " ")
                            let display: String
                            if prefix.isEmpty {
                                display = text
                            } else if text.hasPrefix(prefix) || text.hasPrefix(prefix + " ") {
                                // Provider already sends cumulative partials (e.g. FluidAudio fullText).
                                display = text
                            } else {
                                display = prefix + " " + text
                            }
                            self.onPartialTranscript?(display)
                        }
                    }
                case .sessionStarted:
                    break
                case .error(let error):
                    await MainActor.run {
                        self.logger.error("Streaming event error: \(AppLogger.errorMetadata(error), privacy: .public)")
                    }
                }
            }
        }
    }

    /// Waits for the server to acknowledge our explicit commit, bounded by `finalizationTimeout` (10 s by default).
    private func waitForFinalCommit(signalStream: AsyncStream<Void>) async -> (received: Bool, text: String) {
        // Race: wait for commit acknowledgment vs timeout
        let timeout = finalizationTimeout
        let receivedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                for await _ in signalStream {
                    return true
                }
                return false
            }

            group.addTask {
                // Cancellation only means the acknowledgement won the race; either way this arm loses.
                try? await Task.sleep(for: timeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        logger.notice(
            "Streaming final wait finished received=\(receivedInTime, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)"
        )

        // Clean up the signal
        commitSignal?.finish()
        commitSignal = nil

        if !receivedInTime && committedSegments.isEmpty {
            logger.warning("No transcript received from streaming")
        }

        return (receivedInTime, committedSegments.isEmpty ? "" : committedSegments.joined(separator: " "))
    }

    /// Waits for a provider's documented end-of-stream acknowledgement and authoritative full transcript.
    private func waitForExplicitFinalization(events: AsyncStream<String>) async -> (received: Bool, text: String) {
        let timeout = finalizationTimeout
        let result = await withTaskGroup(of: (Bool, String).self) { group in
            group.addTask {
                for await text in events {
                    return (true, text)
                }
                return (false, "")
            }

            group.addTask {
                // Cancellation only means finalization won the race; either way this arm loses.
                try? await Task.sleep(for: timeout)
                return (false, "")
            }

            let result = await group.next() ?? (false, "")
            group.cancelAll()
            return result
        }

        logger.notice(
            "Streaming explicit finalization finished received=\(result.0, privacy: .public) chars=\(result.1.count, privacy: .public)"
        )
        return (result.0, result.1)
    }

    private func cleanupStreaming() async {
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()
        commitSignal?.finish()
        commitSignal = nil
        await provider?.disconnect()
        provider = nil
        state = .idle
        committedSegments = []
    }
}
