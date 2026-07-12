import Foundation
import os

protocol CustomModelCredentialStoring: AnyObject {
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool
    func readCustomModelAPIKey(forModelId modelId: UUID) -> KeychainReadResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool
}

extension APIKeyManager: CustomModelCredentialStoring {}

enum CustomModelReplacementResult: Equatable {
    case success
    case failed
    case partialFailure
}

protocol CustomModelDataStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

private final class AppSettingsCustomModelDataStore: CustomModelDataStoring {
    func data(forKey key: String) -> Data? { AppSettings.data(forKey: key) }
    func set(_ data: Data, forKey key: String) { AppSettings.setValue(data, forKey: key) }
}

@MainActor
class CustomModelManager: ObservableObject {
    static let shared = CustomModelManager(
        credentialStore: APIKeyManager.shared,
        dataStore: AppSettingsCustomModelDataStore(),
        loadsStoredModels: true
    )
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "CustomModelManager")
    private let customModelsKey = "customCloudModels"
    private let credentialStore: any CustomModelCredentialStoring
    private let dataStore: any CustomModelDataStoring
    private let persistsChanges: Bool
    
    @Published var customModels: [CustomCloudModel] = []
    
    init(
        credentialStore: any CustomModelCredentialStoring,
        dataStore: any CustomModelDataStoring = AppSettingsCustomModelDataStore(),
        loadsStoredModels: Bool = false,
        persistsChanges: Bool = false
    ) {
        self.credentialStore = credentialStore
        self.dataStore = dataStore
        self.persistsChanges = persistsChanges || loadsStoredModels
        if loadsStoredModels { loadCustomModels() }
    }
    
    // MARK: - CRUD Operations
    
    @discardableResult
    func addCustomModel(_ model: CustomCloudModel) -> Bool {
        // Save API key to Keychain if present in transient property
        if let apiKey = model.transientApiKey, !apiKey.isEmpty {
            guard credentialStore.saveCustomModelAPIKey(apiKey, forModelId: model.id) else {
                logger.error("Failed to save API key for custom model")
                return false
            }
        }
        
        var sanitizedModel = model
        sanitizedModel.transientApiKey = nil
        customModels.append(sanitizedModel)
        saveCustomModels()
        return true
    }

    @discardableResult
    func removeCustomModel(withId id: UUID) -> Bool {
        guard credentialStore.deleteCustomModelAPIKey(forModelId: id) else {
            logger.error("Failed to delete API key for custom model; preserving model metadata")
            return false
        }

        customModels.removeAll { $0.id == id }
        saveCustomModels()

        do {
            // Best-effort removal of the obsolete pre-APIKeyManager account.
            try KeychainManager.shared.deleteAPIKey(for: "custom_model_\(id.uuidString)")
        } catch {
            logger.warning("Failed to remove legacy custom-model credential: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
        return true
    }

    @discardableResult
    func updateCustomModel(_ updatedModel: CustomCloudModel) -> Bool {
        if let index = customModels.firstIndex(where: { $0.id == updatedModel.id }) {
            // Update API key in Keychain if it was changed (present in transient)
            if let newKey = updatedModel.transientApiKey, !newKey.isEmpty {
                guard credentialStore.saveCustomModelAPIKey(newKey, forModelId: updatedModel.id) else {
                    logger.error("Failed to save updated API key for custom model")
                    return false
                }
            }
            
            var sanitizedModel = updatedModel
            sanitizedModel.transientApiKey = nil
            customModels[index] = sanitizedModel
            saveCustomModels()
            return true
        }
        return false
    }

    func replaceCustomModels(_ models: [CustomCloudModel]) -> CustomModelReplacementResult {
        let incomingIDs = Set(models.map(\.id))
        guard incomingIDs.count == models.count else {
            logger.error("Refusing custom-model replacement with duplicate identifiers")
            return .failed
        }
        let removedIDs = Set(customModels.map(\.id)).subtracting(incomingIDs)
        let changedIDs = Set(models.compactMap { model in
            model.transientApiKey?.isEmpty == false ? model.id : nil
        })
        let affectedIDs = changedIDs.union(removedIDs)
        var credentialSnapshots: [UUID: KeychainReadResult] = [:]
        for id in affectedIDs {
            let snapshot = credentialStore.readCustomModelAPIKey(forModelId: id)
            guard snapshot != .failed else {
                logger.error("Unable to snapshot custom-model credential; replacement aborted")
                return .failed
            }
            credentialSnapshots[id] = snapshot
        }
        var touchedIDs: [UUID] = []

        for model in models {
            guard let key = model.transientApiKey, !key.isEmpty else { continue }
            touchedIDs.append(model.id)
            guard credentialStore.saveCustomModelAPIKey(key, forModelId: model.id) else {
                return handleReplacementFailure(models, snapshots: credentialSnapshots, touchedIDs: touchedIDs)
            }
        }

        for id in removedIDs {
            touchedIDs.append(id)
            guard credentialStore.deleteCustomModelAPIKey(forModelId: id) else {
                return handleReplacementFailure(models, snapshots: credentialSnapshots, touchedIDs: touchedIDs)
            }
        }

        customModels = sanitized(models)
        saveCustomModels()
        return .success
    }

    private func handleReplacementFailure(
        _ incomingModels: [CustomCloudModel],
        snapshots: [UUID: KeychainReadResult],
        touchedIDs: [UUID]
    ) -> CustomModelReplacementResult {
        var rollbackSucceeded = true
        for id in touchedIDs.reversed() {
            let restored: Bool
            switch snapshots[id] {
            case .present(let previous):
                restored = credentialStore.saveCustomModelAPIKey(previous, forModelId: id)
            case .absent:
                restored = credentialStore.deleteCustomModelAPIKey(forModelId: id)
            case .failed, .none:
                restored = false
            }
            rollbackSucceeded = restored && rollbackSucceeded
        }
        guard !rollbackSucceeded else { return .failed }

        logger.fault("Custom-model credential rollback failed; preserving metadata for retry")
        var modelsByID: [UUID: CustomCloudModel] = [:]
        for model in customModels { modelsByID[model.id] = model }
        for model in sanitized(incomingModels) { modelsByID[model.id] = model }
        customModels = Array(modelsByID.values)
        saveCustomModels()
        return .partialFailure
    }

    private func sanitized(_ models: [CustomCloudModel]) -> [CustomCloudModel] {
        models.map { model in
            var sanitized = model
            sanitized.transientApiKey = nil
            return sanitized
        }
    }
    
    // MARK: - Persistence
    
    private func loadCustomModels() {
        guard let data = dataStore.data(forKey: customModelsKey) else {
            logger.info("No custom models found in UserDefaults")
            return
        }
        
        // Attempt migration from legacy format (with apiKey in JSON)
        if let legacyModels = try? JSONDecoder().decode([LegacyCustomCloudModel].self, from: data) {
            logger.info("Found legacy custom models. Migrating keys to Keychain...")
            
            var migratedModels: [CustomCloudModel] = []
            var migrationSucceeded = true
            
            for legacy in legacyModels {
                if !credentialStore.saveCustomModelAPIKey(legacy.apiKey, forModelId: legacy.id) {
                    migrationSucceeded = false
                    logger.error("Failed to migrate custom model API key; legacy data will be preserved")
                }
                
                // Create new model (apiKey property will now read from Keychain)
                let newModel = CustomCloudModel(
                    id: legacy.id,
                    name: legacy.name,
                    displayName: legacy.displayName,
                    description: legacy.description,
                    apiEndpoint: legacy.apiEndpoint,
                    modelName: legacy.modelName,
                    isMultilingual: legacy.isMultilingualModel,
                    supportedLanguages: legacy.supportedLanguages
                )
                migratedModels.append(newModel)
            }
            
            guard migrationSucceeded else { return }
            self.customModels = migratedModels
            saveCustomModels() // Save in new format
            logger.info("Migration complete. \(migratedModels.count) models migrated.")
            return
        }
        
        // Standard load
        do {
            customModels = try JSONDecoder().decode([CustomCloudModel].self, from: data)
        } catch {
            logger.error("Failed to decode custom models: \(AppLogger.errorMetadata(error), privacy: .public)")
            customModels = []
        }
    }
    
    func saveCustomModels() {
        guard persistsChanges else { return }
        do {
            let data = try JSONEncoder().encode(customModels)
            dataStore.set(data, forKey: customModelsKey)
        } catch {
            logger.error("Failed to encode custom models: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }
    
    // MARK: - Validation
    
    func validateModel(name: String, displayName: String, apiEndpoint: String, apiKey: String, modelName: String) -> [String] {
        var errors: [String] = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }
        
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name cannot be empty")
        }
        
        if apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API endpoint cannot be empty")
        } else if !isValidURL(apiEndpoint) {
            errors.append("API endpoint must be a valid URL")
        }
        
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API key cannot be empty")
        }
        
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model name cannot be empty")
        }
        
        // Check for duplicate names
        if customModels.contains(where: { $0.name == name }) {
            errors.append("A model with this name already exists")
        }
        
        return errors
    }
    
    func validateModel(name: String, displayName: String, apiEndpoint: String, apiKey: String, modelName: String, excludingId: UUID? = nil) -> [String] {
        var errors: [String] = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }
        
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name cannot be empty")
        }
        
        if apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API endpoint cannot be empty")
        } else if !isValidURL(apiEndpoint) {
            errors.append("API endpoint must be a valid URL")
        }
        
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API key cannot be empty")
        }
        
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model name cannot be empty")
        }
        
        // Check for duplicate names, excluding the specified ID
        if customModels.contains(where: { $0.name == name && $0.id != excludingId }) {
            errors.append("A model with this name already exists")
        }
        
        return errors
    }
    
    private func isValidURL(_ string: String) -> Bool {
        // CRITICAL: Enforce HTTPS for URLs that carry API credentials.
        CustomCloudModel.isValidSecureEndpoint(string)
    }
}

// Legacy struct for migration
private struct LegacyCustomCloudModel: Codable {
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
} 
