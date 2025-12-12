import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import os

@MainActor
class AudioEngineRecorder: ObservableObject {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AudioEngineRecorder")

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var recordingFormat: AVAudioFormat?
    nonisolated(unsafe) private var converter: AVAudioConverter?

    private var isRecording = false
    private var recordingURL: URL?

    @Published var currentAveragePower: Float = 0.0
    @Published var currentPeakPower: Float = 0.0

    private let tapBufferSize: AVAudioFrameCount = 4096
    private let tapBusNumber: AVAudioNodeBus = 0

    private let audioProcessingQueue = DispatchQueue(label: "com.tmm22.voicelinkcommunity.audioProcessing", qos: .userInitiated)
    private let fileWriteLock = NSLock()

    // Callback to notify parent class of runtime recording errors
    var onRecordingError: ((Error) -> Void)?

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    @objc private func handleConfigurationChange(notification: Notification) {
        Task { @MainActor in
            guard isRecording else { return }
            logger.info("⚠️ AVAudioEngine configuration change detected (e.g. sample rate change). Restarting engine...")
            do {
                try restartRecordingPreservingFile()
            } catch {
                logger.error("Failed to recover from configuration change: \(error.localizedDescription)")
                onRecordingError?(error)
                stopRecording()
            }
        }
    }

    func startRecording(toOutputFile url: URL) throws {
        logger.info("Starting recording to: \(url.path)")

        stopRecording()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let inputFormat = input.outputFormat(forBus: tapBusNumber)

        logger.info("Input format - Sample Rate: \(inputFormat.sampleRate), Channels: \(inputFormat.channelCount)")

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("Invalid input format: sample rate or channel count is zero")
            throw AudioEngineRecorderError.invalidInputFormat
        }

        // 16kHz, 16-bit PCM, mono
        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("Failed to create desired recording format")
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        recordingFormat = desiredFormat
        recordingURL = url

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            audioFile = try AVAudioFile(
                forWriting: url,
                settings: desiredFormat.settings,
                commonFormat: desiredFormat.commonFormat,
                interleaved: desiredFormat.isInterleaved
            )

            logger.info("Created audio file for writing")
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
            throw AudioEngineRecorderError.failedToCreateFile(error)
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            logger.error("Failed to create audio format converter")
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        converter = audioConverter

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }

            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        engine.prepare()

        do {
            try engine.start()
            isRecording = true
            logger.info("✅ Audio engine started successfully")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            input.removeTap(onBus: tapBusNumber)
            throw AudioEngineRecorderError.failedToStartEngine(error)
        }
    }

    func stopRecording() {
        logger.info("Stopping recording")

        guard isRecording else {
            logger.info("Not currently recording, nothing to stop")
            return
        }

        if let input = inputNode {
            input.removeTap(onBus: tapBusNumber)
            logger.info("Removed tap from input node")
        }

        audioEngine?.stop()
        logger.info("Audio engine stopped")

        fileWriteLock.lock()
        audioFile = nil
        fileWriteLock.unlock()

        audioEngine = nil
        inputNode = nil
        recordingFormat = nil
        recordingURL = nil
        converter = nil
        isRecording = false

        currentAveragePower = 0.0
        currentPeakPower = 0.0

        logger.info("✅ Recording stopped and cleaned up")
    }

    private func restartRecordingPreservingFile() throws {
        guard let url = recordingURL else {
            throw AudioEngineRecorderError.invalidInputFormat
        }

        // Remove old tap
        inputNode?.removeTap(onBus: tapBusNumber)
        audioEngine?.stop()

        // Create new engine
        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let inputFormat = input.outputFormat(forBus: tapBusNumber)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioEngineRecorderError.invalidInputFormat
        }

        guard let desiredFormat = recordingFormat else {
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        converter = audioConverter

        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        engine.prepare()
        try engine.start()

        logger.info("✅ Audio engine restarted after configuration change")
    }

    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        updateMeters(from: buffer)
        writeBufferToFile(buffer)
    }

    nonisolated private func writeBufferToFile(_ buffer: AVAudioPCMBuffer) {
        fileWriteLock.lock()
        guard let audioFile = audioFile,
              let converter = converter,
              let format = recordingFormat else {
            fileWriteLock.unlock()
            return
        }

        let inputSampleRate = buffer.format.sampleRate
        let outputSampleRate = format.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
            fileWriteLock.unlock()
            logger.error("Failed to create converted buffer")
            return
        }

        var error: NSError?

        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            fileWriteLock.unlock()
            logger.error("Audio conversion error: \(error.localizedDescription)")
            return
        }

        do {
            try audioFile.write(from: convertedBuffer)
            fileWriteLock.unlock()
        } catch {
            fileWriteLock.unlock()
            logger.error("Failed to write buffer to file: \(error.localizedDescription)")
        }
    }

    nonisolated private func updateMeters(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard channelCount > 0, frameLength > 0 else { return }

        let channel = channelData[0]
        var sum: Float = 0.0
        var peak: Float = 0.0

        for frame in 0..<frameLength {
            let sample = channel[frame]
            let absSample = abs(sample)

            if absSample > peak {
                peak = absSample
            }

            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))

        // Convert to decibels: 20 * log10(value)
        let averagePowerDb = 20.0 * log10(max(rms, 0.000001))
        let peakPowerDb = 20.0 * log10(max(peak, 0.000001))

        Task { @MainActor in
            self.currentAveragePower = averagePowerDb
            self.currentPeakPower = peakPowerDb
        }
    }

    var isCurrentlyRecording: Bool {
        return isRecording
    }

    var currentRecordingURL: URL? {
        return recordingURL
    }

    deinit {
        // Cannot call @MainActor methods from deinit
        // Direct cleanup is safe for these properties
        if isRecording {
            inputNode?.removeTap(onBus: tapBusNumber)
            audioEngine?.stop()
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Error Types

enum AudioEngineRecorderError: LocalizedError {
    case invalidInputFormat
    case invalidRecordingFormat
    case failedToCreateFile(Error)
    case failedToCreateConverter
    case failedToStartEngine(Error)

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Invalid audio input format from device"
        case .invalidRecordingFormat:
            return "Failed to create recording format"
        case .failedToCreateFile(let error):
            return "Failed to create audio file: \(error.localizedDescription)"
        case .failedToCreateConverter:
            return "Failed to create audio format converter"
        case .failedToStartEngine(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
}
