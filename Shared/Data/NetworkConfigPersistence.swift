//
//  NetworkConfigPersistence.swift
//  Arke
//
//  Utility for persisting and loading network configuration across app sessions
//  Ensures the wallet uses the correct network (mainnet, signet, etc.) after restart
//
//  Created by Claude on 4/30/26.
//

import Foundation
import OSLog

/// Manages persistence of network configuration to iCloud Key-Value Store and UserDefaults
/// UserDefaults is the source of truth on the launch path (fast, local, always available).
/// iCloud KV Store is used as a background sync layer for cross-device sync and reinstall
/// persistence — it is never touched synchronously during app launch, because the first
/// access to NSUbiquitousKeyValueStore.default can block on I/O and trip the launch watchdog.
class NetworkConfigPersistence {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "NetworkConfigPersistence")
    private nonisolated static let iCloudKey = "com.arke.wallet.networkConfigId"

    /// Notification posted when a background iCloud sync updates the locally cached config.
    /// Observers (e.g. WalletManager) can re-read the config in response.
    static let networkConfigDidSyncFromiCloud = Notification.Name("NetworkConfigPersistence.didSyncFromiCloud")

    /// Save the network configuration ID to UserDefaults (synchronous) and iCloud (background)
    /// - Parameter networkConfig: The network configuration to persist
    static func save(_ networkConfig: NetworkConfig) {
        // Save to UserDefaults synchronously (fast local cache, source of truth at launch)
        UserDefaults.standard.set(networkConfig.id, forKey: UserDefaults.networkConfigKey)

        // Mirror to iCloud off the main thread (survives reinstalls and syncs across devices).
        // First access to the ubiquitous store can block, so never do it synchronously here.
        let id = networkConfig.id
        Task.detached(priority: .utility) {
            NSUbiquitousKeyValueStore.default.set(id, forKey: iCloudKey)
        }

        logger.info("Network configuration saved: \(networkConfig.name) (ID: \(networkConfig.id))")
    }

    /// Load the saved network configuration from the local UserDefaults cache.
    /// This is synchronous and safe to call during app launch — it never touches iCloud.
    /// Cross-device / reinstall recovery is handled separately by `syncFromiCloud()`.
    /// - Returns: The saved NetworkConfig, or mainnet as default
    static func load() -> NetworkConfig {
        if let localId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey) {
            logger.debug("Found network config in UserDefaults: \(localId)")
            if let config = findConfig(byId: localId) {
                logger.info("Loaded network configuration from UserDefaults: \(config.name)")
                return config
            }
        }

        // Default to mainnet (not signet)
        logger.info("No saved config found, using default: \(NetworkConfig.mainnet.name)")
        return .mainnet
    }

    /// Reconcile the local cache with iCloud in the background.
    /// Call this AFTER launch (e.g. from the main view's `.task`), never on the launch path.
    /// If iCloud holds a valid config id that differs from the local cache, the cache is
    /// updated and `networkConfigDidSyncFromiCloud` is posted so observers can re-read.
    static func syncFromiCloud() async {
        // Access the ubiquitous store off the main thread — first touch may block on I/O.
        let iCloudId = await Task.detached(priority: .utility) { () -> String? in
            NSUbiquitousKeyValueStore.default.string(forKey: iCloudKey)
        }.value

        guard let iCloudId else {
            // Nothing in iCloud yet. If we have a local value, push it up for other devices.
            if let localId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey) {
                Task.detached(priority: .utility) {
                    NSUbiquitousKeyValueStore.default.set(localId, forKey: iCloudKey)
                }
            }
            return
        }

        // Ignore unknown ids (e.g. a custom network not yet supported here).
        guard findConfig(byId: iCloudId) != nil else {
            logger.warning("iCloud network config id '\(iCloudId)' not recognized, ignoring")
            return
        }

        let localId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey)
        guard iCloudId != localId else { return }

        // iCloud differs from local cache — update cache and notify observers.
        UserDefaults.standard.set(iCloudId, forKey: UserDefaults.networkConfigKey)
        logger.info("Synced network configuration from iCloud: \(iCloudId) (was \(localId ?? "none"))")
        await MainActor.run {
            NotificationCenter.default.post(name: networkConfigDidSyncFromiCloud, object: nil)
        }
    }
    
    /// Find a network configuration by ID
    /// - Parameter id: The network configuration ID
    /// - Returns: The matching NetworkConfig, or nil if not found
    private static func findConfig(byId id: String) -> NetworkConfig? {
        let predefinedNetworks: [NetworkConfig] = [.mainnet, .signet, .testnet]
        if let matched = predefinedNetworks.first(where: { $0.id == id }) {
            return matched
        }
        
        // If not found in predefined networks, it might be a custom network
        // For now, we'll log a warning and return nil
        // In the future, you could persist custom network details fully
        logger.warning("Network ID '\(id)' not found in predefined networks")
        return nil
    }
    
    /// Clear the saved network configuration from both UserDefaults and iCloud
    /// Should be called when deleting the wallet
    static func clear() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)

        // Remove from iCloud off the main thread (first access can block).
        Task.detached(priority: .utility) {
            NSUbiquitousKeyValueStore.default.removeObject(forKey: iCloudKey)
        }

        logger.info("Network configuration cleared from storage")
    }

    /// Check if a network configuration has been saved locally.
    /// Checks the UserDefaults cache only — safe to call synchronously, never touches iCloud.
    /// - Returns: True if a network config is saved, false otherwise
    static func hasSavedConfig() -> Bool {
        return UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey) != nil
    }
}
