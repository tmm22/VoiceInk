import Foundation
import XCTest
@testable import VoiceInk

/// The resolver asks about one model or one provider instead of building the whole usable/connected
/// list. These tests pin the single-item answers to the list answers they replaced.
@MainActor
final class ModeRuntimeResolverSingleItemTests: XCTestCase {
    private enum Outcome: Equatable {
        case noMode
        case noSelection
        case modelNotFound
        case unavailable(String)
        case available(String)
    }

    private var modelsDirectory: URL!
    // TranscriptionModelManager holds these weakly, so the test keeps them alive.
    private var whisper: WhisperModelManager!
    private var fluidAudio: FluidAudioModelManager!
    private var manager: TranscriptionModelManager!

    override func setUp() async throws {
        modelsDirectory = FileSystemHelper.createIsolatedDirectory(prefix: "ResolverSingleItem")
        whisper = WhisperModelManager(modelsDirectory: modelsDirectory)
        fluidAudio = FluidAudioModelManager()
        manager = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluidAudio)
    }

    override func tearDown() async throws {
        manager = nil
        fluidAudio = nil
        whisper = nil
        FileSystemHelper.cleanupDirectory(modelsDirectory)
        modelsDirectory = nil
    }

    // MARK: - Transcription models

    func testSingleModelCheckMatchesUsableListForEveryCatalogueEntry() {
        let usable = manager.usableModels
        let usableIDs = Set(usable.map { $0.id })
        let usableKeys = Set(usable.map { $0.selectionKey })

        XCTAssertFalse(manager.allAvailableModels.isEmpty)
        for model in manager.allAvailableModels {
            XCTAssertEqual(
                manager.isUsable(model),
                usableIDs.contains(model.id),
                "isUsable disagrees with usableModels for \(model.selectionKey)"
            )
            XCTAssertEqual(
                manager.hasUsableModel(selectionKey: model.selectionKey),
                usableKeys.contains(model.selectionKey),
                "hasUsableModel disagrees with usableModels for \(model.selectionKey)"
            )
        }
    }

    func testModelResolutionMatchesUsableListForEveryCatalogueEntry() {
        let usableKeys = Set(manager.usableModels.map { $0.selectionKey })

        for model in manager.allAvailableModels {
            let key = model.selectionKey
            let expected: Outcome = usableKeys.contains(key) ? .available(key) : .unavailable(key)
            XCTAssertEqual(outcome(selecting: key), expected)
        }
    }

    func testUsableListStaysAFilterInCatalogueOrder() {
        let custom = makeCustomModel()
        let missing = ImportedWhisperModel(fileBaseName: "resolver-missing-\(UUID().uuidString)")
        let local = ImportedWhisperModel(fileBaseName: "resolver-local-\(UUID().uuidString)")
        whisper.availableModels = [
            WhisperModelFile(name: local.name, url: modelsDirectory.appendingPathComponent("\(local.name).bin"))
        ]
        manager.allAvailableModels = [local, missing, custom]

        XCTAssertEqual(manager.usableModels.map { $0.selectionKey }, [local.selectionKey, custom.selectionKey])
        XCTAssertTrue(manager.hasUsableModel(selectionKey: local.selectionKey))
        XCTAssertTrue(manager.hasUsableModel(selectionKey: custom.selectionKey))
        XCTAssertFalse(manager.hasUsableModel(selectionKey: missing.selectionKey))
        XCTAssertFalse(manager.hasUsableModel(selectionKey: "resolver-not-in-catalogue"))
    }

    func testSharedSelectionKeyIsUsableWhenAnyEntryIs() {
        let custom = makeCustomModel()
        // A different, unusable entry that happens to carry the same selection key.
        let shadow = ImportedWhisperModel(fileBaseName: custom.selectionKey)
        XCTAssertEqual(shadow.selectionKey, custom.selectionKey)

        let catalogues: [[any TranscriptionModel]] = [[shadow, custom], [custom, shadow]]
        for catalogue in catalogues {
            manager.allAvailableModels = catalogue
            XCTAssertTrue(manager.usableModels.contains { $0.selectionKey == custom.selectionKey })
            XCTAssertTrue(manager.hasUsableModel(selectionKey: custom.selectionKey))
        }

        manager.allAvailableModels = [shadow]
        XCTAssertFalse(manager.usableModels.contains { $0.selectionKey == custom.selectionKey })
        XCTAssertFalse(manager.hasUsableModel(selectionKey: custom.selectionKey))

        manager.allAvailableModels = []
        XCTAssertFalse(manager.hasUsableModel(selectionKey: custom.selectionKey))
    }

    func testResolutionOutcomesForUnusableUnknownAndMissingSelections() {
        let missing = ImportedWhisperModel(fileBaseName: "resolver-missing-\(UUID().uuidString)")
        let custom = makeCustomModel()
        manager.allAvailableModels = [missing, custom]

        XCTAssertEqual(outcome(selecting: missing.selectionKey), .unavailable(missing.selectionKey))
        XCTAssertEqual(outcome(selecting: custom.selectionKey), .available(custom.selectionKey))
        XCTAssertEqual(outcome(selecting: "resolver-not-in-catalogue"), .modelNotFound)
        XCTAssertEqual(outcome(selecting: ""), .noSelection)
        XCTAssertEqual(outcome(selecting: nil), .noSelection)
    }

    // Enhancement providers are deliberately not exercised here. `AIService.connectedProviders` is
    // `AIProvider.allCases.filter(isConnected)` and `firstConnectedProvider` is the first match of
    // the same predicate, so they agree by construction, while a test that builds a real
    // `AIService` reaches `CustomAIProviderManager.shared` and the Keychain in the hosted test
    // process, which shares the installed app's preferences.

    // MARK: - Helpers

    private func outcome(selecting selectionKey: String?) -> Outcome {
        let mode = ModeConfig(
            name: "Resolver Test",
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: selectionKey
        )

        switch ModeRuntimeResolver.transcriptionModelResolution(mode: mode, transcriptionModelManager: manager) {
        case .noMode:
            return .noMode
        case .noSelection:
            return .noSelection
        case .modelNotFound:
            return .modelNotFound
        case .unavailable(_, let model):
            return .unavailable(model.selectionKey)
        case .available(_, let model):
            return .available(model.selectionKey)
        }
    }

    private func makeCustomModel() -> CustomCloudModel {
        CustomCloudModel(
            name: "resolver-custom",
            displayName: "Resolver Custom",
            description: "",
            apiEndpoint: "https://example.invalid/v1/audio/transcriptions",
            modelName: "resolver-custom"
        )
    }
}
