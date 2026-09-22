import Foundation
import SwiftData
import os

/// Sendable source that bridges audio chunks from any thread into an AsyncStream.
final class AudioChunkSource: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingOldest(2_048)
        )
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func send(_ data: Data) -> Bool {
        switch continuation.yield(data) {
        case .enqueued(_):
            return true
        case .dropped(_), .terminated:
            return false
        @unknown default:
            return false
        }
    }

    func finish() {
        continuation.finish()
    }
}

final class StreamingMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedChunks = 0
    private var receivedBytes = 0
    private var sentChunks = 0
    private var sentBytes = 0
    private var droppedChunks = 0
    private var droppedBytes = 0

    func reset() {
        lock.lock()
        receivedChunks = 0
        receivedBytes = 0
        sentChunks = 0
        sentBytes = 0
        droppedChunks = 0
        droppedBytes = 0
        lock.unlock()
    }

    func recordReceived(_ byteCount: Int) {
        lock.lock()
        receivedChunks += 1
        receivedBytes += byteCount
        lock.unlock()
    }

    func recordSent(_ byteCount: Int) {
        lock.lock()
        sentChunks += 1
        sentBytes += byteCount
        lock.unlock()
    }

    func recordDropped(_ byteCount: Int) {
        lock.lock()
        droppedChunks += 1
        droppedBytes += byteCount
        lock.unlock()
    }

    func snapshot() -> (
        receivedChunks: Int,
        receivedBytes: Int,
        sentChunks: Int,
        sentBytes: Int,
        droppedChunks: Int,
        droppedBytes: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedChunks, receivedBytes, sentChunks, sentBytes, droppedChunks, droppedBytes)
    }
}
