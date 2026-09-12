import Accelerate
import Foundation

/// Vectorised PCM sample conversions shared by the file readers, the streaming providers, and the recorder.
///
/// The normalisation matches the historical scalar code exactly: divide by 32767 and clip to [-1, 1].
enum PCMSampleConversion {
    /// Reciprocal of `Int16.max`; multiplying by this matches `Float(sample) / 32767`.
    static let int16ToFloatScale: Float = 1.0 / Float(Int16.max)

    /// Converts little-endian 16-bit PCM bytes to normalised Float32 samples.
    /// A trailing odd byte is ignored.
    static func floatSamples(fromPCM16LittleEndian bytes: UnsafeRawBufferPointer) -> [Float] {
        let sampleCount = bytes.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return [] }

        return [Float](unsafeUninitializedCapacity: sampleCount) { buffer, initializedCount in
            initializedCount = writeFloatSamples(fromPCM16LittleEndian: bytes, into: buffer.baseAddress!)
        }
    }

    /// Converts little-endian 16-bit PCM bytes into a caller-provided Float32 buffer.
    /// `output` must have room for `bytes.count / 2` samples. Returns the number of samples written.
    @discardableResult
    static func writeFloatSamples(
        fromPCM16LittleEndian bytes: UnsafeRawBufferPointer,
        into output: UnsafeMutablePointer<Float>
    ) -> Int {
        let sampleCount = bytes.count / MemoryLayout<Int16>.size
        guard sampleCount > 0, let base = bytes.baseAddress else { return 0 }

        if Int(bitPattern: base) % MemoryLayout<Int16>.alignment == 0 {
            convert(int16: base.assumingMemoryBound(to: Int16.self), count: sampleCount, into: output)
        } else {
            // Unaligned slice (for example a Data subrange): stage through an aligned copy.
            let staging = UnsafeMutablePointer<Int16>.allocate(capacity: sampleCount)
            defer { staging.deallocate() }
            memcpy(staging, base, sampleCount * MemoryLayout<Int16>.size)
            convert(int16: staging, count: sampleCount, into: output)
        }
        return sampleCount
    }

    /// Converts native-endian Int16 samples to normalised Float32 samples.
    static func convert(int16 input: UnsafePointer<Int16>, count: Int, into output: UnsafeMutablePointer<Float>) {
        guard count > 0 else { return }
        #if _endian(big)
        for index in 0..<count {
            output[index] = Float(Int16(littleEndian: input[index]))
        }
        #else
        vDSP_vflt16(input, 1, output, 1, vDSP_Length(count))
        #endif

        var scale = int16ToFloatScale
        vDSP_vsmul(output, 1, &scale, output, 1, vDSP_Length(count))

        var low: Float = -1.0
        var high: Float = 1.0
        vDSP_vclip(output, 1, &low, &high, output, 1, vDSP_Length(count))
    }

    /// Converts normalised Float32 samples to Int16 with clipping, matching the recorder's historical
    /// scalar path: scale by 32767, clip to [-32768, 32767], truncate toward zero.
    static func convert(float input: UnsafePointer<Float>, count: Int, into output: UnsafeMutablePointer<Int16>) {
        guard count > 0 else { return }

        // Scratch is required because vDSP_vfix16 reads Float and writes Int16 in place-incompatible types.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer { scratch.deallocate() }
        convert(float: input, count: count, into: output, scratch: scratch)
    }

    /// Allocation-free variant of `convert(float:count:into:)`; `scratch` must hold `count` floats.
    static func convert(
        float input: UnsafePointer<Float>,
        count: Int,
        into output: UnsafeMutablePointer<Int16>,
        scratch: UnsafeMutablePointer<Float>
    ) {
        guard count > 0 else { return }
        let length = vDSP_Length(count)

        var scale = Float(Int16.max)
        vDSP_vsmul(input, 1, &scale, scratch, 1, length)

        var low = Float(Int16.min)
        var high = Float(Int16.max)
        vDSP_vclip(scratch, 1, &low, &high, scratch, 1, length)

        vDSP_vfix16(scratch, 1, output, 1, length)
    }
}
