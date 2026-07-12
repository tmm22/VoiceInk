import AVFoundation
import Combine

extension TimeInterval {
    func formatTiming() -> String {
        if self < 1 {
            return String(format: "%.0fms", self * 1000)
        }
        if self < 60 {
            return String(format: "%.1fs", self)
        }
        let minutes = Int(self) / 60
        let seconds = truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }
}

final class WaveformGenerator {
    private final class Samples: NSObject {
        let values: [Float]

        init(_ values: [Float]) {
            self.values = values
        }
    }

    private static let cache: NSCache<NSString, Samples> = {
        let cache = NSCache<NSString, Samples>()
        cache.countLimit = 128
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    static func generateWaveformSamples(from url: URL, sampleCount: Int = 200) async -> [Float] {
        let cacheKey = "\(url.absoluteString)#\(sampleCount)" as NSString

        if let cachedSamples = cache.object(forKey: cacheKey) {
            return cachedSamples.values
        }

        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        let stride = max(1, Int(frameCount) / sampleCount)
        let bufferSize = min(UInt32(4096), frameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else { return [] }

        do {
            var maxValues = [Float](repeating: 0.0, count: sampleCount)
            var sampleIndex = 0
            var framePosition: AVAudioFramePosition = 0

            while sampleIndex < sampleCount && framePosition < AVAudioFramePosition(frameCount) {
                audioFile.framePosition = framePosition
                try audioFile.read(into: buffer)

                if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    maxValues[sampleIndex] = abs(channelData[0])
                    sampleIndex += 1
                }

                framePosition += AVAudioFramePosition(stride)
            }

            let normalizedSamples: [Float]
            if let maxSample = maxValues.max(), maxSample > 0 {
                normalizedSamples = maxValues.map { $0 / maxSample }
            } else {
                normalizedSamples = maxValues
            }

            cache.setObject(
                Samples(normalizedSamples),
                forKey: cacheKey,
                cost: normalizedSamples.count * MemoryLayout<Float>.stride
            )
            return normalizedSamples
        } catch {
            AppLogger.audio.error("Waveform generation failed: \(AppLogger.errorMetadata(error), privacy: .public)")
            return []
        }
    }
}

@MainActor
final class AudioPlayerManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isLoadingWaveform = true

            Task.detached { [weak self] in
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                Task { @MainActor [weak self] in
                    self?.updateWaveformSamples(samples)
                }
            }
        } catch {
            AppLogger.audio.error("Audio player failed to load audio: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        waveformSamples = []
        isLoadingWaveform = false
    }

    deinit {
        timer?.invalidate()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentTime = audioPlayer?.currentTime ?? 0
                if currentTime >= duration {
                    pause()
                    seek(to: 0)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateWaveformSamples(_ samples: [Float]) {
        waveformSamples = samples
        isLoadingWaveform = false
    }
}
