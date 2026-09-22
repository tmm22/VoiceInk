import AVFoundation
import Foundation

enum PCMAudioConverter {
    /// Little-endian 16-bit PCM -> normalised Float32 (divide by 32767, clip to [-1, 1]).
    static func float32Samples(fromPCM16Data data: Data) -> [Float] {
        data.withUnsafeBytes { PCMSampleConversion.floatSamples(fromPCM16LittleEndian: $0) }
    }

    /// Little-endian 16-bit PCM -> 16 kHz mono Float32 buffer, converted directly into the channel data.
    static func pcmBuffer(fromPCM16Data data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000.0,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }

        let written = data.withUnsafeBytes { rawBuffer in
            PCMSampleConversion.writeFloatSamples(fromPCM16LittleEndian: rawBuffer, into: channel)
        }
        buffer.frameLength = AVAudioFrameCount(written)

        return buffer
    }
}
