import Foundation
import CoreML
import AVFoundation
import FluidAudio
import os.log

class ParakeetTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.parakeet", category: "ParakeetTranscriptionService")

    deinit {
        loadingTask?.task.cancel()
    }

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        model.name.lowercased().contains("v2") ? .v2 : .v3
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        await cleanupResources()

        let models = try await getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asrManager = manager
        self.activeVersion = version
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            return try await existingTask.value
        }

        let task = Task {
            try await AsrModels.loadFromCache(
                configuration: nil,
                version: version
            )
        }
        loadingTask = (version, task)

        do {
            let models = try await task.value
            self.cachedModels = models
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            return models
        } catch {
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            throw error
        }
    }

    func loadModel(for model: ParakeetModel) async throws {
        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let targetVersion = version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        var speechAudio = try await Task.detached(priority: .userInitiated) {
            try Self.readAudioSamples(from: audioURL)
        }.value

        let durationSeconds = Double(speechAudio.count) / 16000.0
        let isVADEnabled = UserDefaults.standard.bool(forKey: "IsVADEnabled")

        if durationSeconds >= 20.0, isVADEnabled {
            let vadConfig = VadConfig(defaultThreshold: 0.7)
            if vadManager == nil {
                do {
                    vadManager = try await VadManager(config: vadConfig)
                } catch {
                    logger.notice("VAD init failed; falling back to full audio: \(AppLogger.errorMetadata(error), privacy: .public)")
                    vadManager = nil
                }
            }

            if let vadManager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(speechAudio)
                    if !segments.isEmpty {
                        let sampleCount = segments.reduce(into: 0) { $0 += $1.count }
                        var segmentedAudio: [Float] = []
                        segmentedAudio.reserveCapacity(sampleCount)
                        for segment in segments {
                            segmentedAudio.append(contentsOf: segment)
                        }
                        speechAudio = segmentedAudio
                    }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(AppLogger.errorMetadata(error), privacy: .public)")
                }
            }
        }

        // Pad with 1s of silence to capture final punctuation at sequence boundary
        let trailingSilenceSamples = 16_000
        let maxSingleChunkSamples = 240_000
        if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
            speechAudio.reserveCapacity(speechAudio.count + trailingSilenceSamples)
            speechAudio.append(contentsOf: repeatElement(0, count: trailingSilenceSamples))
        }

        var decoderState = TdtDecoderState.make(
            decoderLayers: await asrManager.decoderLayerCount
        )
        let result = try await asrManager.transcribe(
            speechAudio,
            decoderState: &decoderState
        )

        return result.text
    }

    private static func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                // Best-effort close; the descriptor is also closed on deallocation.
                try? handle.close()
            }

            let fileSize = try handle.seekToEnd()
            guard fileSize > 44 else {
                throw ASRError.invalidAudioData
            }
            try handle.seek(toOffset: 44)

            var floats: [Float] = []
            floats.reserveCapacity(Int((fileSize - 44) / 2))

            while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
                data.withUnsafeBytes { rawBuffer in
                    let bytes = rawBuffer.bindMemory(to: UInt8.self)
                    for offset in stride(from: 0, to: bytes.count - 1, by: 2) {
                        let sample = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                        let short = Int16(bitPattern: sample)
                        floats.append(max(-1.0, min(Float(short) / 32767.0, 1.0)))
                    }
                }
            }

            return floats
        } catch {
            throw ASRError.invalidAudioData
        }
    }

    // Releases ASR/VAD resources but preserves cached models for reuse
    func cleanup() {
        Task {
            await cleanupResources()
        }
    }

    private func cleanupResources() async {
        await asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil
    }

}
