import XCTest
@testable import VoiceInk

@MainActor
final class CustomModelManagerCredentialTests: XCTestCase {
    func testDeletionFailurePreservesModelMetadata() {
        let credentials = CredentialStoreStub()
        credentials.deleteSucceeds = false
        let manager = CustomModelManager(credentialStore: credentials)
        let model = makeModel()
        XCTAssertTrue(manager.addCustomModel(model))

        XCTAssertFalse(manager.removeCustomModel(withId: model.id))
        XCTAssertTrue(manager.customModels.contains { $0.id == model.id })
    }

    func testTransientCredentialIsNotRetainedInPublishedModels() {
        let credentials = CredentialStoreStub()
        let manager = CustomModelManager(credentialStore: credentials)
        var model = makeModel()
        model.transientApiKey = "secret"

        XCTAssertTrue(manager.addCustomModel(model))
        XCTAssertNil(manager.customModels.first?.transientApiKey)
        XCTAssertEqual(credentials.savedKeys[model.id], "secret")
    }

    func testFailedLegacyMigrationPreservesOriginalDataForRetry() throws {
        let credentials = CredentialStoreStub()
        credentials.saveSucceeds = false
        let dataStore = CustomModelDataStoreStub()
        let legacyData = try JSONEncoder().encode([LegacyModelFixture.make()])
        dataStore.values["customCloudModels"] = legacyData

        let manager = CustomModelManager(
            credentialStore: credentials,
            dataStore: dataStore,
            loadsStoredModels: true
        )

        XCTAssertTrue(manager.customModels.isEmpty)
        XCTAssertEqual(dataStore.values["customCloudModels"], legacyData)
    }

    func testSuccessfulLegacyMigrationRewritesKeylessData() throws {
        let credentials = CredentialStoreStub()
        let dataStore = CustomModelDataStoreStub()
        let fixture = LegacyModelFixture.make()
        let legacyData = try JSONEncoder().encode([fixture])
        dataStore.values["customCloudModels"] = legacyData

        let manager = CustomModelManager(
            credentialStore: credentials,
            dataStore: dataStore,
            loadsStoredModels: true
        )

        XCTAssertEqual(manager.customModels.count, 1)
        XCTAssertEqual(credentials.savedKeys[fixture.id], fixture.apiKey)
        let rewritten = try XCTUnwrap(dataStore.values["customCloudModels"])
        XCTAssertFalse(String(decoding: rewritten, as: UTF8.self).contains(fixture.apiKey))
    }

    func testReplacementDeletesCredentialsForRemovedModels() {
        let credentials = CredentialStoreStub()
        let manager = CustomModelManager(credentialStore: credentials)
        var model = makeModel()
        model.transientApiKey = "secret"
        XCTAssertTrue(manager.addCustomModel(model))

        XCTAssertEqual(manager.replaceCustomModels([]), .success)
        XCTAssertNil(credentials.savedKeys[model.id])
        XCTAssertTrue(manager.customModels.isEmpty)
    }

    func testRollbackFailureRetainsIncomingMetadataForRetry() {
        let credentials = CredentialStoreStub()
        credentials.saveSucceeds = false
        credentials.deleteSucceeds = false
        let manager = CustomModelManager(credentialStore: credentials)
        var model = makeModel()
        model.transientApiKey = "secret"

        XCTAssertEqual(manager.replaceCustomModels([model]), .partialFailure)
        XCTAssertTrue(manager.customModels.contains { $0.id == model.id })
        XCTAssertNil(manager.customModels.first?.transientApiKey)
    }

    func testSnapshotFailureAbortsBeforeCredentialMutation() {
        let credentials = CredentialStoreStub()
        credentials.snapshotFails = true
        let manager = CustomModelManager(credentialStore: credentials)
        var model = makeModel()
        model.transientApiKey = "secret"

        XCTAssertEqual(manager.replaceCustomModels([model]), .failed)
        XCTAssertTrue(credentials.savedKeys.isEmpty)
        XCTAssertTrue(manager.customModels.isEmpty)
    }

    func testDuplicateIncomingIdentifiersAreRejectedBeforeMutation() {
        let credentials = CredentialStoreStub()
        let manager = CustomModelManager(credentialStore: credentials)
        var first = makeModel()
        first.transientApiKey = "first"
        var duplicate = first
        duplicate.transientApiKey = "second"

        XCTAssertEqual(manager.replaceCustomModels([first, duplicate]), .failed)
        XCTAssertTrue(credentials.savedKeys.isEmpty)
    }

    private func makeModel() -> CustomCloudModel {
        CustomCloudModel(
            name: "test",
            displayName: "Test",
            description: "Test model",
            apiEndpoint: "https://example.com/transcribe",
            modelName: "test-model"
        )
    }
}

private final class CredentialStoreStub: CustomModelCredentialStoring {
    var savedKeys: [UUID: String] = [:]
    var deleteSucceeds = true
    var saveSucceeds = true
    var snapshotFails = false

    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        guard saveSucceeds else { return false }
        savedKeys[modelId] = key
        return true
    }

    func readCustomModelAPIKey(forModelId modelId: UUID) -> KeychainReadResult {
        if snapshotFails { return .failed }
        return savedKeys[modelId].map(KeychainReadResult.present) ?? .absent
    }

    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        guard deleteSucceeds else { return false }
        savedKeys[modelId] = nil
        return true
    }
}

private final class CustomModelDataStoreStub: CustomModelDataStoring {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) { values[key] = data }
}

private struct LegacyModelFixture: Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let apiEndpoint: String
    let apiKey: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    static func make() -> Self {
        Self(
            id: UUID(),
            name: "legacy",
            displayName: "Legacy",
            description: "Legacy model",
            provider: .custom,
            apiEndpoint: "https://example.com/transcribe",
            apiKey: "legacy-secret",
            modelName: "legacy-model",
            isMultilingualModel: true,
            supportedLanguages: [:]
        )
    }
}
