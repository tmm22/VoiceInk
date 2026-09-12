import XCTest
@testable import VoiceInk

final class PendingAudioChunkBufferTests: XCTestCase {
    func testByteBudgetOverflowRequiresBatchFallback() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 10)
        let oldest = Data(repeating: 1, count: 6)
        let newest = Data(repeating: 2, count: 6)

        buffer.append(oldest)
        buffer.append(newest)

        var forwarded: [Data] = []
        let droppedChunkCount = buffer.handoff { forwarded.append($0) }
        XCTAssertTrue(forwarded.isEmpty)
        XCTAssertEqual(droppedChunkCount, 1)
    }

    func testRemovingChunksResetsBufferAndDropCount() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 4)
        buffer.append(Data(repeating: 1, count: 5))
        XCTAssertEqual(buffer.removeAll(), 1)

        var forwarded: [Data] = []
        XCTAssertEqual(buffer.handoff { forwarded.append($0) }, 0)
        XCTAssertTrue(forwarded.isEmpty)
    }

    func testOversizedChunkIsDroppedWithoutGrowingBuffer() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 0)
        buffer.append(Data([1]))

        var forwarded: [Data] = []
        XCTAssertEqual(buffer.handoff { forwarded.append($0) }, 1)
        XCTAssertTrue(forwarded.isEmpty)
    }

    func testFixedChunkCapacityOverflowRequiresBatchFallback() {
        let buffer = PendingAudioChunkBuffer(maximumByteCount: 100, maximumChunkCount: 2)
        buffer.append(Data([1]))
        buffer.append(Data([2]))
        buffer.append(Data([3]))

        var forwarded: [Data] = []
        XCTAssertEqual(buffer.handoff { forwarded.append($0) }, 1)
        XCTAssertTrue(forwarded.isEmpty)
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
