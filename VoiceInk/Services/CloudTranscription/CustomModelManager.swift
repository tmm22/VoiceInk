import Foundation
import os

class CustomModelManager: ObservableObject {
    static let shared = CustomModelManager()
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "CustomModelManager")
    private let userDefaults = UserDefaults.standard
    private let customModelsKey = "customCloudModels"
    
    @Published var customModels: [CustomCloudModel] = []
    
    private init() {
        loadCustomModels()
    }
    
    // MARK: - CRUD Operations
    
    func addCustomModel(_ model: CustomCloudModel) {
        // Save API key to Keychain if present in transient property
        if let apiKey = model.transientApiKey, !apiKey.isEmpty {
            KeychainManager.shared.saveAPIKey(apiKey, for: "custom_model_\(model.id.uuidString)")
        }
        
        customModels.append(model)
        saveCustomModels()
        logger.info("Added custom model: \(model.displayName)")
    }
    
    func removeCustomModel(withId id: UUID) {
        customModels.removeAll { $0.id == id }
        
        // Remove API key from Keychain
        try? KeychainManager.shared.deleteAPIKey(for: "custom_model_\(id.uuidString)")
        
        saveCustomModels()
        logger.info("Removed custom model with ID: \(id)")
    }
    
    func updateCustomModel(_ updatedModel: CustomCloudModel) {
        if let index = customModels.firstIndex(where: { $0.id == updatedModel.id }) {
            // Update API key in Keychain if it was changed (present in transient)
            if let newKey = updatedModel.transientApiKey, !newKey.isEmpty {
                KeychainManager.shared.saveAPIKey(newKey, for: "custom_model_\(updatedModel.id.uuidString)")
            }
            
            customModels[index] = updatedModel
            saveCustomModels()
            logger.info("Updated custom model: \(updatedModel.displayName)")
        }
    }
    
    // MARK: - Persistence
    
    private func loadCustomModels() {
        guard let data = userDefaults.data(forKey: customModelsKey) else {
            logger.info("No custom models found in UserDefaults")
            return
        }
        
        // Attempt migration from legacy format (with apiKey in JSON)
        if let legacyModels = try? JSONDecoder().decode([LegacyCustomCloudModel].self, from: data) {
            logger.info("Found legacy custom models. Migrating keys to Keychain...")
            
            var migratedModels: [CustomCloudModel] = []
            
            for legacy in legacyModels {
                // Save key to Keychain
                KeychainManager.shared.saveAPIKey(legacy.apiKey, for: "custom_model_\(legacy.id.uuidString)")
                
                // Create new model (apiKey property will now read from Keychain)
                let newModel = CustomCloudModel(
                    id: legacy.id,
                    name: legacy.name,
                    displayName: legacy.displayName,
                    description: legacy.description,
                    apiEndpoint: legacy.apiEndpoint,
                    apiKey: "", // Not needed here as we just saved it to keychain, and transient is not needed for load
                    modelName: legacy.modelName,
                    isMultilingual: legacy.isMultilingualModel,
                    supportedLanguages: legacy.supportedLanguages
                )
                migratedModels.append(newModel)
            }
            
            self.customModels = migratedModels
            saveCustomModels() // Save in new format
            logger.info("Migration complete. \(migratedModels.count) models migrated.")
            return
        }
        
        // Standard load
        do {
            customModels = try JSONDecoder().decode([CustomCloudModel].self, from: data)
        } catch {
            logger.error("Failed to decode custom models: \(error.localizedDescription)")
            customModels = []
        }
    }
    
    func saveCustomModels() {
        do {
            let data = try JSONEncoder().encode(customModels)
            userDefaults.set(data, forKey: customModelsKey)
        } catch {
            logger.error("Failed to encode custom models: \(error.localizedDescription)")
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
        if let url = URL(string: string) {
            return url.scheme != nil && url.host != nil
        }
        return false
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
