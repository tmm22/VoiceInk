import AVFoundation
import Accelerate
import Atomics
import AudioToolbox
import CoreAudio
import Foundation
import os

extension CoreAudioRecorder {
    // MARK: - Input Callback

    static let inputCallback: AURenderCallback = {
        (
            inRefCon,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            ioData
        ) -> OSStatus in

        let recorder = Unmanaged<CoreAudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.handleInputBuffer(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inBusNumber: inBusNumber,
            inNumberFrames: inNumberFrames
        )
    }

    func handleInputBuffer(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) -> OSStatus {

        // Admission and active count change atomically: after close(), no new callback can
        // observe resources that stop/switch/teardown are about to mutate.
        guard callbackGate.tryEnter() else { return noErr }
        defer { callbackGate.leave() }
        guard let audioUnit else { return noErr }

        let channelCount = captureChannelCount
        let inputSampleRate = deviceFormat.mSampleRate
        let requiredSamples = inNumberFrames * channelCount

        guard let renderBuf = renderBuffer,
            requiredSamples <= renderBufferSize,
            requiredSamples <= inputBufferCapacitySamples
        else {
            droppedInputBuffersCapacity.wrappingIncrement(ordering: .relaxed)
            return noErr
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * channelCount
        let bufferSize = inNumberFrames * bytesPerFrame

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: channelCount,
                mDataByteSize: bufferSize,
                mData: renderBuf
            )
        )

        // Render audio from the input
        let status = AudioUnitRender(
            audioUnit,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            &bufferList
        )

        if status != noErr {
            return status
        }

        // Calculate audio meters from input buffer
        calculateMeters(from: &bufferList, frameCount: inNumberFrames)

        enqueueInputBuffer(
            &bufferList,
            frameCount: inNumberFrames,
            inputSampleRate: inputSampleRate
        )

        return noErr
    }

    /// Runs on the real-time render thread: vectorised, lock-free, allocation-free.
    func calculateMeters(from bufferList: inout AudioBufferList, frameCount: UInt32) {
        guard let data = bufferList.mBuffers.mData else { return }
        guard frameCount > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float32.self)
        let channelCount = Int(bufferList.mBuffers.mNumberChannels)
        let totalSamples = Int(frameCount) * channelCount

        guard totalSamples > 0 else { return }

        let (avgDb, peakDb) = Self.meterLevels(samples: samples, count: totalSamples)

        averagePowerBits.store(avgDb.bitPattern, ordering: .relaxed)
        peakPowerBits.store(peakDb.bitPattern, ordering: .relaxed)
    }

    /// Returns (rms dBFS, peak dBFS) over the interleaved samples, floored at -120 dBFS.
    static func meterLevels(samples: UnsafePointer<Float32>, count: Int) -> (average: Float, peak: Float) {
        var meanSquare: Float = 0
        var peak: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))

        let rms = sqrt(meanSquare)
        let avgDb = 20.0 * log10(max(rms, 0.000001))
        let peakDb = 20.0 * log10(max(peak, 0.000001))
        return (avgDb, peakDb)
    }

    func enqueueInputBuffer(
        _ inputBuffer: inout AudioBufferList,
        frameCount: UInt32,
        inputSampleRate: Double
    ) {
        guard !inputBufferSlots.isEmpty,
            let inputData = inputBuffer.mBuffers.mData
        else {
            return
        }

        let channelCount = inputBuffer.mBuffers.mNumberChannels
        let sampleCount = frameCount * channelCount

        guard sampleCount <= inputBufferCapacitySamples else {
            droppedInputBuffersCapacity.wrappingIncrement(ordering: .relaxed)
            return
        }

        let writeIndex = inputWriteIndex.load(ordering: .relaxed)
        let readIndex = inputReadIndex.load(ordering: .acquiring)
        guard writeIndex - readIndex < UInt64(inputBufferSlots.count) else {
            droppedInputBuffersBackpressure.wrappingIncrement(ordering: .relaxed)
            return
        }

        let slot = inputBufferSlots[Int(writeIndex % UInt64(inputBufferSlots.count))]
        slot.frameCount = frameCount
        slot.channelCount = channelCount
        slot.sampleRate = inputSampleRate

        let inputSamples = inputData.assumingMemoryBound(to: Float32.self)
        slot.samples.update(from: inputSamples, count: Int(sampleCount))

        inputWriteIndex.store(writeIndex + 1, ordering: .releasing)
        scheduleAudioProcessing()
    }

    func scheduleAudioProcessing() {
        let wasScheduled = audioProcessingScheduled.exchange(true, ordering: .acquiringAndReleasing)
        guard !wasScheduled else { return }

        audioProcessingQueue.async { [weak self] in
            self?.processQueuedInputBuffers()
        }
    }

    func processQueuedInputBuffers(maxBuffers: Int? = nil) {
        var processedBuffers = 0

        while maxBuffers.map({ processedBuffers < $0 }) ?? true {
            let readIndex = inputReadIndex.load(ordering: .relaxed)
            let writeIndex = inputWriteIndex.load(ordering: .acquiring)

            guard readIndex < writeIndex, !inputBufferSlots.isEmpty else {
                audioProcessingScheduled.store(false, ordering: .releasing)

                let latestReadIndex = inputReadIndex.load(ordering: .acquiring)
                let latestWriteIndex = inputWriteIndex.load(ordering: .acquiring)
                if latestReadIndex < latestWriteIndex {
                    scheduleAudioProcessing()
                }
                return
            }

            let slot = inputBufferSlots[Int(readIndex % UInt64(inputBufferSlots.count))]
            convertAndWriteToFile(
                inputSamples: slot.samples,
                frameCount: slot.frameCount,
                inputChannels: slot.channelCount,
                inputSampleRate: slot.sampleRate
            )
            inputReadIndex.store(readIndex + 1, ordering: .releasing)
            processedBuffers += 1
        }

        if maxBuffers != nil,
            inputReadIndex.load(ordering: .acquiring) < inputWriteIndex.load(ordering: .acquiring)
        {
            scheduleAudioProcessing()
        }
    }

    func drainAudioProcessingQueue() {
        if DispatchQueue.getSpecific(key: audioProcessingQueueKey) != nil {
            processQueuedInputBuffers()
        } else {
            audioProcessingQueue.sync {
                processQueuedInputBuffers()
            }
        }
    }

    /// Hardware lifecycle callers run on Recorder.audioSetupQueue. A slow driver can delay
    /// completion, but it must never turn a diagnostic deadline into permission to free memory.
    func waitForRenderCallbacksToFinish() {
        callbackGate.waitUntilDrained(onStalledDrain: onStalledCallbackDrain) {
            self.logger.warning("Audio callback drain exceeded 200ms; retaining recording resources until it finishes")
        }
    }

    func logDroppedInputBufferCounters(context: String) {
        let backpressureDrops = droppedInputBuffersBackpressure.exchange(0, ordering: .acquiringAndReleasing)
        let capacityDrops = droppedInputBuffersCapacity.exchange(0, ordering: .acquiringAndReleasing)
        let conversionDrops = droppedInputBuffersConversion.exchange(0, ordering: .acquiringAndReleasing)

        if backpressureDrops > 0 || capacityDrops > 0 || conversionDrops > 0 {
            logger.warning(
                "🎙️ Dropped input buffers context=\(context, privacy: .public) backpressure=\(backpressureDrops, privacy: .public) capacity=\(capacityDrops, privacy: .public) conversion=\(conversionDrops, privacy: .public)"
            )
        }
    }

    func resetAudioProcessingState() {
        inputWriteIndex.store(0, ordering: .relaxed)
        inputReadIndex.store(0, ordering: .relaxed)
        audioProcessingScheduled.store(false, ordering: .relaxed)
        formatConverter?.reset()
    }

    func convertAndWriteToFile(
        inputSamples: UnsafeMutablePointer<Float32>,
        frameCount: UInt32,
        inputChannels: UInt32,
        inputSampleRate: Double
    ) {
        guard audioFile != nil, let converter = formatConverter else { return }

        guard converter.inputSampleRate == inputSampleRate,
            let output = converter.convert(
                interleavedInput: inputSamples,
                frameCount: frameCount,
                channelCount: inputChannels
            )
        else {
            droppedInputBuffersConversion.wrappingIncrement(ordering: .relaxed)
            return
        }

        writeConvertedFrames(output)
    }

    /// Emits the frames the sample-rate converter is still holding. Call on the setup queue with the
    /// processing queue drained, before closing the file or replacing the converter.
    func flushFormatConverterToFile() {
        guard audioFile != nil, let converter = formatConverter, converter.isResampling else { return }

        let flushAndWrite = {
            if let flushed = converter.flush() {
                self.writeConvertedFrames(flushed)
            }
        }
        if DispatchQueue.getSpecific(key: audioProcessingQueueKey) != nil {
            flushAndWrite()
        } else {
            audioProcessingQueue.sync(execute: flushAndWrite)
        }
    }

    /// Writes Int16 mono frames to the file and forwards them to the streaming callback.
    func writeConvertedFrames(_ output: UnsafeBufferPointer<Int16>) {
        guard let file = audioFile, output.count > 0, let base = output.baseAddress else { return }
        let outputFrameCount = UInt32(output.count)

        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: outputFrameCount * UInt32(MemoryLayout<Int16>.size),
                mData: UnsafeMutableRawPointer(mutating: base)
            )
        )

        let writeStatus = ExtAudioFileWrite(file, outputFrameCount, &outputBufferList)
        if writeStatus != noErr {
            logger.error("🎙️ ExtAudioFileWrite failed with status: \(writeStatus, privacy: .public)")
        }

        // Send the same PCM data to the streaming callback if set.
        if let audioChunk = onAudioChunk {
            let data = Data(bytes: base, count: output.count * MemoryLayout<Int16>.size)
            audioChunk(data)
        }
    }

    func renderFrameCapacity(for deviceID: AudioDeviceID) -> UInt32 {
        max(maxFramesPerRender, getBufferFrameSize(deviceID: deviceID) ?? maxFramesPerRender)
    }

}
