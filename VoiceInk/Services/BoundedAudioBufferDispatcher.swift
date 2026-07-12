import AVFoundation
import AudioToolbox
import Foundation

final class BoundedAudioBufferDispatcher: @unchecked Sendable {
    typealias Processor = @Sendable (AVAudioPCMBuffer) throws -> Void
    typealias FailureHandler = @Sendable (Error) -> Void

    private struct State {
        var availableBuffers: [AVAudioPCMBuffer]
        var isAccepting = true
        var hasFailed = false
    }

    private let queue = DispatchQueue(label: "com.tmm22.voicelinkcommunity.boundedAudioProcessing", qos: .userInitiated)
    private let failureQueue = DispatchQueue(label: "com.tmm22.voicelinkcommunity.audioFailureReporting")
    private let lock = NSLock()
    private var state: State
    private let processor: Processor
    private let failureHandler: FailureHandler

    init?(format: AVAudioFormat, frameCapacity: AVAudioFrameCount, poolSize: Int = 12,
          processor: @escaping Processor, failureHandler: @escaping FailureHandler) {
        var buffers: [AVAudioPCMBuffer] = []
        buffers.reserveCapacity(poolSize)
        for _ in 0..<poolSize {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
            buffers.append(buffer)
        }
        state = State(availableBuffers: buffers)
        self.processor = processor
        self.failureHandler = failureHandler
    }

    func submit(_ source: AVAudioPCMBuffer) {
        lock.lock()
        guard state.isAccepting, !state.hasFailed else { lock.unlock(); return }
        guard let destination = state.availableBuffers.popLast() else {
            state.hasFailed = true
            state.isAccepting = false
            lock.unlock()
            failureQueue.async { [failureHandler] in failureHandler(AudioEngineRecorderError.captureOverrun) }
            return
        }
        guard Self.copy(source, to: destination) else {
            state.availableBuffers.append(destination)
            state.hasFailed = true
            state.isAccepting = false
            lock.unlock()
            failureQueue.async { [failureHandler] in failureHandler(AudioEngineRecorderError.bufferConversionFailed) }
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let shouldProcess = self.lock.withLock { !self.state.hasFailed }
            if shouldProcess {
                do { try self.processor(destination) }
                catch { self.fail(with: error) }
            }
            self.lock.withLock { self.state.availableBuffers.append(destination) }
        }
        lock.unlock()
    }

    func stopAndDrain() {
        lock.withLock { state.isAccepting = false }
        drain()
    }

    func drain() { queue.sync { } }

    private func fail(with error: Error) {
        let shouldReport = lock.withLock { () -> Bool in
            guard !state.hasFailed else { return false }
            state.hasFailed = true
            state.isAccepting = false
            return true
        }
        if shouldReport { failureHandler(error) }
    }

    private static func copy(_ source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer) -> Bool {
        guard source.frameLength <= destination.frameCapacity else { return false }
        destination.frameLength = destination.frameCapacity
        let sources = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: source.audioBufferList)
        )
        let destinations = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sources.count == destinations.count else { return false }
        for index in sources.indices {
            let byteCount = Int(sources[index].mDataByteSize)
            guard byteCount <= Int(destinations[index].mDataByteSize),
                  let sourceData = sources[index].mData,
                  let destinationData = destinations[index].mData else { return false }
            memcpy(destinationData, sourceData, byteCount)
            destinations[index].mDataByteSize = sources[index].mDataByteSize
        }
        destination.frameLength = source.frameLength
        return true
    }
}
