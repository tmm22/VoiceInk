import Foundation

extension UserDefaults {
    enum Keys {
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let selectedAudioDeviceModelUID = "selectedAudioDeviceModelUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let audioInputChannelsByDeviceUID = "audioInputChannelsByDeviceUID"
        static let affiliatePromotionDismissed = "VoiceInkAffiliatePromotionDismissed"
    }

    var audioInputModeRawValue: String? {
        get { string(forKey: Keys.audioInputMode) }
        set { setValue(newValue, forKey: Keys.audioInputMode) }
    }

    var selectedAudioDeviceUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceUID) }
    }

    var selectedAudioDeviceModelUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceModelUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceModelUID) }
    }

    var prioritizedDevicesData: Data? {
        get { data(forKey: Keys.prioritizedDevices) }
        set { setValue(newValue, forKey: Keys.prioritizedDevices) }
    }

    /// Exact device UIDs keep channel choices separate, even for identical interface models.
    var audioInputChannelsByDeviceUID: [String: [UInt32]] {
        get {
            guard let data = data(forKey: Keys.audioInputChannelsByDeviceUID),
                  let selections = try? JSONDecoder().decode([String: [UInt32]].self, from: data) else {
                return [:]
            }
            // Older multiple-input overrides return to Automatic instead of choosing an arbitrary input.
            return selections.filter { $0.value.count == 1 }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: Keys.audioInputChannelsByDeviceUID)
        }
    }

    var affiliatePromotionDismissed: Bool {
        get { bool(forKey: Keys.affiliatePromotionDismissed) }
        set { setValue(newValue, forKey: Keys.affiliatePromotionDismissed) }
    }
}
