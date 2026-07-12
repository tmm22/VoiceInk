import Foundation
import os

/// A short, bounded bridge used while a streaming provider is connecting.
/// Oldest chunks are discarded if provider preparation stalls; the complete
/// recording remains available on disk for non-streaming recovery paths.
final class PendingAudioChunkBuffer: @unchecked Sendable {
    private struct State {
        var chunks: [Data?]
        var firstChunkIndex = 0
        var chunkCount = 0
        var byteCount = 0
        var droppedChunkCount = 0
        var sink: ((Data) -> Void)?

        init(capacity: Int) {
            chunks = [Data?](repeating: nil, count: capacity)
        }
    }

    private let maximumByteCount: Int
    private let maximumChunkCount: Int
    private let state: OSAllocatedUnfairLock<State>

    init(maximumByteCount: Int = 4 * 1_024 * 1_024, maximumChunkCount: Int = 1_024) {
        self.maximumByteCount = max(0, maximumByteCount)
        self.maximumChunkCount = max(1, maximumChunkCount)
        self.state = OSAllocatedUnfairLock(initialState: State(capacity: max(1, maximumChunkCount)))
    }

    func append(_ data: Data) {
        let sink = state.withLock { state -> ((Data) -> Void)? in
            if let sink = state.sink {
                return sink
            }
            guard data.count <= maximumByteCount else {
                state.droppedChunkCount += 1
                return nil
            }

            while state.chunkCount > 0,
                  state.byteCount + data.count > maximumByteCount || state.chunkCount == maximumChunkCount {
                evictOldest(from: &state)
            }

            let insertionIndex = (state.firstChunkIndex + state.chunkCount) % maximumChunkCount
            state.chunks[insertionIndex] = data
            state.chunkCount += 1
            state.byteCount += data.count
            return nil
        }
        sink?(data)
    }

    /// Delivers the buffered prefix before atomically redirecting new chunks.
    /// Chunks arriving during the handoff remain queued, preserving order.
    func handoff(to sink: @escaping (Data) -> Void) -> Int {
        var totalDroppedChunkCount = 0

        while true {
            let batch = state.withLock { drainBufferedChunks(from: &$0) }
            totalDroppedChunkCount += batch.droppedChunkCount
            batch.chunks.forEach(sink)

            let didFinish = state.withLock { state in
                guard state.chunkCount == 0 else { return false }
                if totalDroppedChunkCount == 0 {
                    state.sink = sink
                } else {
                    state = State(capacity: maximumChunkCount)
                }
                return true
            }
            if didFinish {
                return totalDroppedChunkCount
            }
        }
    }

    func takeChunks() -> (chunks: [Data], droppedChunkCount: Int) {
        state.withLock { state in
            drainBufferedChunks(from: &state)
        }
    }

    func removeAll() {
        state.withLock { $0 = State(capacity: maximumChunkCount) }
    }

    private func evictOldest(from state: inout State) {
        guard let chunk = state.chunks[state.firstChunkIndex] else { return }
        state.byteCount -= chunk.count
        state.chunks[state.firstChunkIndex] = nil
        state.firstChunkIndex = (state.firstChunkIndex + 1) % maximumChunkCount
        state.chunkCount -= 1
        state.droppedChunkCount += 1
    }

    private func drainBufferedChunks(from state: inout State) -> (chunks: [Data], droppedChunkCount: Int) {
        var chunks: [Data] = []
        chunks.reserveCapacity(state.chunkCount)
        for offset in 0..<state.chunkCount {
            let index = (state.firstChunkIndex + offset) % maximumChunkCount
            if let chunk = state.chunks[index] {
                chunks.append(chunk)
            }
        }
        let result = (chunks, state.droppedChunkCount)
        let sink = state.sink
        state = State(capacity: maximumChunkCount)
        state.sink = sink
        return result
    }
}
