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
    private var isTapInstalled = false
    private var recordingGeneration: UUID?

    @Published var currentAveragePower: Float = 0.0
    @Published var currentPeakPower: Float = 0.0

    private let tapBufferSize: AVAudioFrameCount = 4096
    private let tapBusNumber: AVAudioNodeBus = 0

    private var bufferDispatcher: BoundedAudioBufferDispatcher?
    private let fileWriteLock = NSLock()
    private var meterTimer: Timer?
    private let meterState = OSAllocatedUnfairLock(initialState: (average: Float(0), peak: Float(0), isDirty: false))

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
        let generation = recordingGeneration
        Task { @MainActor in
            guard isRecording, recordingGeneration == generation else { return }
            logger.info("⚠️ AVAudioEngine configuration change detected (e.g. sample rate change). Restarting engine...")
            do {
                try restartRecordingPreservingFile()
            } catch {
                logger.error("Failed to recover from configuration change: \(AppLogger.errorMetadata(error), privacy: .public)")
                let errorHandler = onRecordingError
                stopRecording()
                errorHandler?(error)
            }
        }
    }

    func startRecording(toOutputFile url: URL) throws {
        stopRecording()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let inputFormat = input.outputFormat(forBus: tapBusNumber)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("Invalid input format: sample rate or channel count is zero")
            throw AudioEngineRecorderError.invalidInputFormat
        }

        // 16kHz, 16-bit PCM, mono - required format for Whisper
        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("Failed to create desired recording format")
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        recordingURL = url
        recordingGeneration = UUID()

        let createdAudioFile: AVAudioFile
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            createdAudioFile = try AVAudioFile(
                forWriting: url,
                settings: desiredFormat.settings,
                commonFormat: desiredFormat.commonFormat,
                interleaved: desiredFormat.isInterleaved
            )
        } catch {
            logger.error("Failed to create audio file: \(AppLogger.errorMetadata(error), privacy: .public)")
            stopRecording()
            throw AudioEngineRecorderError.failedToCreateFile(error)
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            logger.error("Failed to create audio format converter")
            stopRecording()
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        // Thread-safe assignment of shared resources
        fileWriteLock.lock()
        recordingFormat = desiredFormat
        audioFile = createdAudioFile
        converter = audioConverter
        fileWriteLock.unlock()

        guard let dispatcher = makeBufferDispatcher(inputFormat: inputFormat) else {
            stopRecording()
            throw AudioEngineRecorderError.bufferConversionFailed
        }
        bufferDispatcher = dispatcher
        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak dispatcher] buffer, _ in
            dispatcher?.submit(buffer)
        }
        isTapInstalled = true

        engine.prepare()

        do {
            try engine.start()
            isRecording = true
            startMeterUpdates()
            logger.info("✅ Audio engine started successfully")
        } catch {
            logger.error("Failed to start audio engine: \(AppLogger.errorMetadata(error), privacy: .public)")
            input.removeTap(onBus: tapBusNumber)
            isTapInstalled = false
            bufferDispatcher?.stopAndDrain()
            bufferDispatcher = nil
            stopRecording()
            throw AudioEngineRecorderError.failedToStartEngine(error)
        }
    }

    func stopRecording() {
        if isTapInstalled, let input = inputNode {
            input.removeTap(onBus: tapBusNumber)
            isTapInstalled = false
        }

        audioEngine?.stop()

        bufferDispatcher?.stopAndDrain()
        bufferDispatcher = nil
        stopMeterUpdates()

        fileWriteLock.lock()
        audioFile = nil
        converter = nil
        recordingFormat = nil
        fileWriteLock.unlock()

        audioEngine = nil
        inputNode = nil
        recordingURL = nil
        recordingGeneration = nil
        isRecording = false

        currentAveragePower = 0.0
        currentPeakPower = 0.0
        meterState.withLock { $0 = (0, 0, false) }

        logger.info("✅ Recording stopped and cleaned up")
    }

    private func restartRecordingPreservingFile() throws {
        if isTapInstalled, let input = inputNode {
            input.removeTap(onBus: tapBusNumber)
            isTapInstalled = false
        }
        audioEngine?.stop()

        bufferDispatcher?.stopAndDrain()
        bufferDispatcher = nil
        recordingGeneration = UUID()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let inputFormat = input.outputFormat(forBus: tapBusNumber)
        logger.info("Restarting with new input format - Sample Rate: \(inputFormat.sampleRate)")

        guard inputFormat.sampleRate > 0 else {
            throw AudioEngineRecorderError.invalidInputFormat
        }

        guard let format = recordingFormat else {
            throw AudioEngineRecorderError.invalidRecordingFormat
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioEngineRecorderError.failedToCreateConverter
        }

        fileWriteLock.lock()
        converter = newConverter
        fileWriteLock.unlock()

        guard let dispatcher = makeBufferDispatcher(inputFormat: inputFormat) else {
            throw AudioEngineRecorderError.bufferConversionFailed
        }
        bufferDispatcher = dispatcher
        input.installTap(onBus: tapBusNumber, bufferSize: tapBufferSize, format: inputFormat) { [weak dispatcher] buffer, _ in
            dispatcher?.submit(buffer)
        }
        isTapInstalled = true

        engine.prepare()
        try engine.start()
        logger.info("✅ Audio engine successfully restarted after configuration change")
    }

    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        updateMeters(from: buffer)
        try writeBufferToFile(buffer)
    }

    nonisolated private func writeBufferToFile(_ buffer: AVAudioPCMBuffer) throws {
        fileWriteLock.lock()
        defer { fileWriteLock.unlock() }
        
        guard let audioFile = audioFile,
              let converter = converter,
              let format = recordingFormat else {
            throw AudioEngineRecorderError.bufferConversionFailed
        }

        let inputSampleRate = buffer.format.sampleRate
        let outputSampleRate = format.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
            throw AudioEngineRecorderError.bufferConversionFailed
        }

        var error: NSError?
        var hasProvidedBuffer = false

        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if hasProvidedBuffer {
                outStatus.pointee = .noDataNow
                return nil
            } else {
                hasProvidedBuffer = true
                outStatus.pointee = .haveData
                return buffer
            }
        }

        if let error {
            throw AudioEngineRecorderError.audioConversionError(error)
        }
        guard status != .error, convertedBuffer.frameLength > 0 else {
            throw AudioEngineRecorderError.bufferConversionFailed
        }

        do { try audioFile.write(from: convertedBuffer) }
        catch { throw AudioEngineRecorderError.fileWriteFailed(error) }
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

        meterState.withLock { $0 = (averagePowerDb, peakPowerDb, true) }
    }

    private func makeBufferDispatcher(inputFormat: AVAudioFormat) -> BoundedAudioBufferDispatcher? {
        guard let generation = recordingGeneration else { return nil }
        return BoundedAudioBufferDispatcher(
            format: inputFormat,
            frameCapacity: tapBufferSize,
            processor: { [weak self] buffer in try self?.processAudioBuffer(buffer) },
            failureHandler: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isRecording,
                          self.recordingGeneration == generation else { return }
                    self.logger.error("Audio capture pipeline failed: \(AppLogger.errorMetadata(error), privacy: .public)")
                    let errorHandler = self.onRecordingError
                    self.stopRecording()
                    errorHandler?(error)
                }
            }
        )
    }

    private func startMeterUpdates() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let update = self.meterState.withLock { state -> (Float, Float)? in
                    guard state.isDirty else { return nil }
                    state.isDirty = false
                    return (state.average, state.peak)
                }
                if let update {
                    self.currentAveragePower = update.0
                    self.currentPeakPower = update.1
                }
            }
        }
    }

    private func stopMeterUpdates() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    var isCurrentlyRecording: Bool {
        return isRecording
    }

    var currentRecordingURL: URL? {
        return recordingURL
    }

    deinit {
        meterTimer?.invalidate()
        bufferDispatcher?.stopAndDrain()
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
    case bufferConversionFailed
    case audioConversionError(Error)
    case fileWriteFailed(Error)
    case captureOverrun

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
        case .bufferConversionFailed:
            return "Failed to create buffer for audio conversion"
        case .audioConversionError(let error):
            return "Audio format conversion failed: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to write audio data to file: \(error.localizedDescription)"
        case .captureOverrun:
            return "Audio processing could not keep up with recording"
        }
    }
}
