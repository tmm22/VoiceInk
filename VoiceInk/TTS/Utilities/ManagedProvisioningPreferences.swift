import Foundation

@MainActor
final class ManagedProvisioningPreferences {
    static let shared = ManagedProvisioningPreferences()

    private enum Keys {
        static let baseURL = "managedProvisioning.baseURL"
        static let accountId = "managedProvisioning.accountId"
        static let planTier = "managedProvisioning.planTier"
        static let planStatus = "managedProvisioning.planStatus"
        static let isEnabled = "managedProvisioning.enabled"
    }

    var currentConfiguration: ManagedProvisioningClient.Configuration? {
        get {
            guard let urlString = AppSettings.string(forKey: Keys.baseURL),
                  let url = URL(string: urlString),
                  // SECURITY: Enforce HTTPS for URLs that carry credentials
                  url.scheme?.lowercased() == "https",
                  let accountId = AppSettings.string(forKey: Keys.accountId),
                  let planTier = AppSettings.string(forKey: Keys.planTier),
                  let planStatus = AppSettings.string(forKey: Keys.planStatus) else {
                return nil
            }
            return .init(baseURL: url, accountId: accountId, planTier: planTier, planStatus: planStatus)
        }
        set {
            if let newValue {
                // SECURITY: Only allow HTTPS URLs for managed provisioning
                guard newValue.baseURL.scheme?.lowercased() == "https" else {
                    #if DEBUG
                    print("ManagedProvisioningPreferences: Rejecting non-HTTPS URL")
                    #endif
                    return
                }
                AppSettings.setValue(newValue.baseURL.absoluteString, forKey: Keys.baseURL)
                AppSettings.setValue(newValue.accountId, forKey: Keys.accountId)
                AppSettings.setValue(newValue.planTier, forKey: Keys.planTier)
                AppSettings.setValue(newValue.planStatus, forKey: Keys.planStatus)
            } else {
                AppSettings.removeValue(forKey: Keys.baseURL)
                AppSettings.removeValue(forKey: Keys.accountId)
                AppSettings.removeValue(forKey: Keys.planTier)
                AppSettings.removeValue(forKey: Keys.planStatus)
            }
        }
    }

    var isEnabled: Bool {
        get { AppSettings.bool(forKey: Keys.isEnabled, default: false) }
        set { AppSettings.setValue(newValue, forKey: Keys.isEnabled) }
    }

    func clear() {
        currentConfiguration = nil
        isEnabled = false
    }
}

extension ManagedProvisioningPreferences: @unchecked Sendable {}
