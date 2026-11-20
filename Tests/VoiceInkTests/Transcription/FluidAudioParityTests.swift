import Foundation
import XCTest
@testable import VoiceInk

final class FluidAudioParityTests: XCTestCase {
    @MainActor
    func testUltraSelectionUsesItsOwnModelAndSupportsLanguageHints() throws {
        let model = try XCTUnwrap(TranscriptionModelRegistry.models.first { $0.name == "parakeet-ultra" } as? FluidAudioModel)
        XCTAssertTrue(model.supportsStreaming)
        XCTAssertEqual(FluidAudioModelManager.asrVersion(for: model.name), .ultra)
        XCTAssertEqual(FluidAudioTranscriptionService.languageHint(from: "fr", model: model)?.rawValue, "fr")
        XCTAssertNil(FluidAudioTranscriptionService.languageHint(from: "auto", model: model))
    }

    func testInterruptedModelBundleRemainsRetryable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mlmodelc")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(FluidAudioModelManager.modelFileIsReady(at: root))
        try Data([1]).write(to: root.appendingPathComponent("coremldata.bin"))
        let weights = root.appendingPathComponent("weights")
        try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
        let partial = weights.appendingPathComponent("weight.bin.partial")
        try Data([1]).write(to: partial)
        XCTAssertFalse(FluidAudioModelManager.modelFileIsReady(at: root))
        try FileManager.default.moveItem(at: partial, to: weights.appendingPathComponent("weight.bin"))
        XCTAssertTrue(FluidAudioModelManager.modelFileIsReady(at: root))
    }

    func testOversizedLiveBufferRequestsTheCompleteRecording() async {
        let provider = FluidAudioStreamingProvider(fluidAudioService: FluidAudioTranscriptionService())
        do {
            try await provider.sendAudioChunk(Data(count: 91 * 16_000 * 2))
            XCTFail("Expected an oversized live input to use the on-disk recording")
        } catch {
            XCTAssertEqual(provider.stopDisposition, .useBatchFallback)
        }
    }
}
