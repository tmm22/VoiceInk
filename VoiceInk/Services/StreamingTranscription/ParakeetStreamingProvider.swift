import AVFoundation
import FluidAudio
import Foundation
import os

/// On-device streaming transcription provider using FluidAudio's SlidingWindowAsrManager
/// with Parakeet TDT models (v2/v3).
final class ParakeetStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ParakeetStreaming")
    private let parakeetService: ParakeetTranscriptionService
    private var streamingManager: SlidingWindowAsrManager?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(parakeetService: ParakeetTranscriptionService) {
        self.parakeetService = parakeetService
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let version: AsrModelVersion = model.name.lowercased().contains("v2") ? .v2 : .v3
        let models = try await parakeetService.getOrLoadModels(for: version)

        let manager = SlidingWindowAsrManager(config: .streaming)
        try await manager.start(models: models)
        self.streamingManager = manager

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Parakeet streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let manager = streamingManager else {
            throw StreamingTranscriptionError.notConnected
        }

        guard let buffer = Self.convertToAudioBuffer(data) else {
            logger.error("Failed to create streaming audio buffer from PCM chunk")
            throw StreamingTranscriptionError.audioConversionFailed
        }
        await manager.streamAudio(buffer)
    }

    func commit() async throws {
        guard let manager = streamingManager else {
            throw StreamingTranscriptionError.notConnected
        }

        let finalText = try await manager.finish()
        eventsContinuation?.yield(.committed(text: finalText))
    }

    func disconnect() async {
        if let manager = streamingManager {
            await manager.cancel()
        }
        streamingManager = nil

        eventsContinuation?.finish()
        logger.notice("Parakeet streaming disconnected")
    }

    // MARK: - Private

    /// Converts raw PCM Int16 16kHz mono Data to a Float32 AVAudioPCMBuffer
    /// that FluidAudio's AudioConverter can process.
    /// Returns nil if the audio format or buffer cannot be created.
    private static func convertToAudioBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
              let channelData = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            let floatPtr = channelData[0]
            for i in 0..<sampleCount {
                floatPtr[i] = Float(int16Ptr[i]) / 32767.0
            }
        }

        return buffer
    }
}
