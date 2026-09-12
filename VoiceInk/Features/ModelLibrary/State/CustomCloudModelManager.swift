import Foundation
import os

@MainActor
class CustomCloudModelManager: ObservableObject {
    static let shared = CustomCloudModelManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomCloudModelManager")
    private let userDefaults = UserDefaults.standard
    private let customModelsKey = "customCloudModels"

    @Published var customModels: [CustomCloudModel] = []

    private init() {
        loadCustomModels()
    }

    // MARK: - CRUD Operations

    private func addCustomModel(_ model: CustomCloudModel) {
        customModels.append(model)
        saveCustomModels()
    }

    @discardableResult
    func addCustomModel(_ model: CustomCloudModel, apiKey: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
            APIKeyManager.shared.saveCustomModelAPIKey(trimmedKey, forModelId: model.id)
        else {
            return false
        }

        addCustomModel(model)
        return true
    }

    func removeCustomModel(withId id: UUID) {
        customModels.removeAll { $0.id == id }
        saveCustomModels()
        APIKeyManager.shared.deleteCustomModelAPIKey(forModelId: id)
    }

    @discardableResult
    func updateCustomModel(_ updatedModel: CustomCloudModel, apiKey: String? = nil) -> Bool {
        if let apiKey {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                APIKeyManager.shared.saveCustomModelAPIKey(trimmedKey, forModelId: updatedModel.id)
            else {
                return false
            }
        }

        if let index = customModels.firstIndex(where: { $0.id == updatedModel.id }) {
            customModels[index] = updatedModel
            saveCustomModels()
        }
        return true
    }

    // MARK: - Persistence

    private func loadCustomModels() {
        guard let data = userDefaults.data(forKey: customModelsKey) else {
            return
        }

        do {
            customModels = try JSONDecoder().decode([CustomCloudModel].self, from: data)
        } catch {
            logger.error("Failed to decode custom models: \(AppLogger.errorMetadata(error), privacy: .public)")
            customModels = []
        }
    }

    func saveCustomModels() {
        do {
            let data = try JSONEncoder().encode(customModels)
            userDefaults.set(data, forKey: customModelsKey)
        } catch {
            logger.error("Failed to encode custom models: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }

    // MARK: - Validation

    func validateModelDetails(
        name: String, displayName: String, apiEndpoint: String, modelName: String, excludingId: UUID? = nil
    ) -> [String] {
        var errors: [String] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(String(localized: "Name cannot be empty"))
        }

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(String(localized: "Display name cannot be empty"))
        }

        if apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(String(localized: "API endpoint cannot be empty"))
        } else if !SecureEndpointValidator.isAllowed(apiEndpoint) {
            errors.append(
                String(localized: "API endpoint must use HTTPS (plain HTTP is allowed only for localhost)"))
        }

        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(String(localized: "Model name cannot be empty"))
        }

        if customModels.contains(where: { $0.name == name && $0.id != excludingId }) {
            errors.append(String(localized: "A model with this name already exists"))
        }

        return errors
    }

}
