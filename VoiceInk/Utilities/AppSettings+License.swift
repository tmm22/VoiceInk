import Foundation

extension AppSettings {
    // MARK: - License Keys
    enum LicenseKeys {
        static let licenseKey = "VoiceInkLicense"
        static let trialStartDate = "VoiceInkTrialStartDate"
    }

    // MARK: - License Management
    
    /// The user's license key.
    static var licenseKey: String? {
        get { string(forKey: LicenseKeys.licenseKey) }
        set { updateString(newValue, forKey: LicenseKeys.licenseKey) }
    }
    
    /// The start date of the trial period.
    /// This value is obfuscated to prevent easy tampering.
    static var trialStartDate: Date? {
        get {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(LicenseKeys.trialStartDate, salt: salt)
            
            guard let obfuscatedValue = string(forKey: obfuscatedKey),
                  let decodedValue = Obfuscator.decode(obfuscatedValue, salt: salt),
                  let timestamp = Double(decodedValue) else {
                return nil
            }
            
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(LicenseKeys.trialStartDate, salt: salt)
            
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                let obfuscatedValue = Obfuscator.encode(timestamp, salt: salt)
                setValue(obfuscatedValue, forKey: obfuscatedKey)
            } else {
                removeValue(forKey: obfuscatedKey)
            }
        }
    }
}
