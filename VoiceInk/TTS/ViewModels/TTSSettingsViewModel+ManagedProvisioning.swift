import Foundation

extension TTSSettingsViewModel {
    func updateManagedProvisioningConfiguration(baseURL: String, accountId: String, planTier: String, planStatus: String, enabled: Bool) {
        guard let url = URL(string: baseURL) else {
            managedProvisioningError = "Invalid provisioning URL"
            return
        }

        let configuration = ManagedProvisioningClient.Configuration(
            baseURL: url,
            accountId: accountId,
            planTier: planTier.lowercased(),
            planStatus: planStatus.lowercased()
        )
        managedProvisioningClient.configuration = configuration
        managedProvisioningClient.isEnabled = enabled
        managedProvisioningClient.invalidateAllCredentials()
        managedProvisioningConfiguration = configuration
        managedProvisioningEnabled = enabled
        managedProvisioningError = nil

        scheduleManagedProvisioningRefresh(silently: true)
    }

    func clearManagedProvisioning() {
        managedProvisioningTask?.cancel()
        managedProvisioningTask = nil
        managedProvisioningClient.reset()
        managedProvisioningConfiguration = nil
        managedProvisioningEnabled = false
        managedAccountSnapshot = nil
        managedProvisioningError = nil
    }

    func scheduleManagedProvisioningRefresh(silently: Bool) {
        managedProvisioningTask?.cancel()
        managedProvisioningTask = Task { [weak self] in
            await self?.refreshManagedAccountSnapshot(silently: silently)
        }
    }

    func refreshManagedAccountSnapshot(silently: Bool = false) async {
        guard managedProvisioningClient.isEnabled, managedProvisioningClient.configuration != nil else {
            managedAccountSnapshot = nil
            if !silently {
                managedProvisioningError = "Managed provisioning is disabled."
            }
            return
        }

        do {
            let snapshot = try await managedProvisioningClient.fetchAccountSnapshot()
            managedAccountSnapshot = snapshot
            managedProvisioningError = nil
        } catch {
            if !silently {
                managedProvisioningError = error.localizedDescription
            }
        }
    }
}
