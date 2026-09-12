import Foundation

enum AudioSampleReaderError: Error {
    case invalidAudioData
}

enum AudioSampleReader {
    /// Reads a 16-bit little-endian PCM file body (after `headerSize` bytes) as normalised Float32 samples.
    /// Conversion is vectorised per chunk; a trailing odd byte is carried into the next chunk and any
    /// final unpaired byte is ignored, matching the previous scalar reader.
    static func readPCM16LE(from url: URL, headerSize: Int = 44, chunkSize: Int = 1 << 20) throws -> [Float] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: headerSize), header.count == headerSize else {
            throw AudioSampleReaderError.invalidAudioData
        }

        var samples: [Float] = []
        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64),
           fileSize > Int64(headerSize) {
            let estimatedSamples = Int((fileSize - Int64(headerSize)) / 2)
            if estimatedSamples > 0 {
                samples.reserveCapacity(estimatedSamples)
            }
        }

        let safeChunkSize = max(2, chunkSize - (chunkSize % 2))
        var carryByte: UInt8?

        while let chunk = try handle.read(upToCount: safeChunkSize), !chunk.isEmpty {
            var data = chunk
            if let carry = carryByte {
                data.insert(carry, at: 0)
                carryByte = nil
            }
            if data.count % 2 != 0 {
                carryByte = data.removeLast()
            }

            let sampleCount = data.count / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { continue }

            let existingCount = samples.count
            samples.append(contentsOf: repeatElement(0, count: sampleCount))
            data.withUnsafeBytes { rawBuffer in
                samples.withUnsafeMutableBufferPointer { output in
                    PCMSampleConversion.writeFloatSamples(
                        fromPCM16LittleEndian: rawBuffer,
                        into: output.baseAddress! + existingCount
                    )
                }
            }
        }

        return samples
    }
}
