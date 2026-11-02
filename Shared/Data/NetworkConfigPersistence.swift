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
///
/// Two keys, both in both stores:
/// - the config **id** (`networkConfigKey`), which is all builds before 2026-10-29
///   read and which resolves the two Second presets on its own;
/// - the full config as JSON (`networkConfigDataKey`), which is what a
///   `custom:*` id resolves through. Older builds ignore an id they can't
///   resolve (with a warning), so a mixed-version account degrades to "that
///   device keeps what it has", never to a wrong open.
class NetworkConfigPersistence {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "NetworkConfigPersistence")
    private nonisolated static let iCloudKey = UserDefaults.networkConfigKey
    private nonisolated static let iCloudDataKey = UserDefaults.networkConfigDataKey

    /// Notification posted when a background iCloud sync updates the locally cached config.
    /// Observers can re-read the config in response. Nothing observes it today: the
    /// launch paths reconcile ahead of the first wallet open instead (see
    /// `reconciliation(walletNetworkId:cachedConfigId:storedConfig:)`), and re-pointing
    /// a wallet that is already open would invalidate its database handle.
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
    ///   - storedConfig: The full config from the local cache, i.e. `storedConfig()`;
    ///     the only way a `custom:*` id resolves.
    static func reconciliation(
        walletNetworkId: String,
        cachedConfigId: String?,
        storedConfig: NetworkConfig?
    ) -> Reconciliation {
        guard let cachedConfigId, let cached = resolve(id: cachedConfigId, stored: storedConfig) else {
            return .noUsableConfig
        }
        return cached.id == walletNetworkId ? .inSync : .reapply(cached)
    }

    /// Whether the account's config may replace this device's before the open.
    enum ReapplyDecision: Equatable {
        /// Re-point the wallet object to the account's config (rule 22).
        case reapply
        /// Keep this device's config and re-publish it to the account.
        case keepCurrent(reason: String)
    }

    /// Second gate behind `reconciliation`'s `.reapply`. Pure.
    ///
    /// Rule 22 re-points a wallet object built on the wrong *chain* so that the
    /// database on disk opens. Custom servers add a case rule 22 never had:
    /// the account can name a different *server on the same chain* (an older
    /// build that knows only preset ids imported the phrase onto Second; or a
    /// second device imported the same phrase onto a custom server). bark pins
    /// the server key in the database at creation and refuses every other
    /// server, so re-pointing an existing database to another server on its
    /// chain can only break a wallet that works. The guard applies in both
    /// directions, but only when `current` was *resolved from this device's
    /// cache*: `load()`'s mainnet fallback says nothing about the database and
    /// must still yield to the account (that is how a reinstall finds its
    /// custom server). The caller restores the kept config locally only, never
    /// to the account, so two devices on different servers do not fight.
    static func reapplyDecision(
        current: NetworkConfig,
        currentResolvedFromCache: Bool,
        cached: NetworkConfig,
        walletDatabaseExists: Bool
    ) -> ReapplyDecision {
        guard walletDatabaseExists, currentResolvedFromCache else { return .reapply }
        guard cached.networkType == current.networkType else { return .reapply }
        return .keepCurrent(reason: "account names another server on the same chain, but this device's database belongs to \(current.arkServerBaseURL)")
    }

    /// Whether the local cache holds an id that resolves (presets by id, a
    /// custom id through the stored JSON). `load()` falls back to mainnet when
    /// it does not; `reapplyDecision` needs to know which of the two happened.
    static func localCacheResolves() -> Bool {
        guard let id = savedConfigId() else { return false }
        return resolve(id: id, stored: storedConfig()) != nil
    }

    /// A custom id the account names whose full config cannot be resolved
    /// here (iCloud delivers the id and the JSON as separate keys, and older
    /// builds write the id only). Pure: `accountId` is the iCloud id, `candidates`
    /// are the account's JSON and this device's stored JSON. While pending,
    /// create and import refuse to write a *different* config over the
    /// account's, since that is how a preset silently replaces a custom server
    /// account-wide.
    static func pendingCustomServerId(accountId: String?, candidates: [NetworkConfig?]) -> String? {
        guard let accountId, accountId.hasPrefix(NetworkConfig.customIdPrefix) else { return nil }
        let resolvable = candidates.contains { resolve(id: accountId, stored: $0) != nil }
        return resolvable ? nil : accountId
    }

    /// Reads iCloud directly (off the main thread), because the create and
    /// import paths run before `syncFromiCloud` has ever run on a fresh device.
    static func accountPendingCustomServerId() async -> String? {
        let (iCloudId, iCloudData) = await Task.detached(priority: .utility) { () -> (String?, Data?) in
            let store = NSUbiquitousKeyValueStore.default
            return (store.string(forKey: iCloudKey), store.data(forKey: iCloudDataKey))
        }.value
        return pendingCustomServerId(accountId: iCloudId, candidates: [iCloudData.flatMap(decode), storedConfig()])
    }

    /// Write this device's cache only, leaving the account's value alone. Used
    /// when `reapplyDecision` keeps the current config: the sync just overwrote
    /// the cache with the account's value, and the next launch must not open
    /// the database with another server's config.
    static func saveLocally(_ networkConfig: NetworkConfig) {
        UserDefaults.standard.set(networkConfig.id, forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.set(encode(networkConfig), forKey: UserDefaults.networkConfigDataKey)
        logger.info("Network configuration restored locally: \(networkConfig.name) (ID: \(networkConfig.id)); account value left as is")
    }

    /// Resolve a config id. Pure. Presets resolve by id alone; anything else
    /// resolves only through a stored full config whose id matches, so a stale
    /// or foreign JSON blob can never answer for a different id.
    static func resolve(id: String, stored: NetworkConfig?) -> NetworkConfig? {
        if let preset = NetworkConfig.preset(byId: id) {
            return preset
        }
        if let stored, stored.id == id {
            return stored
        }
        return nil
    }

    /// Save the network configuration to UserDefaults (synchronous) and iCloud (background).
    /// Writes the id and the full config together so the two never disagree.
    /// - Parameter networkConfig: The network configuration to persist
    static func save(_ networkConfig: NetworkConfig) {
        let data = encode(networkConfig)

        // Save to UserDefaults synchronously (fast local cache, source of truth at launch)
        UserDefaults.standard.set(networkConfig.id, forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.set(data, forKey: UserDefaults.networkConfigDataKey)

        // Mirror to iCloud off the main thread (survives reinstalls and syncs across devices).
        // First access to the ubiquitous store can block, so never do it synchronously here.
        let id = networkConfig.id
        Task.detached(priority: .utility) {
            let store = NSUbiquitousKeyValueStore.default
            store.set(id, forKey: iCloudKey)
            if let data {
                store.set(data, forKey: iCloudDataKey)
            } else {
                store.removeObject(forKey: iCloudDataKey)
            }
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
            if let config = resolve(id: localId, stored: storedConfig()) {
                logger.info("Loaded network configuration from UserDefaults: \(config.name)")
                return config
            }
            logger.warning("Network ID '\(localId)' not resolvable locally")
        }

        // Default to mainnet (not signet)
        logger.info("No saved config found, using default: \(NetworkConfig.mainnet.name)")
        return .mainnet
    }

    /// Reconcile the local cache with iCloud in the background.
    /// Called from the pre-open reconciliation only (Launch_Sequence_Contract rule 22),
    /// never after a wallet is open.
    /// If iCloud holds a resolvable config id that differs from the local cache, the cache
    /// (id and full config) is updated and `networkConfigDidSyncFromiCloud` is posted.
    static func syncFromiCloud() async {
        // Access the ubiquitous store off the main thread — first touch may block on I/O.
        let (iCloudId, iCloudData) = await Task.detached(priority: .utility) { () -> (String?, Data?) in
            let store = NSUbiquitousKeyValueStore.default
            return (store.string(forKey: iCloudKey), store.data(forKey: iCloudDataKey))
        }.value

        guard let iCloudId else {
            // Nothing in iCloud yet. If we have a local value, push it up for other devices.
            if let localId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey) {
                let localData = UserDefaults.standard.data(forKey: UserDefaults.networkConfigDataKey)
                Task.detached(priority: .utility) {
                    let store = NSUbiquitousKeyValueStore.default
                    store.set(localId, forKey: iCloudKey)
                    if let localData {
                        store.set(localData, forKey: iCloudDataKey)
                    }
                }
            }
            return
        }

        // Resolve the account's id: presets by id, a custom server through the
        // account's full config, or this device's own copy of it (the two KVS
        // keys can arrive separately). Unknown preset-shaped ids are ignored,
        // as before.
        let iCloudConfig = iCloudData.flatMap(decode)
        let localId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey)
        let localConfig = storedConfig()
        guard let resolved = resolve(id: iCloudId, stored: iCloudConfig) ?? resolve(id: iCloudId, stored: localConfig) else {
            // Not resolvable here: an old `testnet` id, or a custom server whose
            // JSON has not arrived. Leave the local cache alone (it may hold a
            // resolvable config this device's database needs); create/import
            // consult iCloud directly for the pending case
            // (`accountPendingCustomServerId`).
            logger.warning("iCloud network config id '\(iCloudId)' not resolvable here, ignoring")
            return
        }

        // Self-heal: this device holds the custom config the account names but
        // the account's JSON key is missing or stale (the two keys upload
        // independently). Push the JSON so other devices can resolve the id.
        if iCloudId == localId, resolved.serverKind == .custom, iCloudConfig != resolved,
           let data = encode(resolved) {
            Task.detached(priority: .utility) {
                NSUbiquitousKeyValueStore.default.set(data, forKey: iCloudDataKey)
            }
            logger.info("Pushed missing custom server details for '\(iCloudId)' to iCloud")
        }

        guard iCloudId != localId || (resolved.serverKind == .custom && localConfig != resolved) else { return }

        // iCloud differs from local cache — update cache (id and full config) and notify observers.
        UserDefaults.standard.set(iCloudId, forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.set(encode(resolved), forKey: UserDefaults.networkConfigDataKey)
        logger.info("Synced network configuration from iCloud: \(iCloudId) (was \(localId ?? "none"))")
        await MainActor.run {
            NotificationCenter.default.post(name: networkConfigDidSyncFromiCloud, object: nil)
        }
    }

    /// Clear only this device's local cache. For local-only wallet deletion:
    /// the iCloud copy is account-shared property of the remaining devices and
    /// must survive — removing it strands every other device on the default
    /// network and their signet/testnet dbs refuse to open (2026-08-20
    /// incident; Launch_Sequence_Contract rule 21).
    static func clearLocal() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigDataKey)
        logger.info("Network configuration cleared locally (iCloud copy preserved)")
    }

    /// Clear the local cache AND the shared iCloud copy. Last-device full wipe
    /// only — owned by WalletDataCleanupService, like every other deletion of
    /// account-shared state.
    static func clearEverywhere() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigDataKey)

        // Remove from iCloud off the main thread (first access can block).
        Task.detached(priority: .utility) {
            let store = NSUbiquitousKeyValueStore.default
            store.removeObject(forKey: iCloudKey)
            store.removeObject(forKey: iCloudDataKey)
        }

        logger.info("Network configuration cleared from local and iCloud storage")
    }

    /// The raw network config id in the local cache, if any.
    /// Reads the UserDefaults cache only — safe to call synchronously, never touches iCloud.
    /// Returns the id unresolved; `reconciliation(walletNetworkId:cachedConfigId:storedConfig:)`
    /// decides what an unknown id means.
    static func savedConfigId() -> String? {
        UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey)
    }

    /// The full config in the local cache, if any. UserDefaults only.
    static func storedConfig() -> NetworkConfig? {
        UserDefaults.standard.data(forKey: UserDefaults.networkConfigDataKey).flatMap(decode)
    }

    // MARK: - Coding

    private nonisolated static func encode(_ config: NetworkConfig) -> Data? {
        do {
            return try JSONEncoder().encode(config)
        } catch {
            logger.error("Failed to encode network config \(config.id): \(error)")
            return nil
        }
    }

    private nonisolated static func decode(_ data: Data) -> NetworkConfig? {
        do {
            return try JSONDecoder().decode(NetworkConfig.self, from: data)
        } catch {
            logger.error("Failed to decode stored network config: \(error)")
            return nil
        }
    }
}
