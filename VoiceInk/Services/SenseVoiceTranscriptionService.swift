import Foundation
import AVFoundation
import OnnxRuntimeBindings
import os.log

final class SenseVoiceTranscriptionService: TranscriptionService {
    /// Everything `transcribe()` needs besides the audio. Built once per model and cached as a unit.
    private struct Runtime {
        let session: ORTSession
        let tokenizer: SenseVoiceTokenizer
    }

    private let modelsDirectory: URL
    private let featureExtractor = FastConformerFeatureExtractor()
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "SenseVoice")

    // The ONNX Runtime environment is created with the first session build, which runs off the main
    // actor, so constructing this service (done on the main actor by the registry) stays cheap.
    private let envLock = NSLock()
    private var env: ORTEnv?
    private var didAttemptEnvCreation = false
    /// Shared single-flight, generation-safe cache; see `ONNXRuntimeCache.swift`.
    private let runtimeCache = ONNXRuntimeCache<Runtime>()

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard model.provider == .senseVoice else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        let samples = try readAudioSamples(from: audioURL)
        guard !samples.isEmpty else { throw VoiceInkEngineError.transcriptionFailed }
        
        let rawFeatures = featureExtractor.extract(samples: samples)
        guard !rawFeatures.isEmpty else { throw VoiceInkEngineError.transcriptionFailed }
        
        // SenseVoice uses LFR (Low Frame Rate) features: stack 7 frames with stride 6
        // This converts 80-dim features to 560-dim (80 * 7)
        let features = applyLFR(features: rawFeatures, lfrM: 7, lfrN: 6)
        guard !features.isEmpty else { throw VoiceInkEngineError.transcriptionFailed }
        
        logger.notice("SenseVoice: Feature shape after LFR: \(features.count) frames x \(features.first?.count ?? 0) dims")

        // Normally cached by the record-start prepare; joins that build if it is still running.
        let runtime = try await loadRuntime(forModelNamed: model.name, request: .transcribe)
        let session = runtime.session
        let tokenizer = runtime.tokenizer
        
        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()
        
        logger.notice("SenseVoice input names: \(inputNames, privacy: .public)")
        logger.notice("SenseVoice output names: \(outputNames, privacy: .public)")
        
        // SenseVoice expects: x, x_length, language, text_norm
        guard let outputName = outputNames.first else {
            logger.error("SenseVoice: Could not find output name")
            throw VoiceInkEngineError.modelLoadFailed
        }
        
        let inputValue = try makeInputTensor(from: features)
        let lengthValue = try makeLengthTensor(frameCount: features.count)
        let languageId = senseVoiceLanguageId(context.language)
        let languageValue = try makeLanguageTensor(languageId: languageId)
        let textNormValue = try makeTextNormTensor(normalize: true)
        
        logger.notice("SenseVoice: Using language ID \(languageId)")
        
        // Build inputs dictionary using actual input names from model
        var inputs: [String: ORTValue] = [:]
        for name in inputNames {
            if name == "x" {
                inputs[name] = inputValue
            } else if name == "x_length" {
                inputs[name] = lengthValue
            } else if name == "language" {
                inputs[name] = languageValue
            } else if name == "text_norm" {
                inputs[name] = textNormValue
            }
        }
        
        logger.notice("SenseVoice: Running inference with \(inputs.count) inputs")

        let outputs = try session.run(withInputs: inputs,
                                      outputNames: [outputName],
                                      runOptions: nil)
        guard let outputValue = outputs[outputName] else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        let tokenIds = try extractTokenIds(from: outputValue)
        return tokenizer.decode(ids: tokenIds)
    }

    /// Changes whenever `cleanup()` or `invalidateSession(for:)` runs. Read it at the moment a prepare
    /// is requested and pass it to `prepare(_:requestedAt:)`.
    var invalidationEpoch: Int { runtimeCache.invalidationEpoch }

    /// Builds the session and tokenizer for `model` ahead of `transcribe()`, which then finds them
    /// cached. Shares a build that is already in flight. Throws without caching anything when the build
    /// fails or is deferred, in which case `transcribe()` builds and reports errors itself.
    ///
    /// - Parameter epoch: `invalidationEpoch` as read when the prepare was requested. A cleanup that
    ///   lands after that cancels the prepare instead of leaving a session cached behind it.
    func prepare(_ model: any TranscriptionModel, requestedAt epoch: Int) async throws {
        guard model.provider == .senseVoice else {
            throw VoiceInkEngineError.modelLoadFailed
        }
        _ = try await loadRuntime(forModelNamed: model.name, request: .prepare(epoch: epoch))
    }

    func invalidateSession(for modelName: String) {
        runtimeCache.invalidate(modelName)
    }

    func cleanup() {
        runtimeCache.invalidateAll()
    }

    private func loadRuntime(
        forModelNamed modelName: String, request: ONNXRuntimeCache<Runtime>.Request
    ) async throws -> Runtime {
        try await runtimeCache.runtime(for: modelName, request: request) { [weak self] in
            // The service is gone, so nobody is left to use the runtime. Callers keep it alive.
            guard let self else { throw VoiceInkEngineError.modelLoadFailed }
            return try self.buildRuntime(forModelNamed: modelName)
        }
    }

    /// Same steps, in the same order, that `transcribe()` has always run: session, then tokenizer.
    private func buildRuntime(forModelNamed modelName: String) throws -> Runtime {
        let session = try makeSession(for: modelName)
        let tokenizerURL = modelsDirectory
            .appendingPathComponent(modelName)
            .appendingPathComponent("tokens.txt")
        let tokenizer = try SenseVoiceTokenizer(tokensFileURL: tokenizerURL)
        return Runtime(session: session, tokenizer: tokenizer)
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
                logger.notice("ONNX Runtime environment initialized successfully")
            } catch {
                logger.error("Failed to initialize ONNX Runtime environment: \(AppLogger.errorMetadata(error), privacy: .public)")
            }
        }
        return env
    }

    private func makeSession(for modelName: String) throws -> ORTSession {
        guard let env = runtimeEnvironment() else {
            logger.error("SenseVoice: ONNX environment is nil")
            throw VoiceInkEngineError.modelLoadFailed
        }

        let modelPath = modelsDirectory
            .appendingPathComponent(modelName)
            .appendingPathComponent("model.int8.onnx")

        logger.notice("SenseVoice model lookup started for \(modelName, privacy: .public)")
        logger.notice("SenseVoice model exists: \(FileManager.default.fileExists(atPath: modelPath.path), privacy: .public)")
        
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            logger.error("SenseVoice: Model file not found at path")
            throw VoiceInkEngineError.modelLoadFailed
        }

        let options = try ORTSessionOptions()
        _ = try? options.setGraphOptimizationLevel(.all)
        // Skip CoreML for SenseVoice - use CPU for compatibility
        
        let session: ORTSession
        do {
            session = try ORTSession(env: env, modelPath: modelPath.path, sessionOptions: options)
            logger.notice("SenseVoice: ONNX session created successfully")
        } catch {
            logger.error("SenseVoice: Failed to create ONNX session: \(AppLogger.errorMetadata(error), privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }
        return session
    }

    // LFR (Low Frame Rate) feature stacking for SenseVoice
    // Stacks lfrM frames with stride lfrN to produce higher dimensional features
    private func applyLFR(features: [[Float]], lfrM: Int, lfrN: Int) -> [[Float]] {
        guard !features.isEmpty else { return [] }
        
        let numFrames = features.count
        let featureDim = features[0].count
        
        // Calculate output frames
        var lfrFeatures: [[Float]] = []
        
        var i = 0
        while i < numFrames {
            var stackedFrame: [Float] = []
            stackedFrame.reserveCapacity(lfrM * featureDim)
            
            for j in 0..<lfrM {
                let frameIdx = min(i + j, numFrames - 1)
                stackedFrame.append(contentsOf: features[frameIdx])
            }
            
            lfrFeatures.append(stackedFrame)
            i += lfrN
        }
        
        return lfrFeatures
    }

    private func makeInputTensor(from features: [[Float]]) throws -> ORTValue {
        let frames = features.count
        guard let firstFrame = features.first else {
            throw VoiceInkEngineError.transcriptionFailed
        }
        let dimension = firstFrame.count  // Use actual dimension from features
        
        var flattened: [Float] = []
        flattened.reserveCapacity(frames * dimension)
        for frame in features {
            flattened.append(contentsOf: frame)
        }

        let dataLength = flattened.count * MemoryLayout<Float>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        flattened.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }

        let shape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: frames), NSNumber(value: dimension)]
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }

    private func makeLengthTensor(frameCount: Int) throws -> ORTValue {
        var length = Int32(frameCount)
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &length) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    // Maps user's selected language to SenseVoice language ID
    // SenseVoice language IDs: 0=zh, 1=yue, 2=en, 3=ja, 4=ko
    private func senseVoiceLanguageId(_ selectedLanguage: String?) -> Int32 {
        let selectedLanguage = selectedLanguage ?? "en"
        
        switch selectedLanguage.lowercased() {
        case "zh", "zh-cn", "zh-tw", "chinese":
            return 0  // Chinese
        case "yue", "cantonese":
            return 1  // Cantonese
        case "en", "english", "auto":
            return 2  // English (default for auto)
        case "ja", "japanese":
            return 3  // Japanese
        case "ko", "korean":
            return 4  // Korean
        default:
            return 2  // Default to English for unsupported languages
        }
    }

    // Language IDs: 0=zh, 1=yue, 2=en, 3=ja, 4=ko
    private func makeLanguageTensor(languageId: Int32) throws -> ORTValue {
        var langId = languageId
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &langId) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    // text_norm: 0 = without inverse text normalization, 1 = with inverse text normalization
    private func makeTextNormTensor(normalize: Bool) throws -> ORTValue {
        var normFlag = Int32(normalize ? 1 : 0)
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &normFlag) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    private func extractTokenIds(from value: ORTValue) throws -> [Int] {
        let tensorData = try value.tensorData()
        let typeInfo = try value.tensorTypeAndShapeInfo()
        let elementType = typeInfo.elementType
        
        switch elementType {
        case .int64:
            let count = tensorData.length / MemoryLayout<Int64>.size
            var buffer = [Int64](repeating: 0, count: count)
            tensorData.getBytes(&buffer, length: tensorData.length)
            return buffer.map { Int($0) }
        case .int32:
            let count = tensorData.length / MemoryLayout<Int32>.size
            var buffer = [Int32](repeating: 0, count: count)
            tensorData.getBytes(&buffer, length: tensorData.length)
            return buffer.map { Int($0) }
        default:
            let shape = typeInfo.shape.map { $0.intValue }
            if elementType == .float, shape.count >= 2 {
                // `tensorData` aliases storage owned by `value`; keep both alive while it is read.
                let inPlaceTokenIds = withExtendedLifetime((value, tensorData)) {
                    Self.greedyDecodeInPlace(
                        logits: UnsafeRawBufferPointer(start: tensorData.bytes, count: tensorData.length),
                        frameCount: shape[shape.count - 2],
                        vocabSize: shape.last ?? 1
                    )
                }
                if let inPlaceTokenIds {
                    return inPlaceTokenIds
                }
            }

            let floatCount = tensorData.length / MemoryLayout<Float>.size
            var floatBuffer = [Float](repeating: 0, count: floatCount)
            tensorData.getBytes(&floatBuffer, length: tensorData.length)
            
            if shape.count >= 2 {
                let vocabSize = shape.last ?? 1
                let frameCount = shape[shape.count - 2]
                return greedyDecode(floatBuffer, frameCount: frameCount, vocabSize: vocabSize)
            }
            return []
        }
    }

    private func greedyDecode(_ logits: [Float], frameCount: Int, vocabSize: Int) -> [Int] {
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

    /// The same greedy argmax as `greedyDecode(_:frameCount:vocabSize:)`, read straight from the logits
    /// tensor's own storage so the logits (frames x vocabulary floats, roughly 1.7 MB per second of
    /// audio) are not copied a second time. Identical comparison and iteration order over the same bytes.
    /// Returns nil when the storage cannot be read in place; the caller then takes the copying path.
    static func greedyDecodeInPlace(logits: UnsafeRawBufferPointer, frameCount: Int, vocabSize: Int) -> [Int]? {
        guard frameCount > 0, vocabSize > 0 else { return nil }
        let (elementCount, overflow) = frameCount.multipliedReportingOverflow(by: vocabSize)
        guard !overflow,
              elementCount <= logits.count / MemoryLayout<Float>.stride,
              let baseAddress = logits.baseAddress,
              Int(bitPattern: baseAddress) % MemoryLayout<Float>.alignment == 0
        else { return nil }

        let values = baseAddress.assumingMemoryBound(to: Float.self)
        var decoded: [Int] = []
        decoded.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let frameValues = values + frame * vocabSize
            var maxValue: Float = -.infinity
            var maxIndex = 0
            for vocabIndex in 0..<vocabSize {
                let value = frameValues[vocabIndex]
                if value > maxValue {
                    maxValue = value
                    maxIndex = vocabIndex
                }
            }
            decoded.append(maxIndex)
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
