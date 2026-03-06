import Foundation
import Security
import os

/// Securely stores and retrieves secrets using Keychain.
/// Local builds still use Keychain, but disable syncable items because
/// local entitlements omit the production iCloud/keychain configuration.
final class KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")
    private let service = "com.prakashjoshipax.VoiceInk"

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String, syncable: Bool = true) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable)
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(data: Data, forKey key: String, syncable: Bool = true) -> Bool {
        let effectiveSyncable = resolvedSyncable(syncable)

        // First, try to delete any existing item to avoid duplicates
        delete(forKey: key, syncable: effectiveSyncable)

        var query = baseQuery(forKey: key, syncable: effectiveSyncable)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.info("Successfully saved keychain item for key: \(key, privacy: .public)")
            return true
        } else {
            logger.error("Failed to save keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
            return false
        }
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        let effectiveSyncable = resolvedSyncable(syncable)

        var query = baseQuery(forKey: key, syncable: effectiveSyncable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            logger.error("Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
        }

        return nil
    }

    /// Deletes an item from Keychain.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        let effectiveSyncable = resolvedSyncable(syncable)
        let query = baseQuery(forKey: key, syncable: effectiveSyncable)
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            if status == errSecSuccess {
                logger.info("Successfully deleted keychain item for key: \(key, privacy: .public)")
            }
            return true
        } else {
            logger.error("Failed to delete keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
            return false
        }
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        let effectiveSyncable = resolvedSyncable(syncable)

        var query = baseQuery(forKey: key, syncable: effectiveSyncable)
        query[kSecReturnData as String] = kCFBooleanFalse

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Private Helpers

    private func resolvedSyncable(_ requestedSyncable: Bool) -> Bool {
        #if LOCAL_BUILD
        return false
        #else
        return requestedSyncable
        #endif
    }

    /// Creates base Keychain query dictionary.
    private func baseQuery(forKey key: String, syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]

        if syncable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        return query
    }
}
