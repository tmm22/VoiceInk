import AVFoundation
import AudioToolbox
import XCTest
@testable import VoiceInk

/// The reader must start at the WAV `data` chunk. Core Audio and AVAudioFile both insert padding
/// chunks, so the payload is not at byte 44.
final class AudioSampleReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileSystemHelper.createIsolatedDirectory(prefix: "AudioSampleReader")
    }

    override func tearDownWithError() throws {
        FileSystemHelper.cleanupDirectory(directory)
    }

    func testCoreAudioRecorderWAVReturnsOnlyRecordedSamples() throws {
        let url = directory.appendingPathComponent("recorder.wav")
        let written = (0..<160).map { Int16(truncatingIfNeeded: $0 * 100 - 8_000) }
        try writeWithExtAudioFile(written, to: url)
        let payloadOffset = try payloadOffset(of: url)
        XCTAssertGreaterThan(payloadOffset, 44, "Precondition: the writer pads before the data chunk")

        let samples = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(samples.count, written.count)
        for (sample, expected) in zip(samples, written) {
            XCTAssertEqual(sample, Float(expected) / 32767, accuracy: 1e-6)
        }
    }

    func testAVAudioFileWAVReturnsOnlyWrittenSamples() throws {
        let url = directory.appendingPathComponent("imported.wav")
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        buffer.frameLength = 320
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        for index in 0..<320 { channel[index] = 1_000 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: false)
            try file.write(from: buffer)
        }
        let samples = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(samples.count, 320)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 1_000 / 32767) < 1e-6 })
    }

    func testCanonicalWAVWithTrailingChunkStopsAtDeclaredDataSize() throws {
        let url = directory.appendingPathComponent("canonical.wav")
        let payload: [Int16] = [1, -1, 32_767, -32_768]
        var data = canonicalWAV(payload)
        // A LIST chunk after `data` is metadata, not audio.
        data.append(Data("LIST".utf8))
        data.append(contentsOf: [4, 0, 0, 0, 0x41, 0x42, 0x43, 0x44])
        try data.write(to: url)
        let samples = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(samples.count, payload.count)
        XCTAssertEqual(samples[2], 1, accuracy: 1e-6)
    }

    func testNonPCM16WAVIsRejectedInsteadOfDecodedAsNoise() throws {
        let url = directory.appendingPathComponent("float.wav")
        var data = canonicalWAV([0, 0])
        data[34] = 32  // bitsPerSample
        data[20] = 3   // WAVE_FORMAT_IEEE_FLOAT
        try data.write(to: url)
        XCTAssertThrowsError(try AudioSampleReader.readPCM16LE(from: url)) { error in
            XCTAssertEqual(error as? AudioSampleReaderError, .unsupportedSampleFormat)
        }
    }

    func testRawFileWithoutRIFFHeaderSkipsRequestedHeaderSize() throws {
        let url = directory.appendingPathComponent("raw.pcm")
        var data = Data(repeating: 0xAB, count: 44)
        for sample: Int16 in [100, 200, 300] {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
        let samples = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[1], 200 / 32767, accuracy: 1e-6)
    }

    func testSmallChunksCarryOddBytesAcrossReads() throws {
        let url = directory.appendingPathComponent("chunks.wav")
        let payload = (0..<101).map { Int16($0) }
        try canonicalWAV(payload).write(to: url)
        let samples = try AudioSampleReader.readPCM16LE(from: url, chunkSize: 3)
        XCTAssertEqual(samples.count, payload.count)
        XCTAssertEqual(samples.last ?? 0, 100 / 32767, accuracy: 1e-6)
    }

    func testDeclaredDataSizeLargerThanFileReadsOnlyWhatExists() throws {
        let url = directory.appendingPathComponent("truncated.wav")
        var data = canonicalWAV([5, 6, 7])
        // Claim ~4 GB of audio; the reader must neither over-read nor size its buffer from this.
        data.replaceSubrange(40..<44, with: [0xF0, 0xFF, 0xFF, 0xFF])
        try data.write(to: url)
        let samples = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(samples.count, 3)
        XCTAssertLessThan(samples.capacity, 1_000_000)
    }

    func testDataChunkWithoutFormatIsRejected() throws {
        let url = directory.appendingPathComponent("noformat.wav")
        var data = Data("RIFF".utf8)
        data.append(contentsOf: [12, 0, 0, 0])
        data.append(Data("WAVEdata".utf8))
        data.append(contentsOf: [4, 0, 0, 0, 1, 0, 2, 0])
        try data.write(to: url)
        XCTAssertThrowsError(try AudioSampleReader.readPCM16LE(from: url))
    }

    // MARK: - Helpers

    private func writeWithExtAudioFile(_ samples: [Int16], to url: URL) throws {
        var format = AudioStreamBasicDescription(
            mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var fileRef: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileCreateWithURL(
            url as CFURL, kAudioFileWAVEType, &format, nil, AudioFileFlags.eraseFile.rawValue, &fileRef), noErr)
        let file = try XCTUnwrap(fileRef)
        defer { ExtAudioFileDispose(file) }
        XCTAssertEqual(ExtAudioFileSetProperty(
            file, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format), noErr)
        var mutableSamples = samples
        let status = mutableSamples.withUnsafeMutableBytes { raw -> OSStatus in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return ExtAudioFileWrite(file, UInt32(samples.count), &list)
        }
        XCTAssertEqual(status, noErr)
    }

    private func payloadOffset(of url: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try AudioSampleReader.locatePCMPayload(in: handle, fallbackHeaderSize: 44).offset
    }

    private func canonicalWAV(_ samples: [Int16]) -> Data {
        func le32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        func le16(_ value: UInt16) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let payloadBytes = UInt32(samples.count * 2)
        var data = Data("RIFF".utf8)
        data.append(contentsOf: le32(36 + payloadBytes))
        data.append(Data("WAVEfmt ".utf8))
        data.append(contentsOf: le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16))
        data.append(Data("data".utf8))
        data.append(contentsOf: le32(payloadBytes))
        for sample in samples {
            data.append(contentsOf: le16(UInt16(bitPattern: sample)))
        }
        return data
    }
}
