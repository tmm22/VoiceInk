import Foundation
import Security
import os

/// The single Keychain engine for the app.
///
/// Every secret lives in a `Namespace` that fixes the `kSecAttrService` string and the keychain
/// flavour (Data Protection vs. login keychain). Namespaces are deliberately frozen so items written
/// by earlier releases keep resolving:
/// - `.credentials` — production credentials (`APIKeyManager`, `LicenseManager`).
/// - `.loginKeychain(service:)` — the TTS workspace's legacy per-provider keys (`KeychainManager`).
final class KeychainService {
    static let shared = KeychainService(namespace: .credentials)

    /// Describes where a set of secrets is stored. Do not change the `service` strings of existing
    /// namespaces; users would lose access to already-stored keys.
    struct Namespace {
        /// Value written to `kSecAttrService`.
        let service: String
        /// Use the Data Protection keychain (`kSecUseDataProtectionKeychain`) and honour `syncable`.
        /// The login keychain is used when false.
        let usesDataProtectionKeychain: Bool
        /// Whether `kSecAttrAccessible` is written alongside saved items.
        let appliesAccessibility: Bool
        /// Optional `kSecAttrAccessGroup`.
        let accessGroup: String?

        /// Production credentials. Local builds are ad-hoc signed and cannot use the Data Protection
        /// Keychain, so they get a separate, non-syncing login-Keychain namespace. Credentials never
        /// fall back to UserDefaults.
        static let credentials: Namespace = {
            #if LOCAL_BUILD
                return Namespace(
                    service: "com.prakashjoshipax.VoiceInk.Local",
                    usesDataProtectionKeychain: false,
                    appliesAccessibility: false,
                    accessGroup: nil
                )
            #else
                return Namespace(
                    service: "com.prakashjoshipax.VoiceInk",
                    usesDataProtectionKeychain: true,
                    appliesAccessibility: true,
                    accessGroup: nil
                )
            #endif
        }()

        /// Plain login-keychain namespace keyed by an arbitrary service string.
        static func loginKeychain(service: String, accessGroup: String? = nil) -> Namespace {
            Namespace(
                service: service,
                usesDataProtectionKeychain: false,
                appliesAccessibility: true,
                accessGroup: accessGroup
            )
        }
    }

    enum Accessibility {
        case afterFirstUnlockThisDeviceOnly
        case whenUnlocked

        fileprivate var value: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenUnlocked:
                return kSecAttrAccessibleWhenUnlocked
            }
        }
    }

    enum ReadResult<Value> {
        case value(Value)
        case notFound
        case unavailable(OSStatus)
    }

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "KeychainService")
    let namespace: Namespace

    init(namespace: Namespace) {
        self.namespace = namespace
    }

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(
        _ value: String,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable, accessibility: accessibility)
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(
        data: Data,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        store(data: data, forKey: key, syncable: syncable, accessibility: accessibility) == errSecSuccess
    }

    /// Saves data to Keychain (update-then-add) and returns the final Security framework status.
    @discardableResult
    func store(
        data: Data,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> OSStatus {
        let query = baseQuery(forKey: key, syncable: syncable)
        var attributes: [String: Any] = [kSecValueData as String: data]
        applyAccessibility(accessibility, to: &attributes)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            logger.info("Successfully updated keychain item for key: \(key, privacy: .public)")
            return updateStatus
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error(
                "Failed to update keychain item for key: \(key, privacy: .public), status: \(updateStatus, privacy: .public)"
            )
            return updateStatus
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        applyAccessibility(accessibility, to: &addQuery)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            logger.info("Successfully saved keychain item for key: \(key, privacy: .public)")
            return addStatus
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if retryStatus == errSecSuccess {
                logger.info("Successfully updated concurrently created keychain item for key: \(key, privacy: .public)")
                return retryStatus
            }

            logger.error(
                "Failed to update concurrently created keychain item for key: \(key, privacy: .public), status: \(retryStatus, privacy: .public)"
            )
            return retryStatus
        }

        logger.error(
            "Failed to save keychain item for key: \(key, privacy: .public), status: \(addStatus, privacy: .public)"
        )
        return addStatus
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves a string while distinguishing missing data from unavailable storage.
    func readString(forKey key: String, syncable: Bool = true) -> ReadResult<String> {
        switch readData(forKey: key, syncable: syncable) {
        case .value(let data):
            guard let value = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode keychain string for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(value)
        case .notFound:
            return .notFound
        case .unavailable(let status):
            return .unavailable(status)
        }
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        guard case .value(let data) = readData(forKey: key, syncable: syncable) else {
            return nil
        }
        return data
    }

    /// Retrieves data while preserving the Security framework status.
    func readData(forKey key: String, syncable: Bool = true) -> ReadResult<Data> {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            guard let data = result as? Data else {
                logger.error("Keychain returned invalid data for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(data)
        }

        if status == errSecItemNotFound {
            return .notFound
        }

        logger.error(
            "Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
        )
        return .unavailable(status)
    }

    /// Deletes an item from Keychain. Missing items count as success.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        let status = remove(forKey: key, syncable: syncable)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Deletes an item from Keychain and returns the raw Security framework status.
    @discardableResult
    func remove(forKey key: String, syncable: Bool = true) -> OSStatus {
        let query = baseQuery(forKey: key, syncable: syncable)
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            logger.info("Successfully deleted keychain item for key: \(key, privacy: .public)")
        } else if status != errSecItemNotFound {
            logger.error(
                "Failed to delete keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
            )
        }
        return status
    }

    /// Deletes every item stored under this namespace's service and returns the raw status.
    @discardableResult
    func removeAll(syncable: Bool = true) -> OSStatus {
        let query = serviceQuery(syncable: syncable)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete keychain items for service, status: \(status, privacy: .public)")
        }
        return status
    }

    /// Checks if a key exists in Keychain without reading the secret value.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanFalse
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain existence check error for key: \(key, privacy: .public), status: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// Lists every account (key) stored under this namespace's service.
    func allKeys(syncable: Bool = true) -> [String] {
        var query = serviceQuery(syncable: syncable)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = kCFBooleanTrue

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        guard status == errSecSuccess, let existingItems = items as? [[String: Any]] else {
            return []
        }

        return existingItems.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Private Helpers

    /// Creates a base Keychain query for a single account.
    private func baseQuery(forKey key: String, syncable: Bool) -> [String: Any] {
        var query = serviceQuery(syncable: syncable)
        query[kSecAttrAccount as String] = key
        return query
    }

    /// Creates a Keychain query scoped to the whole namespace (service).
    private func serviceQuery(syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace.service,
        ]

        if let accessGroup = namespace.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        if namespace.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true

            if syncable {
                query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            }
        }

        return query
    }

    private func applyAccessibility(_ accessibility: Accessibility?, to attributes: inout [String: Any]) {
        guard namespace.appliesAccessibility, let accessibility else { return }
        attributes[kSecAttrAccessible as String] = accessibility.value
    }
}
