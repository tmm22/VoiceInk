import Foundation
import AVFoundation
import OnnxRuntimeBindings
import OSLog

private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "FastConformerTranscriptionService")

final class FastConformerTranscriptionService: TranscriptionService {
    private let modelsDirectory: URL
    private let featureExtractor = FastConformerFeatureExtractor()

    private var env: ORTEnv?
    private var sessions: [String: ORTSession] = [:]
    private var metadataCache: [String: (input: String, output: String)] = [:]
    private var tokenizerCache: [String: FastConformerTokenizer] = [:]
    private let cacheLock = NSLock()

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        self.env = try? ORTEnv(loggingLevel: .warning)
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let fastConformerModel = model as? FastConformerModel else {
            throw WhisperStateError.modelLoadFailed
        }

        let samples = try readAudioSamples(from: audioURL)
        guard !samples.isEmpty else { throw WhisperStateError.transcriptionFailed }
        let features = featureExtractor.extract(samples: samples)
        guard !features.isEmpty else { throw WhisperStateError.transcriptionFailed }

        let session = try ensureSession(for: fastConformerModel)
        let outputName = try outputMetadata(for: fastConformerModel, session: session)
        let tokenizer = try tokenizer(for: fastConformerModel)
        
        let (audioSignal, lengthTensor) = try makeInputTensors(from: features)

        let outputs = try session.run(
            withInputs: ["audio_signal": audioSignal, "length": lengthTensor],
            outputNames: [outputName],
            runOptions: nil
        )
        guard let outputValue = outputs[outputName] else {
            throw WhisperStateError.transcriptionFailed
        }

        let logits = try extractLogits(from: outputValue)
        let decodedIds = greedyDecode(logits.data,
                                      frameCount: logits.frameCount,
                                      vocabSize: logits.vocabSize,
                                      blankId: tokenizer.blankId)
        return tokenizer.decode(ids: decodedIds)
    }

    func invalidateSession(for modelName: String) {
        cacheLock.lock()
        sessions[modelName] = nil
        metadataCache[modelName] = nil
        tokenizerCache[modelName] = nil
        cacheLock.unlock()
    }

    func cleanup() {
        cacheLock.lock()
        sessions.removeAll()
        metadataCache.removeAll()
        tokenizerCache.removeAll()
        cacheLock.unlock()
    }

    private func tokenizer(for model: FastConformerModel) throws -> FastConformerTokenizer {
        cacheLock.lock()
        if let cached = tokenizerCache[model.name] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let tokenizerURL = modelsDirectory
            .appendingPathComponent(model.name)
            .appendingPathComponent("tokens.txt")
        let tokenizer = try FastConformerTokenizer(tokensFileURL: tokenizerURL)
        cacheLock.lock()
        tokenizerCache[model.name] = tokenizer
        cacheLock.unlock()
        return tokenizer
    }

    private func ensureSession(for model: FastConformerModel) throws -> ORTSession {
        cacheLock.lock()
        if let session = sessions[model.name] {
            cacheLock.unlock()
            return session
        }
        cacheLock.unlock()
        guard let env = env else {
            throw WhisperStateError.modelLoadFailed
        }

        let modelDirectory = modelsDirectory.appendingPathComponent(model.name)
        guard let modelPath = OnnxModelFileLocator.findModelFile(in: modelDirectory) else {
            logger.error("No ONNX model file found in directory: \(modelDirectory.path)")
            throw WhisperStateError.modelLoadFailed
        }
        
        logger.info("Loading ONNX model: \(modelPath.lastPathComponent) for \(model.name)")

        let options = try ORTSessionOptions()
        _ = try? options.setGraphOptimizationLevel(.all)
        if model.requiresMetal {
            _ = try? options.appendExecutionProvider("coreml", providerOptions: [:])
        }

        let session = try ORTSession(env: env, modelPath: modelPath.path, sessionOptions: options)
        cacheLock.lock()
        sessions[model.name] = session
        cacheLock.unlock()
        return session
    }

    private func outputMetadata(for model: FastConformerModel, session: ORTSession) throws -> String {
        cacheLock.lock()
        if let cached = metadataCache[model.name] {
            cacheLock.unlock()
            return cached.1
        }
        cacheLock.unlock()
        guard let outputName = try session.outputNames().first else {
            throw WhisperStateError.modelLoadFailed
        }
        cacheLock.lock()
        metadataCache[model.name] = ("audio_signal", outputName)
        cacheLock.unlock()
        return outputName
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

        let audioShape: [NSNumber] = [1, NSNumber(value: dimension), NSNumber(value: frames)]
        let audioSignal = try ORTValue(tensorData: audioTensorData, elementType: .float, shape: audioShape)
        
        var lengthValue: Int64 = Int64(frames)
        let lengthData = NSMutableData(bytes: &lengthValue, length: MemoryLayout<Int64>.size)
        let lengthTensor = try ORTValue(tensorData: lengthData, elementType: .int64, shape: [1])
        
        return (audioSignal, lengthTensor)
    }

    private func extractLogits(from value: ORTValue) throws -> (data: [Float], frameCount: Int, vocabSize: Int) {
        let typeInfo = try value.tensorTypeAndShapeInfo()
        let shape = typeInfo.shape.map { $0.intValue }
        guard shape.count >= 3 else {
            throw WhisperStateError.modelLoadFailed
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
            throw WhisperStateError.transcriptionFailed
        }
    }
}
