import XCTest
@testable import VoiceInk

final class PendingAudioChunkBufferTests: XCTestCase {
    func testDropsOldestChunksWhenByteBudgetIsExceeded() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 10)
        let oldest = Data(repeating: 1, count: 6)
        let newest = Data(repeating: 2, count: 6)

        buffer.append(oldest)
        buffer.append(newest)

        let result = buffer.takeChunks()
        XCTAssertEqual(result.chunks, [newest])
        XCTAssertEqual(result.droppedChunkCount, 1)
    }

    func testTakingChunksResetsBufferAndDropCount() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 4)
        buffer.append(Data(repeating: 1, count: 5))
        _ = buffer.takeChunks()

        let result = buffer.takeChunks()
        XCTAssertTrue(result.chunks.isEmpty)
        XCTAssertEqual(result.droppedChunkCount, 0)
    }

    func testOversizedChunkIsDroppedWithoutGrowingBuffer() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 0)
        buffer.append(Data([1]))

        let result = buffer.takeChunks()
        XCTAssertTrue(result.chunks.isEmpty)
        XCTAssertEqual(result.droppedChunkCount, 1)
    }

    func testFixedChunkCapacityEvictsOldestInOrder() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 100, maximumChunkCount: 2)
        buffer.append(Data([1]))
        buffer.append(Data([2]))
        buffer.append(Data([3]))

        let result = buffer.takeChunks()
        XCTAssertEqual(result.chunks, [Data([2]), Data([3])])
        XCTAssertEqual(result.droppedChunkCount, 1)
    }

    func testHandoffPreservesBufferedPrefixBeforeSubsequentChunks() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 100)
        buffer.append(Data([1]))
        var forwarded: [Data] = []

        let droppedChunkCount = buffer.handoff { forwarded.append($0) }
        buffer.append(Data([2]))

        XCTAssertEqual(droppedChunkCount, 0)
        XCTAssertEqual(forwarded, [Data([1]), Data([2])])
    }
}
