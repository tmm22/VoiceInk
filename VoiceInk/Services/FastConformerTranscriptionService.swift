import Foundation
import AVFoundation
import OnnxRuntimeBindings
import OSLog

private let logger = Logger(subsystem: AppLogger.subsystem, category: "FastConformerTranscriptionService")

final class FastConformerTranscriptionService: TranscriptionService {
    /// Everything `transcribe()` needs besides the audio. Built once per model and cached as a unit.
    private struct Runtime {
        let session: ORTSession
        let outputName: String
        let tokenizer: FastConformerTokenizer
    }

    private let modelsDirectory: URL
    private let featureExtractor = FastConformerFeatureExtractor()

    // The ONNX Runtime environment is created with the first session build, which runs off the main
    // actor, so constructing this service (done on the main actor by the registry) stays cheap.
    private let envLock = NSLock()
    private var env: ORTEnv?
    private var didAttemptEnvCreation = false
    private let runtimeCache = ONNXRuntimeCache<Runtime>()

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let fastConformerModel = model as? FastConformerModel else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        let samples = try readAudioSamples(from: audioURL)
        guard !samples.isEmpty else { throw VoiceInkEngineError.transcriptionFailed }
        let features = featureExtractor.extract(samples: samples)
        guard !features.isEmpty else { throw VoiceInkEngineError.transcriptionFailed }

        // Normally cached by the record-start prepare; joins that build if it is still running.
        let runtime = try await loadRuntime(for: fastConformerModel, request: .transcribe)
        let session = runtime.session
        let outputName = runtime.outputName
        let tokenizer = runtime.tokenizer
        
        let (audioSignal, lengthTensor) = try makeInputTensors(from: features)

        let outputs = try session.run(
            withInputs: ["audio_signal": audioSignal, "length": lengthTensor],
            outputNames: [outputName],
            runOptions: nil
        )
        guard let outputValue = outputs[outputName] else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        let logits = try extractLogits(from: outputValue)
        let decodedIds = greedyDecode(logits.data,
                                      frameCount: logits.frameCount,
                                      vocabSize: logits.vocabSize,
                                      blankId: tokenizer.blankId)
        return tokenizer.decode(ids: decodedIds)
    }

    /// Changes whenever `cleanup()` or `invalidateSession(for:)` runs. Read it at the moment a prepare
    /// is requested and pass it to `prepare(_:requestedAt:)`.
    var invalidationEpoch: Int { runtimeCache.invalidationEpoch }

    /// Builds the session, output metadata and tokenizer for `model` ahead of `transcribe()`, which
    /// then finds them cached. Shares a build that is already in flight. Throws without caching anything
    /// when the build fails or is deferred, in which case `transcribe()` builds and reports errors itself.
    ///
    /// - Parameter epoch: `invalidationEpoch` as read when the prepare was requested. A cleanup that
    ///   lands after that cancels the prepare instead of leaving a session cached behind it.
    func prepare(_ model: any TranscriptionModel, requestedAt epoch: Int) async throws {
        guard let fastConformerModel = model as? FastConformerModel else {
            throw VoiceInkEngineError.modelLoadFailed
        }
        _ = try await loadRuntime(for: fastConformerModel, request: .prepare(epoch: epoch))
    }

    func invalidateSession(for modelName: String) {
        runtimeCache.invalidate(modelName)
    }

    func cleanup() {
        runtimeCache.invalidateAll()
    }

    private func loadRuntime(
        for model: FastConformerModel, request: ONNXRuntimeCache<Runtime>.Request
    ) async throws -> Runtime {
        try await runtimeCache.runtime(for: model.name, request: request) { [weak self] in
            // The service is gone, so nobody is left to use the runtime. Callers keep it alive.
            guard let self else { throw VoiceInkEngineError.modelLoadFailed }
            return try self.buildRuntime(for: model)
        }
    }

    /// Same steps, in the same order, that `transcribe()` has always run: session, output name, tokenizer.
    private func buildRuntime(for model: FastConformerModel) throws -> Runtime {
        let session = try makeSession(for: model)
        guard let outputName = try session.outputNames().first else {
            throw VoiceInkEngineError.modelLoadFailed
        }
        let tokenizerURL = modelsDirectory
            .appendingPathComponent(model.name)
            .appendingPathComponent("tokens.txt")
        let tokenizer = try FastConformerTokenizer(tokensFileURL: tokenizerURL)
        return Runtime(session: session, outputName: outputName, tokenizer: tokenizer)
    }

    /// Created once, on first use. A failed attempt is remembered rather than retried, exactly as when
    /// the environment was created in `init`.
    private func runtimeEnvironment() -> ORTEnv? {
        envLock.lock()
        defer { envLock.unlock() }
        if !didAttemptEnvCreation {
            didAttemptEnvCreation = true
            do {
                env = try ORTEnv(loggingLevel: .warning)
            } catch {
                logger.error("Failed to initialize ONNX Runtime environment: \(AppLogger.errorMetadata(error), privacy: .public)")
            }
        }
        return env
    }

    private func makeSession(for model: FastConformerModel) throws -> ORTSession {
        guard let env = runtimeEnvironment() else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        let modelDirectory = modelsDirectory.appendingPathComponent(model.name)
        guard let modelPath = OnnxModelFileLocator.findModelFile(in: modelDirectory) else {
            logger.error("No ONNX model file found for \(model.name, privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }
        
        logger.info("Loading ONNX model for \(model.name, privacy: .public)")

        let options = try ORTSessionOptions()
        _ = try? options.setGraphOptimizationLevel(.all)
        if model.requiresMetal {
            _ = try? options.appendExecutionProvider("coreml", providerOptions: [:])
        }

        return try ORTSession(env: env, modelPath: modelPath.path, sessionOptions: options)
    }

    private func makeInputTensors(from features: [[Float]]) throws -> (audioSignal: ORTValue, length: ORTValue) {
        let frames = features.count
        let dimension = featureExtractor.featureDimension
        
        var transposed = [Float](repeating: 0, count: frames * dimension)
        for (frameIdx, frame) in features.enumerated() {
            for (featureIdx, value) in frame.enumerated() {
                transposed[featureIdx * frames + frameIdx] = value
            }
        }

        let audioDataLength = transposed.count * MemoryLayout<Float>.size
        let audioTensorData = NSMutableData(length: audioDataLength) ?? NSMutableData()
        transposed.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(audioTensorData.mutableBytes, baseAddress, audioDataLength)
        }

        let audioShape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: dimension), NSNumber(value: frames)]
        let audioSignal = try ORTValue(tensorData: audioTensorData, elementType: .float, shape: audioShape)
        
        var lengthValue: Int64 = Int64(frames)
        let lengthData = NSMutableData(bytes: &lengthValue, length: MemoryLayout<Int64>.size)
        let lengthTensor = try ORTValue(tensorData: lengthData, elementType: .int64, shape: [NSNumber(value: 1)])
        
        return (audioSignal, lengthTensor)
    }

    private func extractLogits(from value: ORTValue) throws -> (data: [Float], frameCount: Int, vocabSize: Int) {
        let typeInfo = try value.tensorTypeAndShapeInfo()
        let shape = typeInfo.shape.map { $0.intValue }
        guard shape.count >= 3 else {
            throw VoiceInkEngineError.modelLoadFailed
        }
        let frameCount = shape[shape.count - 2]
        let vocabSize = shape.last ?? 0
        let tensorData = try value.tensorData()
        let floatCount = tensorData.length / MemoryLayout<Float>.size
        var buffer = [Float](repeating: 0, count: floatCount)
        tensorData.getBytes(&buffer, length: tensorData.length)
        return (buffer, frameCount, vocabSize)
    }

    private func greedyDecode(_ logits: [Float], frameCount: Int, vocabSize: Int, blankId: Int) -> [Int] {
        guard frameCount > 0, vocabSize > 0 else { return [] }
        var decoded: [Int] = []
        decoded.reserveCapacity(frameCount)
        var previous = blankId

        for frame in 0..<frameCount {
            let offset = frame * vocabSize
            var maxValue: Float = -.infinity
            var maxIndex = blankId
            for vocabIndex in 0..<vocabSize {
                let value = logits[offset + vocabIndex]
                if value > maxValue {
                    maxValue = value
                    maxIndex = vocabIndex
                }
            }

            if maxIndex == blankId {
                previous = blankId
                continue
            }

            if maxIndex == previous {
                continue
            }

            decoded.append(maxIndex)
            previous = maxIndex
        }

        return decoded
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            return try AudioSampleReader.readPCM16LE(from: url)
        } catch {
            throw VoiceInkEngineError.transcriptionFailed
        }
    }
}
