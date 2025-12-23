import UserNotifications

extension TTSViewModel {
    var selectedProvider: TTSProviderType {
        get { settings.selectedProvider }
        set { settings.selectedProvider = newValue }
    }

    var selectedVoice: Voice? {
        get { settings.selectedVoice }
        set { settings.selectedVoice = newValue }
    }

    var selectedFormat: AudioSettings.AudioFormat {
        get { settings.selectedFormat }
        set { settings.selectedFormat = newValue }
    }

    var availableVoices: [Voice] {
        settings.availableVoices
    }

    var elevenLabsModel: ElevenLabsModel {
        get { settings.elevenLabsModel }
        set { settings.elevenLabsModel = newValue }
    }

    var notificationsEnabled: Bool {
        settings.notificationsEnabled
    }

    var notificationCenter: UNUserNotificationCenter? {
        settings.notificationCenter
    }
}
