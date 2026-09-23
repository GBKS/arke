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
    /// Observers can re-read the config in response. Nothing observes it today: the
    /// launch paths reconcile ahead of the first wallet open instead (see
    /// `reconciliation(walletNetworkId:cachedConfigId:)`), and re-pointing a wallet
    /// that is already open would invalidate its database handle.
    static let networkConfigDidSyncFromiCloud = Notification.Name("NetworkConfigPersistence.didSyncFromiCloud")

    /// What to do with a wallet's network after reconciling the cache with iCloud.
    enum Reconciliation: Equatable {
        /// The wallet already runs on the cached network - nothing to do.
        case inSync
        /// The wallet runs on a different network than the account does; re-apply
        /// this config before anything opens the wallet database.
        case reapply(NetworkConfig)
        /// No network config is available, or the cached id can't be resolved to a
        /// known network. Leave the wallet alone: a `load()`-style mainnet fallback
        /// here would re-point a correctly-running signet wallet at mainnet, which
        /// is the failure this reconciliation exists to prevent.
        case noUsableConfig
    }

    /// Decide whether a wallet's network needs re-applying, given the cached config id.
    /// Pure: resolves ids only, touches neither UserDefaults nor iCloud, so the
    /// decision is unit-testable (`NetworkConfigReconciliationTests`).
    /// - Parameters:
    ///   - walletNetworkId: `NetworkConfig.id` the wallet object currently carries.
    ///   - cachedConfigId: Raw id from the local cache, i.e. `savedConfigId()`.
    static func reconciliation(walletNetworkId: String, cachedConfigId: String?) -> Reconciliation {
        guard let cachedConfigId, let cached = findConfig(byId: cachedConfigId) else {
            return .noUsableConfig
        }
        return cached.id == walletNetworkId ? .inSync : .reapply(cached)
    }

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
    
    /// Clear only this device's local cache. For local-only wallet deletion:
    /// the iCloud copy is account-shared property of the remaining devices and
    /// must survive — removing it strands every other device on the default
    /// network and their signet/testnet dbs refuse to open (2026-08-20
    /// incident; Launch_Sequence_Contract rule 21).
    static func clearLocal() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)
        logger.info("Network configuration cleared locally (iCloud copy preserved)")
    }

    /// Clear the local cache AND the shared iCloud copy. Last-device full wipe
    /// only — owned by WalletDataCleanupService, like every other deletion of
    /// account-shared state.
    static func clearEverywhere() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)

        // Remove from iCloud off the main thread (first access can block).
        Task.detached(priority: .utility) {
            NSUbiquitousKeyValueStore.default.removeObject(forKey: iCloudKey)
        }

        logger.info("Network configuration cleared from local and iCloud storage")
    }

    /// The raw network config id in the local cache, if any.
    /// Reads the UserDefaults cache only — safe to call synchronously, never touches iCloud.
    /// Returns the id unresolved; `reconciliation(walletNetworkId:cachedConfigId:)` decides
    /// what an unknown id means.
    static func savedConfigId() -> String? {
        UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey)
    }
}
