import Foundation
import os

/// Service responsible for syncing data to iCloud using NSUbiquitousKeyValueStore
@MainActor
class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()
    
    private let store = NSUbiquitousKeyValueStore.default
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "CloudSyncService")
    
    // Keys for data storage
    private let customPromptsKey = "cloud_sync_custom_prompts"
    
    // Callback for when external changes are detected
    var onPromptsChanged: (([CustomPrompt]) -> Void)?
    
    private init() {
        // Register for external change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChangeExternally),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        
        // Initial sync to get latest data
        store.synchronize()
        logger.info("CloudSyncService initialized")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Syncs the provided custom prompts to iCloud
    /// - Parameter prompts: The list of prompts to sync
    func syncPrompts(_ prompts: [CustomPrompt]) {
        do {
            let encoded = try JSONEncoder().encode(prompts)
            store.set(encoded, forKey: customPromptsKey)
            store.synchronize()
            logger.info("Successfully synced \(prompts.count) prompts to iCloud")
        } catch {
            logger.error("Failed to encode prompts for iCloud sync: \(error.localizedDescription)")
        }
    }
    
    /// Fetches the current prompts from iCloud
    /// - Returns: Array of CustomPrompt or nil if not found/error
    func fetchPrompts() -> [CustomPrompt]? {
        guard let data = store.data(forKey: customPromptsKey) else {
            return nil
        }
        
        do {
            let prompts = try JSONDecoder().decode([CustomPrompt].self, from: data)
            return prompts
        } catch {
            logger.error("Failed to decode prompts from iCloud: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    @objc private func storeDidChangeExternally(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        // We only care about server changes or initial sync
        guard reasonForChange == NSUbiquitousKeyValueStoreServerChange ||
              reasonForChange == NSUbiquitousKeyValueStoreInitialSyncChange else {
            return
        }
        
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }
        
        if changedKeys.contains(customPromptsKey) {
            logger.info("Detected external change for custom prompts")
            if let newPrompts = fetchPrompts() {
                // Already on MainActor
                onPromptsChanged?(newPrompts)
            }
        }
    }
}
