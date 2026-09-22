import AVFoundation
import Accelerate
import Atomics
import AudioToolbox
import CoreAudio
import Foundation
import os

struct AudioInputChannelSelection: Equatable {
    let deviceChannelIndices: [Int32]

    static func resolve(
        deviceChannelCount: UInt32,
        preferredStereoChannels: [UInt32]?
    ) -> AudioInputChannelSelection {
        guard deviceChannelCount > 0 else {
            return AudioInputChannelSelection(deviceChannelIndices: [])
        }

        let fallback = (0..<min(deviceChannelCount, 2)).map(Int32.init)
        guard let preferredStereoChannels,
              !preferredStereoChannels.isEmpty,
              preferredStereoChannels.allSatisfy({ (1...deviceChannelCount).contains($0) }) else {
            return AudioInputChannelSelection(deviceChannelIndices: fallback)
        }

        var seen = Set<UInt32>()
        let preferred = preferredStereoChannels.compactMap { channel -> Int32? in
            guard seen.insert(channel).inserted else { return nil }
            return Int32(channel - 1)
        }

        return AudioInputChannelSelection(deviceChannelIndices: preferred)
    }
}

// MARK: - Core Audio Recorder (AUHAL-based, does not change system default device)
final class CoreAudioRecorder: @unchecked Sendable {
    final class InputBufferSlot: @unchecked Sendable {
        let samples: UnsafeMutablePointer<Float32>
        let capacitySamples: UInt32
        var frameCount: UInt32 = 0
        var channelCount: UInt32 = 0
        var sampleRate: Double = 0

        init(capacitySamples: UInt32) {
            self.capacitySamples = capacitySamples
            self.samples = UnsafeMutablePointer<Float32>.allocate(capacity: Int(capacitySamples))
        }

        deinit {
            samples.deallocate()
        }
    }

    // MARK: - Properties

    let logger = Logger(subsystem: AppLogger.subsystem, category: "CoreAudioRecorder")

    var audioUnit: AudioUnit?
    var audioFile: ExtAudioFileRef?

    var isRecording = false
    var isAudioUnitInitialized = false
    var currentDeviceID: AudioDeviceID = 0
    var recordingURL: URL?

    // Device format (what the hardware provides)
    var deviceFormat = AudioStreamBasicDescription()
    var captureChannelCount: UInt32 = 1
    // Output format (16kHz mono PCM Int16 for transcription)
    var outputFormat = AudioStreamBasicDescription()

    // Downmix + resample + Int16 conversion. Used only on audioProcessingQueue; replaced from the
    // setup path only while that queue is drained (setup, device switch, teardown).
    var formatConverter: RecordingAudioFormatConverter?

    // Audio metering. Store bit patterns so the render callback never locks.
    let averagePowerBits = ManagedAtomic<UInt32>(Float32(-160.0).bitPattern)
    let peakPowerBits = ManagedAtomic<UInt32>(Float32(-160.0).bitPattern)

    var averagePower: Float {
        Float32(bitPattern: averagePowerBits.load(ordering: .relaxed))
    }

    var peakPower: Float {
        Float32(bitPattern: peakPowerBits.load(ordering: .relaxed))
    }

    // Pre-allocated render buffer (to avoid malloc in real-time callback)
    var renderBuffer: UnsafeMutablePointer<Float32>?
    var renderBufferSize: UInt32 = 0

    // Keep the render callback realtime-safe; processing is best-effort under sustained overload.
    let audioProcessingQueue = DispatchQueue(
        label: "com.prakashjoshipax.voiceink.audioProcessing", qos: .userInitiated)
    let audioProcessingQueueKey = DispatchSpecificKey<Void>()
    let maxFramesPerRender: UInt32 = 4096
    let inputRingSlotCount = 96
    var inputBufferSlots: [InputBufferSlot] = []
    var inputBufferCapacitySamples: UInt32 = 0
    let inputWriteIndex = ManagedAtomic<UInt64>(0)
    let inputReadIndex = ManagedAtomic<UInt64>(0)
    let audioProcessingScheduled = ManagedAtomic(false)
    let callbackGate = AudioCallbackGate()
    let onStalledCallbackDrain: @Sendable () -> Void
    let droppedInputBuffersBackpressure = ManagedAtomic<UInt64>(0)
    let droppedInputBuffersCapacity = ManagedAtomic<UInt64>(0)
    /// Buffers the converter rejected (format mismatch or conversion error), kept apart from capacity drops.
    let droppedInputBuffersConversion = ManagedAtomic<UInt64>(0)

    /// Called from the recorder processing queue with raw PCM data (16-bit, 16kHz, mono) for streaming.
    let audioChunkLock = NSLock()
    var _onAudioChunk: ((_ data: Data) -> Void)?
    var onAudioChunk: ((_ data: Data) -> Void)? {
        get {
            audioChunkLock.lock()
            defer { audioChunkLock.unlock() }
            return _onAudioChunk
        }
        set {
            audioChunkLock.lock()
            _onAudioChunk = newValue
            audioChunkLock.unlock()
        }
    }

    // MARK: - Initialization

    init(onStalledCallbackDrain: @escaping @Sendable () -> Void = {}) {
        self.onStalledCallbackDrain = onStalledCallbackDrain
        audioProcessingQueue.setSpecific(key: audioProcessingQueueKey, value: ())
    }

    deinit {
        teardown()
    }

    // MARK: - Public Interface

    /// Prepares AUHAL for the selected device without starting capture.
    func prepare(deviceID: AudioDeviceID) throws {
        if isRecording {
            return
        }

        try validateDevice(deviceID)

        if isPrepared(for: deviceID) {
            return
        }

        teardownPreparedAudioUnit()
        currentDeviceID = deviceID

        logDeviceDetails(deviceID: deviceID)

        do {
            try createAudioUnit()

            try setInputDevice(deviceID)

            try configureFormats()

            try setupInputCallback()

            try initializeAudioUnit()
        } catch {
            teardownPreparedAudioUnit()
            throw error
        }
    }

    /// Discards an idle prepared AUHAL so the next recording creates a fresh connection.
    /// Active recordings keep their existing device-switching lifecycle.
    func invalidatePreparation() {
        guard !isRecording, audioUnit != nil else { return }

        teardownPreparedAudioUnit()
        currentDeviceID = 0
        resetMeters()
    }

    /// Starts recording from the specified device to the given URL (WAV format)
    func startRecording(toOutputFile url: URL, deviceID: AudioDeviceID) throws {
        // Stop any existing recording
        stopRecording()

        try prepare(deviceID: deviceID)

        do {
            recordingURL = url

            // The output file is per recording; the AUHAL setup above is reused.
            try createOutputFile(at: url)
            resetAudioProcessingState()

            try startAudioUnit()
        } catch {
            isRecording = false
            callbackGate.close()
            teardownPreparedAudioUnit()
            closeOutputFile()
            recordingURL = nil
            throw error
        }
    }

    /// Stops the current recording
    func stopRecording() {
        guard isRecording || audioFile != nil else {
            return
        }

        let wasRecording = isRecording
        isRecording = false
        callbackGate.close()

        if wasRecording, let unit = audioUnit {
            let stopStatus = AudioOutputUnitStop(unit)
            if stopStatus != noErr {
                logger.warning("🎙️ AudioOutputUnitStop returned \(stopStatus, privacy: .public)")
            }

            waitForRenderCallbacksToFinish()

            let resetStatus = AudioUnitReset(unit, kAudioUnitScope_Global, 0)
            if resetStatus != noErr {
                logger.warning("🎙️ AudioUnitReset returned \(resetStatus, privacy: .public)")
            }
        }

        waitForRenderCallbacksToFinish()
        drainAudioProcessingQueue()
        flushFormatConverterToFile()
        logDroppedInputBufferCounters(context: "stop")

        closeOutputFile()
        recordingURL = nil

        resetMeters()
    }

    /// Releases the prepared AUHAL and buffers. Use for app shutdown or hard recovery.
    func teardown() {
        stopRecording()
        teardownPreparedAudioUnit()
        recordingURL = nil
        currentDeviceID = 0
        resetMeters()
    }

    var isCurrentlyRecording: Bool { isRecording }
    var currentRecordingURL: URL? { recordingURL }
    var currentDevice: AudioDeviceID { currentDeviceID }

    /// Switches to a new input device mid-recording without stopping the file write
    func switchDevice(to newDeviceID: AudioDeviceID) throws {
        guard isRecording, let unit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Don't switch if it's the same device
        guard newDeviceID != currentDeviceID else { return }

        let oldDeviceID = currentDeviceID
        try RecordingDeviceSwitch.perform(
            change: { try reconfigureRecordingDevice(to: newDeviceID, unit: unit) },
            recover: {
                // Rebuild even after a partial format/buffer/initialization change. Merely
                // restoring the device property can leave buffers configured for the new device.
                isRecording = false
                teardownPreparedAudioUnit()
                try prepare(deviceID: oldDeviceID)
                try startAudioUnit()
            },
            stop: { stopRecording() }
        )
    }

    private func reconfigureRecordingDevice(to newDeviceID: AudioDeviceID, unit: AudioUnit) throws {
        logger.notice(
            "🎙️ Switching recording device to \(newDeviceID, privacy: .public)")

        // Step 1: Stop the AudioUnit (but keep file open)
        callbackGate.close()
        var status = AudioOutputUnitStop(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioOutputUnitStop returned \(status, privacy: .public)")
        }

        waitForRenderCallbacksToFinish()
        drainAudioProcessingQueue()
        // The converter is rebuilt for the new format below; emit the frames it still holds first.
        flushFormatConverterToFile()
        logDroppedInputBufferCounters(context: "device-switch")
        isRecording = false

        // Step 2: Uninitialize to allow reconfiguration
        status = AudioUnitUninitialize(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }
        isAudioUnitInitialized = false

        // Step 3: Set the new device
        var device = newDeviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }

        // Step 4: Get new device format
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var newDeviceFormat = AudioStreamBasicDescription()
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &newDeviceFormat,
            &formatSize
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Step 5: Configure callback format and map only the device's preferred input channels.
        let newCaptureChannelCount = try configureCaptureFormat(
            deviceID: newDeviceID,
            deviceFormat: newDeviceFormat
        )

        // Step 6: Reallocate buffers if needed
        try allocateAudioBuffers(
            maxFrames: renderFrameCapacity(for: newDeviceID),
            channelCount: newCaptureChannelCount,
            inputSampleRate: newDeviceFormat.mSampleRate,
            resetQueuedAudio: true
        )

        // Update stored format
        deviceFormat = newDeviceFormat
        captureChannelCount = newCaptureChannelCount
        currentDeviceID = newDeviceID

        // Step 7: Reinitialize and restart
        status = AudioUnitInitialize(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }
        isAudioUnitInitialized = true

        try startAudioUnit()

        logger.notice("🎙️ Successfully switched to device \(newDeviceID, privacy: .public)")
    }

}
