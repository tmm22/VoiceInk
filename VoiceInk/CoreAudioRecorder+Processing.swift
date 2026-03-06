import Foundation
import CoreAudio
import AudioToolbox

extension CoreAudioRecorder {
    var inputCallback: AURenderCallback {
        { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
            let recorder = Unmanaged<CoreAudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
            return recorder.handleInputBuffer(
                ioActionFlags: ioActionFlags,
                inTimeStamp: inTimeStamp,
                inBusNumber: inBusNumber,
                inNumberFrames: inNumberFrames
            )
        }
    }

    func handleInputBuffer(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) -> OSStatus {
        guard let audioUnit, isRecording, let renderBuf = renderBuffer else {
            return noErr
        }

        let channelCount = deviceFormat.mChannelsPerFrame
        let requiredSamples = inNumberFrames * channelCount
        guard requiredSamples <= renderBufferSize else {
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

        calculateMeters(from: &bufferList, frameCount: inNumberFrames)
        convertAndWriteToFile(inputBuffer: &bufferList, frameCount: inNumberFrames)

        return noErr
    }

    func calculateMeters(from bufferList: inout AudioBufferList, frameCount: UInt32) {
        guard let data = bufferList.mBuffers.mData else { return }
        guard frameCount > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float32.self)
        let channelCount = Int(deviceFormat.mChannelsPerFrame)
        let totalSamples = Int(frameCount) * channelCount
        guard totalSamples > 0 else { return }

        var sum: Float = 0.0
        var peak: Float = 0.0

        for i in 0..<totalSamples {
            let sample = abs(samples[i])
            sum += sample * sample
            if sample > peak {
                peak = sample
            }
        }

        let rms = sqrt(sum / Float(totalSamples))
        let avgDb = 20.0 * log10(max(rms, 0.000001))
        let peakDb = 20.0 * log10(max(peak, 0.000001))

        meterLock.lock()
        _averagePower = avgDb
        _peakPower = peakDb
        meterLock.unlock()
    }

    func convertAndWriteToFile(inputBuffer: inout AudioBufferList, frameCount: UInt32) {
        guard let file = audioFile else { return }

        let inputChannels = deviceFormat.mChannelsPerFrame
        let inputSampleRate = deviceFormat.mSampleRate
        let outputSampleRate = outputFormat.mSampleRate

        guard let inputData = inputBuffer.mBuffers.mData else { return }
        let inputSamples = inputData.assumingMemoryBound(to: Float32.self)

        let ratio = outputSampleRate / inputSampleRate
        let outputFrameCount = UInt32(Double(frameCount) * ratio)

        guard outputFrameCount > 0,
              let outputBuffer = conversionBuffer,
              outputFrameCount <= conversionBufferSize else { return }

        if inputSampleRate == outputSampleRate {
            for i in 0..<Int(frameCount) {
                var sample: Float32 = 0
                for ch in 0..<Int(inputChannels) {
                    sample += inputSamples[i * Int(inputChannels) + ch]
                }
                sample /= Float32(inputChannels)

                let scaled = sample * 32767.0
                let clipped = max(-32768.0, min(32767.0, scaled))
                outputBuffer[i] = Int16(clipped)
            }
        } else {
            for i in 0..<Int(outputFrameCount) {
                let inputIndex = Double(i) / ratio
                let inputIndexInt = Int(inputIndex)
                let frac = Float32(inputIndex - Double(inputIndexInt))

                var sample: Float32 = 0
                let idx1 = min(inputIndexInt, Int(frameCount) - 1)
                let idx2 = min(inputIndexInt + 1, Int(frameCount) - 1)

                for ch in 0..<Int(inputChannels) {
                    let s1 = inputSamples[idx1 * Int(inputChannels) + ch]
                    let s2 = inputSamples[idx2 * Int(inputChannels) + ch]
                    sample += s1 + frac * (s2 - s1)
                }
                sample /= Float32(inputChannels)

                let scaled = sample * 32767.0
                let clipped = max(-32768.0, min(32767.0, scaled))
                outputBuffer[i] = Int16(clipped)
            }
        }

        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: outputFrameCount * 2,
                mData: outputBuffer
            )
        )

        let writeStatus = ExtAudioFileWrite(file, outputFrameCount, &outputBufferList)
        if writeStatus != noErr {
            logger.error("🎙️ ExtAudioFileWrite failed with status: \(writeStatus, privacy: .public)")
        }

        if let onAudioChunk {
            let byteCount = Int(outputFrameCount) * MemoryLayout<Int16>.size
            let data = Data(bytes: outputBuffer, count: byteCount)
            onAudioChunk(data)
        }
    }
}
