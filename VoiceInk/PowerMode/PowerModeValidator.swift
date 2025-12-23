import Foundation
import SwiftUI

enum PowerModeValidationError: Error, Identifiable {
    case emptyName
    case duplicateName(String)
    case duplicateAppTrigger(String, String) // (app name, existing power mode name)
    case duplicateWebsiteTrigger(String, String) // (website, existing power mode name)
    
    var id: String {
        switch self {
        case .emptyName: return "emptyName"
        case .duplicateName: return "duplicateName"
        case .duplicateAppTrigger: return "duplicateAppTrigger"
        case .duplicateWebsiteTrigger: return "duplicateWebsiteTrigger"
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .emptyName:
            return Localization.PowerMode.validationEmptyName
        case .duplicateName(let name):
            return String(format: Localization.PowerMode.validationDuplicateName, name)
        case .duplicateAppTrigger(let appName, let powerModeName):
            return String(format: Localization.PowerMode.validationDuplicateAppTrigger, appName, powerModeName)
        case .duplicateWebsiteTrigger(let website, let powerModeName):
            return String(format: Localization.PowerMode.validationDuplicateWebsiteTrigger, website, powerModeName)
        }
    }
}

@MainActor
struct PowerModeValidator {
    private let powerModeManager: PowerModeManager
    
    init(powerModeManager: PowerModeManager) {
        self.powerModeManager = powerModeManager
    }
    
    func validateForSave(config: PowerModeConfig, mode: ConfigurationMode) -> [PowerModeValidationError] {
        var errors: [PowerModeValidationError] = []
        
        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }
        
        let isDuplicateName = powerModeManager.configurations.contains { existingConfig in
            if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                return false
            }
            return existingConfig.name == config.name
        }
        
        if isDuplicateName {
            errors.append(.duplicateName(config.name))
        }
        

        
        if let appConfigs = config.appConfigs {
            for appConfig in appConfigs {
                for existingConfig in powerModeManager.configurations {
                    if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                        continue
                    }
                    
                    if let existingAppConfigs = existingConfig.appConfigs,
                       existingAppConfigs.contains(where: { $0.bundleIdentifier == appConfig.bundleIdentifier }) {
                        errors.append(.duplicateAppTrigger(appConfig.appName, existingConfig.name))
                    }
                }
            }
        }
        
        if let urlConfigs = config.urlConfigs {
            for urlConfig in urlConfigs {
                for existingConfig in powerModeManager.configurations {
                    if case .edit(let editConfig) = mode, existingConfig.id == editConfig.id {
                        continue
                    }
                    
                    if let existingUrlConfigs = existingConfig.urlConfigs,
                       existingUrlConfigs.contains(where: { $0.url == urlConfig.url }) {
                        errors.append(.duplicateWebsiteTrigger(urlConfig.url, existingConfig.name))
                    }
                }
            }
        }
        
        return errors
    }
}

extension View {
    func powerModeValidationAlert(
        errors: [PowerModeValidationError],
        isPresented: Binding<Bool>
    ) -> some View {
        self.alert(
            Localization.PowerMode.cannotSaveTitle,
            isPresented: isPresented,
            actions: {
                Button(Localization.PowerMode.okButton, role: .cancel) {}
            },
            message: {
                if let firstError = errors.first {
                    Text(firstError.localizedDescription)
                } else {
                    Text(Localization.PowerMode.validationErrorsMessage)
                }
            }
        )
    }
} 
