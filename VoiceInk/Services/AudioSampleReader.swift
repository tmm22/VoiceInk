import Foundation

enum AudioSampleReaderError: Error {
    case invalidAudioData
}

enum AudioSampleReader {
    static func readPCM16LE(from url: URL, headerSize: Int = 44, chunkSize: Int = 16_384) throws -> [Float] {
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
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
                let count = rawBuffer.count / MemoryLayout<Int16>.size
                samples.reserveCapacity(samples.count + count)
                for index in 0..<count {
                    let littleEndianSample = Int16(littleEndian: base[index])
                    let normalized = Float(littleEndianSample) / Float(Int16.max)
                    samples.append(max(-1.0, min(normalized, 1.0)))
                }
            }
        }

        return samples
    }
}
