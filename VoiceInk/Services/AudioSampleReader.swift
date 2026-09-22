import Foundation

enum AudioSampleReaderError: Error {
    case invalidAudioData
    case unsupportedSampleFormat
}

enum AudioSampleReader {
    /// Byte range of the PCM payload inside a file.
    struct PCMPayload: Equatable {
        let offset: Int
        /// `nil` reads to end of file (streamed WAVs may leave the data size unset).
        let length: Int?
    }

    /// Reads a 16-bit little-endian PCM file body as normalised Float32 samples.
    ///
    /// RIFF/WAVE files are parsed chunk by chunk so the payload starts at the `data` chunk. Core Audio's
    /// WAV writer inserts a `FLLR` alignment chunk before `data`, so a fixed 44-byte header assumption
    /// would feed header and padding bytes to the model as audio. Files without a RIFF header fall back
    /// to skipping `headerSize` bytes. Conversion is vectorised per chunk; a trailing odd byte is carried
    /// into the next chunk and any final unpaired byte is ignored.
    static func readPCM16LE(from url: URL, headerSize: Int = 44, chunkSize: Int = 1 << 20) throws -> [Float] {
        let handle = try FileHandle(forReadingFrom: url)
        // Best-effort close of a read-only handle; nothing is lost if it fails.
        defer { try? handle.close() }

        let payload = try locatePCMPayload(in: handle, fallbackHeaderSize: headerSize)
        try handle.seek(toOffset: UInt64(payload.offset))

        var samples: [Float] = []
        // Reserve from the bytes actually on disk; a corrupt header must not size the allocation.
        // A missing size attribute only costs the reservation, not correctness.
        var estimatedBytes: Int?
        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64),
            fileSize > Int64(payload.offset)
        {
            let available = Int(fileSize - Int64(payload.offset))
            estimatedBytes = payload.length.map { min($0, available) } ?? available
        }
        if let estimatedBytes, estimatedBytes > 0 {
            samples.reserveCapacity(estimatedBytes / MemoryLayout<Int16>.size)
        }
        // A declared payload length bounds the read; a chunk after `data` is not audio.
        var remainingBytes = payload.length

        let safeChunkSize = max(2, chunkSize - (chunkSize % 2))
        var carryByte: UInt8?

        while true {
            let requested = remainingBytes.map { min(safeChunkSize, $0) } ?? safeChunkSize
            guard requested > 0, let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else { break }
            remainingBytes = remainingBytes.map { $0 - chunk.count }

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
            let written = data.withUnsafeBytes { rawBuffer in
                samples.withUnsafeMutableBufferPointer { output -> Int in
                    guard let base = output.baseAddress else { return 0 }
                    return PCMSampleConversion.writeFloatSamples(
                        fromPCM16LittleEndian: rawBuffer,
                        into: base + existingCount
                    )
                }
            }
            // Keep the sample count honest if fewer samples were decoded than reserved.
            if written < sampleCount {
                samples.removeLast(sampleCount - written)
            }
        }

        return samples
    }

    /// Finds the PCM payload. For RIFF/WAVE files this walks the chunk list to the `data` chunk and
    /// rejects formats other than 16-bit integer PCM; otherwise it skips `fallbackHeaderSize` bytes.
    static func locatePCMPayload(in handle: FileHandle, fallbackHeaderSize: Int) throws -> PCMPayload {
        try handle.seek(toOffset: 0)
        guard let riffHeader = try handle.read(upToCount: 12), riffHeader.count == 12 else {
            throw AudioSampleReaderError.invalidAudioData
        }
        guard riffHeader[0..<4] == Data("RIFF".utf8), riffHeader[8..<12] == Data("WAVE".utf8) else {
            // Not a WAVE container: honour the caller's raw header size, as the previous reader did.
            guard let header = try handle.read(upToCount: max(0, fallbackHeaderSize - 12)),
                header.count == max(0, fallbackHeaderSize - 12)
            else {
                throw AudioSampleReaderError.invalidAudioData
            }
            return PCMPayload(offset: fallbackHeaderSize, length: nil)
        }

        var offset = 12
        var sawFormat = false
        while let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8 {
            let identifier = chunkHeader[0..<4]
            let size = Int(chunkHeader.littleEndianUInt32(at: 4))
            offset += 8
            if identifier == Data("fmt ".utf8) {
                guard size >= 16, let format = try handle.read(upToCount: 16), format.count == 16 else {
                    throw AudioSampleReaderError.invalidAudioData
                }
                let formatTag = format.littleEndianUInt16(at: 0)
                let bitsPerSample = format.littleEndianUInt16(at: 14)
                // 1 = integer PCM, 0xFFFE = WAVE_FORMAT_EXTENSIBLE (PCM sub-format from Core Audio).
                guard formatTag == 1 || formatTag == 0xFFFE, bitsPerSample == 16 else {
                    throw AudioSampleReaderError.unsupportedSampleFormat
                }
                sawFormat = true
                let remaining = size - 16 + (size % 2)
                if remaining > 0 { try handle.seek(toOffset: UInt64(offset + 16 + remaining)) }
                offset += 16 + remaining
                continue
            }
            if identifier == Data("data".utf8) {
                // Without a validated `fmt ` chunk the payload encoding is unknown.
                guard sawFormat else { throw AudioSampleReaderError.invalidAudioData }
                // 0 or 0xFFFFFFFF means the writer did not finalise the size; read to end of file.
                let length = (size == 0 || size == Int(UInt32.max)) ? nil : size
                return PCMPayload(offset: offset, length: length)
            }
            let padded = size + (size % 2)
            offset += padded
            try handle.seek(toOffset: UInt64(offset))
        }
        throw AudioSampleReaderError.invalidAudioData
    }
}

private extension Data {
    func littleEndianUInt32(at position: Int) -> UInt32 {
        let index = startIndex + position
        return UInt32(self[index]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16
            | UInt32(self[index + 3]) << 24
    }

    func littleEndianUInt16(at position: Int) -> UInt16 {
        let index = startIndex + position
        return UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }
}
