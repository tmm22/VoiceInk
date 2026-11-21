import XCTest
@testable import VoiceInk

/// The in-place SenseVoice argmax must produce exactly the token ids of the copying decoder it replaces.
final class ONNXSenseVoiceInPlaceDecodeTests: XCTestCase {
    func testMatchesCopyingDecoderOnRandomLogits() {
        var generator = SplitMix64(seed: 0x5EED_CAFE)
        for (frameCount, vocabSize) in [(1, 1), (1, 7), (5, 1), (17, 33), (64, 257), (3, 25_055)] {
            let logits = (0..<(frameCount * vocabSize)).map { _ in generator.nextLogit() }
            assertInPlaceDecodeMatchesReference(logits, frameCount: frameCount, vocabSize: vocabSize)
        }
    }

    func testMatchesCopyingDecoderOnTiesAndNonFiniteValues() {
        let nan = Float.nan
        let inf = Float.infinity
        let frames: [[Float]] = [
            [1, 1, 1, 1],              // tie: the first maximum wins
            [0, 2, 2, 1],              // tie between later entries
            [nan, nan, nan, nan],      // nothing compares greater: index 0
            [-inf, -inf, -inf, -inf],  // never greater than the initial -infinity: index 0
            [nan, -inf, 3, nan],       // NaN is skipped
            [inf, inf, 0, nan],        // first +infinity wins
            [-0.0, 0.0, -0.0, 0.0],    // signed zeros compare equal
            [-5, -4, -3, -2]           // maximum in the last slot
        ]
        assertInPlaceDecodeMatchesReference(frames.flatMap { $0 }, frameCount: frames.count, vocabSize: 4)
    }

    func testIgnoresElementsBeyondFrameCountTimesVocabSize() {
        // Leading batch dimensions and spare elements are never read past frameCount * vocabSize.
        let logits: [Float] = [0, 9, 1, 8, 2, 7, 100, 100, 100]
        assertInPlaceDecodeMatchesReference(logits, frameCount: 3, vocabSize: 2)
    }

    func testFallsBackWhenStorageCannotBeReadInPlace() {
        let logits: [Float] = [0, 1, 2, 3, 4, 5]
        logits.withUnsafeBytes { bytes in
            XCTAssertNil(
                SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: bytes, frameCount: 4, vocabSize: 2),
                "Fewer elements than the shape claims")
            XCTAssertNil(SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: bytes, frameCount: 0, vocabSize: 2))
            XCTAssertNil(SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: bytes, frameCount: 3, vocabSize: 0))
            XCTAssertNil(SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: bytes, frameCount: -1, vocabSize: 2))
            XCTAssertNil(
                SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: bytes, frameCount: .max, vocabSize: 2),
                "Overflowing shapes are rejected")

            let misaligned = UnsafeRawBufferPointer(rebasing: bytes[1...])
            XCTAssertNil(
                SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: misaligned, frameCount: 1, vocabSize: 2),
                "Storage that is not aligned for Float takes the copying path")
        }
        XCTAssertNil(
            SenseVoiceTranscriptionService.greedyDecodeInPlace(
                logits: UnsafeRawBufferPointer(start: nil, count: 0), frameCount: 1, vocabSize: 1))
    }

    private func assertInPlaceDecodeMatchesReference(
        _ logits: [Float], frameCount: Int, vocabSize: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = referenceGreedyDecode(logits, frameCount: frameCount, vocabSize: vocabSize)
        let actual = logits.withUnsafeBytes {
            SenseVoiceTranscriptionService.greedyDecodeInPlace(logits: $0, frameCount: frameCount, vocabSize: vocabSize)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    /// The copying decoder exactly as `SenseVoiceTranscriptionService.greedyDecode` has always run it.
    private func referenceGreedyDecode(_ logits: [Float], frameCount: Int, vocabSize: Int) -> [Int] {
        guard frameCount > 0, vocabSize > 0 else { return [] }
        var decoded: [Int] = []
        decoded.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let offset = frame * vocabSize
            var maxValue: Float = -.infinity
            var maxIndex = 0
            for vocabIndex in 0..<vocabSize {
                let value = logits[offset + vocabIndex]
                if value > maxValue {
                    maxValue = value
                    maxIndex = vocabIndex
                }
            }
            decoded.append(maxIndex)
        }

        return decoded
    }
}

/// Deterministic generator so every run decodes the same logits.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// Mostly coarse values, so ties are common, with the occasional non-finite entry.
    mutating func nextLogit() -> Float {
        let value = next()
        switch value % 97 {
        case 0: return .nan
        case 1: return .infinity
        case 2: return -.infinity
        default: return Float(Int(value >> 40) % 41 - 20) / 4
        }
    }
}
