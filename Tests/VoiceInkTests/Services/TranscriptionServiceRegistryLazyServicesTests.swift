import SwiftData
import XCTest
@testable import VoiceInk

/// The FluidAudio and ONNX services must only exist for users who actually use them, and the
/// record-start ONNX prepare must be harmless when it cannot build anything.
@MainActor
final class TranscriptionServiceRegistryLazyServicesTests: XCTestCase {
    private var container: ModelContainer!
    private var modelProvider: StubWhisperModelProvider!
    private var modelsDirectory: URL!

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: VocabularyWord.self, configurations: configuration)
        modelProvider = StubWhisperModelProvider()
        modelsDirectory = FileSystemHelper.createIsolatedDirectory(prefix: "TranscriptionServiceRegistry")
    }

    override func tearDown() async throws {
        FileSystemHelper.cleanupDirectory(modelsDirectory)
        modelsDirectory = nil
        modelProvider = nil
        container = nil
    }

    func testCleanupNeverCreatesUnusedServices() async {
        let registry = makeRegistry()

        await registry.cleanup()
        await registry.cleanup()

        XCTAssertNil(registry.cachedFluidAudioTranscriptionService)
        XCTAssertNil(registry.cachedFastConformerTranscriptionService)
        XCTAssertNil(registry.cachedSenseVoiceTranscriptionService)
    }

    func testAccessorsCreateEachServiceOnceAndCleanupKeepsIt() async {
        let registry = makeRegistry()

        let fluidAudio = registry.fluidAudioTranscriptionService
        let fastConformer = registry.fastConformerTranscriptionService
        let senseVoice = registry.senseVoiceTranscriptionService
        XCTAssertTrue(registry.fluidAudioTranscriptionService === fluidAudio)
        XCTAssertTrue(registry.fastConformerTranscriptionService === fastConformer)
        XCTAssertTrue(registry.senseVoiceTranscriptionService === senseVoice)
        XCTAssertTrue(registry.service(for: .fastConformer) as AnyObject === fastConformer)
        XCTAssertTrue(registry.service(for: .senseVoice) as AnyObject === senseVoice)
        XCTAssertTrue(registry.service(for: .fluidAudio) as AnyObject === fluidAudio)

        await registry.cleanup()

        XCTAssertTrue(registry.cachedFluidAudioTranscriptionService === fluidAudio)
        XCTAssertTrue(registry.cachedFastConformerTranscriptionService === fastConformer)
        XCTAssertTrue(registry.cachedSenseVoiceTranscriptionService === senseVoice)
    }

    func testPrepareONNXRuntimeIsANoOpForOtherProviders() async {
        let registry = makeRegistry()
        let cloudModel = CloudModel(
            name: "cloud", displayName: "Cloud", description: "", provider: .groq,
            isMultilingual: true, supportedLanguages: [:])
        let fluidAudioModel = FluidAudioModel(
            name: "parakeet", displayName: "Parakeet", description: "", size: "", speed: 0, accuracy: 0,
            ramUsage: 0, supportedLanguages: ["en": "English"])

        await registry.prepareONNXRuntimeIfNeeded(for: cloudModel)
        await registry.prepareONNXRuntimeIfNeeded(for: fluidAudioModel)

        XCTAssertNil(registry.cachedFluidAudioTranscriptionService)
        XCTAssertNil(registry.cachedFastConformerTranscriptionService)
        XCTAssertNil(registry.cachedSenseVoiceTranscriptionService)
    }

    func testPrepareONNXRuntimeSwallowsFailureWhenModelFilesAreMissing() async {
        let registry = makeRegistry()
        let missingName = "missing-onnx-model-\(UUID().uuidString)"

        // Neither model exists on disk, so both builds fail; the call must still simply return.
        await registry.prepareONNXRuntimeIfNeeded(for: makeFastConformerModel(named: missingName))
        await registry.prepareONNXRuntimeIfNeeded(for: makeSenseVoiceModel(named: missingName))

        XCTAssertNotNil(registry.cachedFastConformerTranscriptionService)
        XCTAssertNotNil(registry.cachedSenseVoiceTranscriptionService)
        XCTAssertNil(registry.cachedFluidAudioTranscriptionService)
    }

    func testServicePrepareReportsMissingModelsAndCanBeRetried() async {
        let fastConformer = FastConformerTranscriptionService(modelsDirectory: modelsDirectory)
        let senseVoice = SenseVoiceTranscriptionService(modelsDirectory: modelsDirectory)
        let fastConformerModel = makeFastConformerModel(named: "missing-fastconformer")
        let senseVoiceModel = makeSenseVoiceModel(named: "missing-sensevoice")

        // A failed prepare caches nothing, so every later attempt starts over and fails the same way.
        for _ in 0..<2 {
            await assertModelLoadFailed {
                try await fastConformer.prepare(fastConformerModel, requestedAt: fastConformer.invalidationEpoch)
            }
            await assertModelLoadFailed {
                try await senseVoice.prepare(senseVoiceModel, requestedAt: senseVoice.invalidationEpoch)
            }
        }
        // Each service only prepares its own kind of model.
        await assertModelLoadFailed {
            try await fastConformer.prepare(senseVoiceModel, requestedAt: fastConformer.invalidationEpoch)
        }
        await assertModelLoadFailed {
            try await senseVoice.prepare(fastConformerModel, requestedAt: senseVoice.invalidationEpoch)
        }
    }

    func testCleanupCancelsAServicePrepareRequestedBeforeIt() async {
        let fastConformer = FastConformerTranscriptionService(modelsDirectory: modelsDirectory)
        let senseVoice = SenseVoiceTranscriptionService(modelsDirectory: modelsDirectory)
        let fastConformerEpoch = fastConformer.invalidationEpoch
        let senseVoiceEpoch = senseVoice.invalidationEpoch

        fastConformer.cleanup()
        senseVoice.invalidateSession(for: "missing-sensevoice")
        XCTAssertNotEqual(fastConformer.invalidationEpoch, fastConformerEpoch)
        XCTAssertNotEqual(senseVoice.invalidationEpoch, senseVoiceEpoch)

        // Deferred before any build is attempted, so the missing model files are never even looked at.
        await assertDeferred {
            try await fastConformer.prepare(
                self.makeFastConformerModel(named: "missing-fastconformer"), requestedAt: fastConformerEpoch)
        }
        await assertDeferred {
            try await senseVoice.prepare(
                self.makeSenseVoiceModel(named: "missing-sensevoice"), requestedAt: senseVoiceEpoch)
        }
    }

    func testReleasingONNXRuntimesNeverCreatesServicesAndInvalidatesExistingOnes() {
        let registry = makeRegistry()

        registry.releaseONNXRuntimes()
        XCTAssertNil(registry.cachedFastConformerTranscriptionService)
        XCTAssertNil(registry.cachedSenseVoiceTranscriptionService)
        XCTAssertNil(registry.cachedFluidAudioTranscriptionService)

        let fastConformer = registry.fastConformerTranscriptionService
        let senseVoice = registry.senseVoiceTranscriptionService
        let fastConformerEpoch = fastConformer.invalidationEpoch
        let senseVoiceEpoch = senseVoice.invalidationEpoch

        registry.releaseONNXRuntimes()

        // The services stay; anything prepared or still building for them is invalidated.
        XCTAssertTrue(registry.cachedFastConformerTranscriptionService === fastConformer)
        XCTAssertTrue(registry.cachedSenseVoiceTranscriptionService === senseVoice)
        XCTAssertNotEqual(fastConformer.invalidationEpoch, fastConformerEpoch)
        XCTAssertNotEqual(senseVoice.invalidationEpoch, senseVoiceEpoch)
        XCTAssertNil(registry.cachedFluidAudioTranscriptionService)
    }

    private func makeRegistry() -> TranscriptionServiceRegistry {
        TranscriptionServiceRegistry(
            modelProvider: modelProvider, modelsDirectory: modelsDirectory, modelContext: container.mainContext)
    }

    private func makeFastConformerModel(named name: String) -> FastConformerModel {
        FastConformerModel(
            name: name, displayName: "FastConformer", description: "", size: "", speed: 0, accuracy: 0,
            ramUsage: 0, requiresMetal: false, isMultilingualModel: false, supportedLanguages: ["en": "English"],
            modelURL: "", tokenizerURL: "", checksum: nil)
    }

    private func makeSenseVoiceModel(named name: String) -> SenseVoiceModel {
        SenseVoiceModel(
            name: name, displayName: "SenseVoice", description: "", size: "", speed: 0, accuracy: 0,
            ramUsage: 0, isMultilingualModel: true, supportedLanguages: ["en": "English"],
            modelURL: "", tokenizerURL: "")
    }

    private func assertDeferred(
        _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected the prepare to be deferred", file: file, line: line)
        } catch is ONNXRuntimeBuildDeferredError {
            // Expected: cleanup ran after the prepare was requested.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertModelLoadFailed(
        _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected the prepare to fail", file: file, line: line)
        } catch VoiceInkEngineError.modelLoadFailed {
            // Expected: there is no model to load.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class StubWhisperModelProvider: WhisperModelProvider {
    let availableModels: [WhisperModelFile] = []
}
