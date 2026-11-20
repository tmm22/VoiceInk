import AVFoundation
import CoreML
import FluidAudio

enum FluidAudioSpeechFilter {
    static func loadLocalModel() async throws -> VadManager {
        let config = VadConfig(defaultThreshold: 0.7)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = config.computeUnits
        let model = try await MLModel.load(contentsOf: FluidAudioModelManager.vadModelURL, configuration: configuration)
        return VadManager(config: config, vadModel: model)
    }

    /// Keep VAD state across blocks, including speech that ends at EOF. The source and
    /// the filtered recording are disk-backed so a long dictation needs only one PCM buffer.
    static func writeSpeech(from input: URL, to output: URL, using manager: VadManager) async throws -> Bool {
        let rate = VadManager.sampleRate
        let (source, _) = try AudioSourceFactory().makeDiskBackedSource(from: input, targetSampleRate: rate)
        defer { source.cleanup() }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(VadManager.chunkSize)),
            let channel = buffer.floatChannelData?[0]
        else { throw ASRError.processingFailed("Unable to allocate speech filter buffer") }
        let file = try AVAudioFile(forWriting: output, settings: format.settings)
        var state = VadStreamState.initial()
        var start: Int?
        var lastEnd = 0

        func writeRange(endingAt end: Int) throws {
            guard let lower = start else { return }
            start = nil
            let upper = min(end, source.sampleCount)
            var offset = max(lower, lastEnd)
            guard offset < upper else { return }
            while offset < upper {
                try Task.checkCancellation()
                let count = min(upper - offset, Int(buffer.frameCapacity))
                try source.copySamples(into: channel, offset: offset, count: count)
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                offset += count
            }
            lastEnd = upper
        }

        for offset in stride(from: 0, to: source.sampleCount, by: VadManager.chunkSize) {
            try Task.checkCancellation()
            let count = min(source.sampleCount - offset, VadManager.chunkSize)
            try source.copySamples(into: channel, offset: offset, count: count)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            let result = try await manager.processStreamingChunk(samples, state: state)
            state = result.state
            if let event = result.event {
                switch event.kind {
                case .speechStart: start = event.sampleIndex
                case .speechEnd: try writeRange(endingAt: event.sampleIndex)
                }
            }
        }
        try writeRange(endingAt: source.sampleCount)
        guard file.length > 0 else { return false }

        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: rate)
        while file.length < minimum {
            let count = min(minimum - Int(file.length), Int(buffer.frameCapacity))
            channel.update(repeating: 0, count: count)
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
        }
        return true
    }
}
