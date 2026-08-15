import UserNotifications

extension TTSSettingsViewModel {
    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }

        guard let notificationCenter else {
            notificationsEnabled = false
            saveSettings()
            return
        }

        if enabled {
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.notificationsEnabled = granted
                    self.saveSettings()
                }
            }
        } else {
            notificationsEnabled = false
            saveSettings()
        }
    }
}
