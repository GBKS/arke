//
//  WalletDataCleanupService.swift
//  Arké
//
//  Created by Assistant on 12/09/24.
//

import Foundation
import SwiftData
import Observation

/// Responsible for comprehensive wallet data cleanup operations
/// Handles deletion of all wallet-related data from local storage, Keychain, and CloudKit
@MainActor
@Observable
class WalletDataCleanupService {
    
    // MARK: - Published Properties
    
    /// Current deletion progress (nil when not deleting)
    var deletionProgress: DeletionProgress?
    
    /// Error message for deletion operations
    var error: String?
    
    /// Loading state
    var isDeleting: Bool = false
    
    // MARK: - Dependencies
    
    private var modelContext: ModelContext?
    private let taskManager: TaskDeduplicationManager
    private var deviceRegistrationService: DeviceRegistrationService {
        ServiceContainer.shared.deviceRegistrationService
    }
    
    // MARK: - Constants
    
    private let keychainService = "com.arke.wallet"
    private let mnemonicAccount = "mnemonic"
    private let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Public API
    
    /// Determine the appropriate deletion strategy based on device registry
    func getDeletionStrategy() async -> DeletionStrategy {
        do {
            let hasOthers = try await deviceRegistrationService.hasOtherActiveDevices()
            
            if hasOthers {
                // Other devices exist - safe to delete locally only
                return .localOnly
            } else {
                // Last device - need to ask user about iCloud data
                return .promptForCloudData
            }
        } catch {
            #if DEBUG
            print("⚠️ [WalletDataCleanupService] Failed to check other devices: \(error.localizedDescription)")
            #endif
            
            // Fallback to prompt if we can't determine
            return .promptForCloudData
        }
    }
    
    /// Delete wallet data with specified strategy
    /// - Parameter includeCloudData: If true, deletes all data from CloudKit. If false, only local data.
    /// - Returns: Summary of what was deleted
    func deleteWalletData(includeCloudData: Bool) async throws -> DeletionSummary {
        return try await taskManager.execute(key: "deleteWalletData") {
            try await self.performDeleteWalletData(includeCloudData: includeCloudData)
        }
    }
    
    // MARK: - Internal Deletion Orchestration
    
    private func performDeleteWalletData(includeCloudData: Bool) async throws -> DeletionSummary {
        isDeleting = true
        defer { 
            isDeleting = false
            deletionProgress = nil
        }
        
        var summary = DeletionSummary(timestamp: Date())
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Starting wallet data deletion (includeCloudData: \(includeCloudData))")
        #endif
        
        // Step 1: Delete keychain data — full wipe only. The mnemonic is
        // synced via iCloud Keychain, so deleting it here would propagate to
        // every device and permanently lock the remaining secondaries out of
        // promotion. With other active devices the seed is shared property
        // and must survive this device's deletion.
        if includeCloudData {
            updateProgress(.deletingKeychain, message: "Removing mnemonic from Keychain...")
            do {
                try Self.deleteKeychainItem(service: keychainService, account: mnemonicAccount)
                summary.keychainDeleted = true
                #if DEBUG
                print("✅ [WalletDataCleanupService] Keychain data deleted")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [WalletDataCleanupService] Failed to delete keychain: \(error)")
                #endif
                throw WalletCleanupError.keychainDeletionFailed(error)
            }
        } else {
            #if DEBUG
            print("⏭️ [WalletDataCleanupService] Keeping mnemonic (wallet lives on other devices)")
            #endif
        }

        // Step 2: Unregister device
        updateProgress(.unregisteringDevice, message: "Unregistering device...")
        do {
            try await deviceRegistrationService.unregisterCurrentDevice()
            summary.deviceUnregistered = true
            #if DEBUG
            print("✅ [WalletDataCleanupService] Device unregistered")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [WalletDataCleanupService] Failed to unregister device: \(error)")
            #endif
            // Non-fatal, continue
        }
        
        // Step 3: Delete cloud data if requested
        if includeCloudData {
            // Get wallet hash before deleting it (needed for KV store cleanup)
            let walletHash = getHashFromUbiquitousStore()
            
            // Delete hash from ubiquitous store
            updateProgress(.deletingCloudHash, message: "Removing hash from iCloud...")
            deleteHashFromUbiquitousStore()
            summary.ubiquitousHashDeleted = true
            
            // Clear device registrations from KV store
            if let hash = walletHash {
                updateProgress(.deletingCloudHash, message: "Clearing device registrations...")
                deviceRegistrationService.clearDeviceRegistrationsFromKVStore(walletHash: hash)
                #if DEBUG
                print("✅ [WalletDataCleanupService] Cleared device registrations from KV store")
                #endif
            }

            // Delete the shared network configuration from iCloud KVS. Full
            // wipe only: on local-only deletion the KVS copy is the remaining
            // devices' network identity — removing it strands them on the
            // default network (2026-08-20 incident; contract rule 21)
            updateProgress(.deletingCloudHash, message: "Removing network configuration from iCloud...")
            NetworkConfigPersistence.clearEverywhere()

            // Delete the wallet database backup from iCloud Drive
            // A leftover backup would resurface via the restore-on-launch path
            // after a new wallet is created
            updateProgress(.deletingBackupStatus, message: "Deleting iCloud backup...")
            summary.iCloudBackupDeleted = WalletBackupService.deleteAllBackups()
            #if DEBUG
            print("✅ [WalletDataCleanupService] iCloud backup deletion: \(summary.iCloudBackupDeleted ? "complete" : "skipped or failed")")
            #endif
            
            // Delete all CloudKit data
            guard let modelContext = modelContext else {
                throw WalletCleanupError.noModelContext
            }
            
            let cloudSummary = try await deleteCloudKitData(modelContext: modelContext)
            summary.merge(cloudSummary)
            
            #if DEBUG
            print("✅ [WalletDataCleanupService] Cloud data deletion complete")
            #endif
        } else {
            #if DEBUG
            print("⏭️ [WalletDataCleanupService] Skipping cloud data deletion")
            #endif
        }
        
        // Step 4: Clear UserDefaults
        updateProgress(.clearingUserDefaults, message: "Clearing user preferences...")
        clearUserDefaults()
        summary.userDefaultsCleared = true

        // Step 5: Record or clear the local-deletion tombstone. Local-only
        // deletion leaves the seed in iCloud Keychain (shared property of the
        // other devices), so without a tombstone the next launch would silently
        // resurrect the wallet. Detection routes a tombstoned install to the
        // rejoin screen instead (Wallet_Deletion_And_Rejoin.md). Set AFTER
        // clearUserDefaults so it can't be wiped by that step.
        if includeCloudData {
            SecurityService.clearLocalDeletionTombstone()
        } else if let walletHash = getHashFromUbiquitousStore() {
            SecurityService.recordLocalDeletionTombstone(walletHash: walletHash)
        } else {
            #if DEBUG
            print("⚠️ [WalletDataCleanupService] No wallet hash readable — skipping local-deletion tombstone (next launch falls back to normal detection)")
            #endif
        }

        updateProgress(.finalizingDeletion, message: "Finalizing deletion...")
        
        #if DEBUG
        print("✅ [WalletDataCleanupService] Wallet data deletion complete")
        print("📊 Summary: \(summary.totalItemsDeleted) items deleted")
        #endif
        
        return summary
    }
    
    // MARK: - Keychain Deletion

    /// Deletes a keychain item regardless of its synchronizable attribute.
    /// The mnemonic is saved with kSecAttrSynchronizable: true (iCloud
    /// Keychain), but very old installs may hold a pre-sync local item —
    /// kSecAttrSynchronizableAny matches both. A query without the attribute
    /// matches only non-synchronizable items and silently misses the seed.
    /// Parametrized so tests can run it against a scratch item.
    nonisolated static func deleteKeychainItem(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletCleanupError.keychainError(status)
        }
    }
    
    // MARK: - Ubiquitous Store Deletion
    
    private func getHashFromUbiquitousStore() -> String? {
        let store = NSUbiquitousKeyValueStore.default
        return store.string(forKey: ubiquitousHashKey)
    }
    
    private func deleteHashFromUbiquitousStore() {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: ubiquitousHashKey)
        store.synchronize()
    }
    
    // MARK: - UserDefaults Cleanup
    
    private func clearUserDefaults() {
        // Reset balance privacy to default (false = visible)
        UserDefaults.standard.removeObject(forKey: UserDefaults.balancePrivacyKey)
        
        // Reset notification preference
        UserDefaults.standard.removeObject(forKey: UserDefaults.notificationsEnabledKey)
        
        // Clear saved network configuration (local cache only — the iCloud
        // copy is handled strategy-aware above, contract rule 21)
        NetworkConfigPersistence.clearLocal()
        
        // Reset address icons preference
        UserDefaults.standard.removeObject(forKey: UserDefaults.showAddressIconsKey)
        
        // Reset nearby device detection
        UserDefaults.standard.removeObject(forKey: UserDefaults.proximityPermissionKey)

        // Reset initial sync completion marker
        UserDefaults.standard.removeObject(forKey: UserDefaults.initialSyncCompletedKey)
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Cleared balance privacy, notification settings, network config, and address icons preference")
        #endif
    }
    
    // MARK: - CloudKit Data Deletion
    
    private func deleteCloudKitData(modelContext: ModelContext) async throws -> DeletionSummary {
        var summary = DeletionSummary(timestamp: Date())
        
        // 1. Delete transactions
        updateProgress(.deletingTransactions, message: "Deleting transactions...")
        let (txCount, tagAssignmentCount, contactAssignmentCount) = try await deleteTransactions(modelContext: modelContext)
        summary.transactionsDeleted = txCount
        summary.transactionTagAssignmentsDeleted = tagAssignmentCount
        summary.transactionContactAssignmentsDeleted = contactAssignmentCount
        
        // 1b. Delete exit history — PersistentExitCache is merge-saved and
        // never pruned by refreshes (it preserves exit history past bark's
        // purge), so wallet deletion is the only place it gets cleared;
        // leftovers would show the OLD wallet's completed exits in the
        // X-Ray of a newly created/imported wallet
        updateProgress(.deletingTransactions, message: "Deleting exit history...")
        summary.exitHistoryDeleted = try await deleteExitHistory(modelContext: modelContext)

        // 1c. Delete pending send metadata (PendingPaymentMetadata /
        // PendingTagAssignment) — created by the send flow before a bark txid
        // exists; an old wallet's leftover entries would mis-attach to the next
        // wallet's transactions. Gap found by the wipe-coverage inventory
        // (Wallet_Deletion_And_Rejoin.md)
        updateProgress(.deletingTransactions, message: "Deleting pending send metadata...")
        summary.pendingSendMetadataDeleted = try await deletePendingSendMetadata(modelContext: modelContext)

        // 2. Delete tags
        updateProgress(.deletingTags, message: "Deleting tags...")
        summary.tagsDeleted = try await deleteTags(modelContext: modelContext)
        
        // 3. Delete contacts
        updateProgress(.deletingContacts, message: "Deleting contacts...")
        let (contactCount, addressCount) = try await deleteContacts(modelContext: modelContext)
        summary.contactsDeleted = contactCount
        summary.contactAddressesDeleted = addressCount
        
        // 4. Delete balance cache
        updateProgress(.deletingBalanceCache, message: "Deleting balance cache...")
        summary.balanceCacheDeleted = try await deleteBalanceCache(modelContext: modelContext)
        
        // 5. Delete configuration
        updateProgress(.deletingConfiguration, message: "Deleting wallet configuration...")
        summary.configurationsDeleted = try await deleteConfiguration(modelContext: modelContext)
        
        // 6. Delete device registrations
        updateProgress(.deletingDeviceRegistry, message: "Deleting device registrations...")
        summary.deviceRegistrationsDeleted = try await deleteDeviceRegistrations(modelContext: modelContext)
        
        // 7. Delete backup status (ongoing exits no longer tracked locally)
        updateProgress(.deletingBackupStatus, message: "Deleting backup status...")
        summary.backupStatusDeleted = try await deleteBackupStatus(modelContext: modelContext)
        
        // 8. Delete address history
        updateProgress(.deletingAddressHistory, message: "Deleting address history...")
        summary.addressHistoryDeleted = try await deleteAddressHistory(modelContext: modelContext)
        
        // 9. Delete user profile
        updateProgress(.deletingUserProfile, message: "Deleting user profile...")
        summary.userProfileDeleted = try await deleteUserProfile(modelContext: modelContext)
        
        // Save all deletions
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ [WalletDataCleanupService] All CloudKit deletions saved")
            #endif
        } catch {
            #if DEBUG
            print("❌ [WalletDataCleanupService] Failed to save deletions: \(error)")
            #endif
            throw WalletCleanupError.saveFailed(error)
        }
        
        return summary
    }
    
    // MARK: - Individual Entity Deletion
    
    private func deleteTransactions(modelContext: ModelContext) async throws -> (transactions: Int, tagAssignments: Int, contactAssignments: Int) {
        let descriptor = FetchDescriptor<PersistentTransaction>()
        let transactions = try modelContext.fetch(descriptor)
        
        // Pre-resolve all faults before deletion to prevent "detached from context" errors
        // This includes accessing properties that may be used by conversion methods or cascading deletes
        var tagAssignmentCount = 0
        var contactAssignmentCount = 0
        
        for transaction in transactions {
            // Access properties to force SwiftData to resolve faults
            _ = transaction.childTxids
            _ = transaction.parentTxid
            _ = transaction.tagAssignments
            _ = transaction.contactAssignments
            _ = transaction.receivingAddress
            
            // Count relationships
            tagAssignmentCount += transaction.tagAssignments?.count ?? 0
            contactAssignmentCount += transaction.contactAssignments?.count ?? 0
        }
        
        // Now delete all transactions
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(transactions.count) transactions for deletion (cascade: \(tagAssignmentCount) tag assignments, \(contactAssignmentCount) contact assignments)")
        #endif
        
        return (transactions.count, tagAssignmentCount, contactAssignmentCount)
    }
    
    private func deleteExitHistory(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<PersistentExitCache>()
        let entries = try modelContext.fetch(descriptor)

        for entry in entries {
            modelContext.delete(entry)
        }

        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(entries.count) exit history entries for deletion")
        #endif

        return entries.count
    }

    private func deletePendingSendMetadata(modelContext: ModelContext) async throws -> Int {
        let metadataDescriptor = FetchDescriptor<PendingPaymentMetadata>()
        let metadata = try modelContext.fetch(metadataDescriptor)
        for entry in metadata {
            modelContext.delete(entry)
        }

        let tagDescriptor = FetchDescriptor<PendingTagAssignment>()
        let pendingTags = try modelContext.fetch(tagDescriptor)
        for entry in pendingTags {
            modelContext.delete(entry)
        }

        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(metadata.count) pending payment metadata and \(pendingTags.count) pending tag assignments for deletion")
        #endif

        return metadata.count + pendingTags.count
    }

    private func deleteTags(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<PersistentTag>()
        let tags = try modelContext.fetch(descriptor)
        
        for tag in tags {
            modelContext.delete(tag)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(tags.count) tags for deletion")
        #endif
        
        return tags.count
    }
    
    private func deleteContacts(modelContext: ModelContext) async throws -> (contacts: Int, addresses: Int) {
        let descriptor = FetchDescriptor<PersistentContact>()
        let contacts = try modelContext.fetch(descriptor)
        
        let addressCount = contacts.reduce(0) { $0 + ($1.addresses?.count ?? 0) }
        
        for contact in contacts {
            modelContext.delete(contact)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(contacts.count) contacts for deletion (cascade: \(addressCount) addresses)")
        #endif
        
        return (contacts.count, addressCount)
    }
    
    private func deleteBalanceCache(modelContext: ModelContext) async throws -> Int {
        var count = 0
        
        // Delete Ark balance cache
        let arkBalanceDescriptor = FetchDescriptor<ArkBalanceModel>()
        let arkBalances = try modelContext.fetch(arkBalanceDescriptor)
        for balance in arkBalances {
            modelContext.delete(balance)
            count += 1
        }
        
        // Delete onchain balance cache
        let onchainBalanceDescriptor = FetchDescriptor<OnchainBalanceModel>()
        let onchainBalances = try modelContext.fetch(onchainBalanceDescriptor)
        for balance in onchainBalances {
            modelContext.delete(balance)
            count += 1
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(count) balance cache records for deletion")
        #endif
        
        return count
    }
    
    private func deleteConfiguration(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<WalletConfiguration>()
        let configs = try modelContext.fetch(descriptor)
        
        for config in configs {
            modelContext.delete(config)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(configs.count) wallet configurations for deletion")
        #endif
        
        return configs.count
    }
    
    private func deleteDeviceRegistrations(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<DeviceRegistration>()
        let devices = try modelContext.fetch(descriptor)
        
        for device in devices {
            modelContext.delete(device)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(devices.count) device registrations for deletion")
        #endif
        
        return devices.count
    }
    
    private func deleteBackupStatus(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<BackupStatus>()
        let backupStatuses = try modelContext.fetch(descriptor)
        
        for status in backupStatuses {
            modelContext.delete(status)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(backupStatuses.count) backup status records for deletion")
        #endif
        
        return backupStatuses.count
    }
    
    private func deleteAddressHistory(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<PersistentAddress>()
        let addresses = try modelContext.fetch(descriptor)
        
        for address in addresses {
            modelContext.delete(address)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(addresses.count) address history records for deletion")
        #endif
        
        return addresses.count
    }
    
    private func deleteUserProfile(modelContext: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = try modelContext.fetch(descriptor)
        
        for profile in profiles {
            modelContext.delete(profile)
        }
        
        #if DEBUG
        print("🗑️ [WalletDataCleanupService] Queued \(profiles.count) user profile(s) for deletion")
        #endif
        
        return profiles.count
    }
    
    // MARK: - Progress Tracking
    
    private func updateProgress(_ step: DeletionStep, message: String) {
        deletionProgress = DeletionProgress(
            currentStep: step,
            totalSteps: 14, // Total number of deletion steps (including address history, user profile, and user defaults)
            message: message
        )
        
        #if DEBUG
        print("📊 [WalletDataCleanupService] Progress: \(step.displayName) - \(message)")
        #endif
    }
    
    // MARK: - State Management
    
    /// Clear error state
    func clearError() {
        error = nil
    }
}

// MARK: - Supporting Types

/// Progress information for ongoing deletion operation
struct DeletionProgress {
    let currentStep: DeletionStep
    let totalSteps: Int
    let message: String
    
    var progressPercentage: Double {
        Double(currentStep.rawValue) / Double(totalSteps)
    }
}

/// Individual deletion steps
enum DeletionStep: Int, CaseIterable {
    case deletingKeychain = 1
    case unregisteringDevice = 2
    case deletingCloudHash = 3
    case deletingTransactions = 4
    case deletingTags = 5
    case deletingContacts = 6
    case deletingBalanceCache = 7
    case deletingConfiguration = 8
    case deletingDeviceRegistry = 9
    case deletingBackupStatus = 10
    case deletingAddressHistory = 11
    case deletingUserProfile = 12
    case clearingUserDefaults = 13
    case finalizingDeletion = 14
    
    var displayName: String {
        switch self {
        case .deletingKeychain:
            return "Deleting Keychain"
        case .unregisteringDevice:
            return "Unregistering Device"
        case .deletingCloudHash:
            return "Deleting Cloud Hash"
        case .deletingTransactions:
            return "Deleting Transactions"
        case .deletingTags:
            return "Deleting Tags"
        case .deletingContacts:
            return "Deleting Contacts"
        case .deletingBalanceCache:
            return "Deleting Balance Cache"
        case .deletingConfiguration:
            return "Deleting Configuration"
        case .deletingDeviceRegistry:
            return "Deleting Device Registry"
        case .deletingBackupStatus:
            return "Deleting Backup Status"
        case .deletingAddressHistory:
            return "Deleting Address History"
        case .deletingUserProfile:
            return "Deleting User Profile"
        case .clearingUserDefaults:
            return "Clearing User Defaults"
        case .finalizingDeletion:
            return "Finalizing"
        }
    }
}

/// Summary of what was deleted during wallet cleanup
struct DeletionSummary: Codable {
    var keychainDeleted: Bool = false
    var deviceUnregistered: Bool = false
    var ubiquitousHashDeleted: Bool = false
    var userDefaultsCleared: Bool = false
    var iCloudBackupDeleted: Bool = false
    
    var transactionsDeleted: Int = 0
    var transactionTagAssignmentsDeleted: Int = 0
    var transactionContactAssignmentsDeleted: Int = 0
    var exitHistoryDeleted: Int = 0
    var pendingSendMetadataDeleted: Int = 0
    var tagsDeleted: Int = 0
    var contactsDeleted: Int = 0
    var contactAddressesDeleted: Int = 0
    var balanceCacheDeleted: Int = 0
    var configurationsDeleted: Int = 0
    var deviceRegistrationsDeleted: Int = 0
    var backupStatusDeleted: Int = 0
    var addressHistoryDeleted: Int = 0
    var userProfileDeleted: Int = 0
    
    let timestamp: Date
    
    var totalItemsDeleted: Int {
        transactionsDeleted +
        transactionTagAssignmentsDeleted +
        transactionContactAssignmentsDeleted +
        exitHistoryDeleted +
        pendingSendMetadataDeleted +
        tagsDeleted +
        contactsDeleted + 
        contactAddressesDeleted + 
        balanceCacheDeleted + 
        configurationsDeleted + 
        deviceRegistrationsDeleted +
        backupStatusDeleted +
        addressHistoryDeleted +
        userProfileDeleted
    }
    
    var cloudDataDeleted: Bool {
        totalItemsDeleted > 0
    }
    
    /// Merge another summary into this one
    mutating func merge(_ other: DeletionSummary) {
        keychainDeleted = keychainDeleted || other.keychainDeleted
        deviceUnregistered = deviceUnregistered || other.deviceUnregistered
        ubiquitousHashDeleted = ubiquitousHashDeleted || other.ubiquitousHashDeleted
        userDefaultsCleared = userDefaultsCleared || other.userDefaultsCleared
        iCloudBackupDeleted = iCloudBackupDeleted || other.iCloudBackupDeleted
        
        transactionsDeleted += other.transactionsDeleted
        transactionTagAssignmentsDeleted += other.transactionTagAssignmentsDeleted
        transactionContactAssignmentsDeleted += other.transactionContactAssignmentsDeleted
        exitHistoryDeleted += other.exitHistoryDeleted
        pendingSendMetadataDeleted += other.pendingSendMetadataDeleted
        tagsDeleted += other.tagsDeleted
        contactsDeleted += other.contactsDeleted
        contactAddressesDeleted += other.contactAddressesDeleted
        balanceCacheDeleted += other.balanceCacheDeleted
        configurationsDeleted += other.configurationsDeleted
        deviceRegistrationsDeleted += other.deviceRegistrationsDeleted
        backupStatusDeleted += other.backupStatusDeleted
        addressHistoryDeleted += other.addressHistoryDeleted
        userProfileDeleted += other.userProfileDeleted
    }
    
    /// Human-readable summary string
    var summaryDescription: String {
        var parts: [String] = []
        
        if transactionsDeleted > 0 {
            parts.append(String(localized: "\(transactionsDeleted) transactions"))
        }
        if tagsDeleted > 0 {
            parts.append(String(localized: "\(tagsDeleted) tags"))
        }
        if contactsDeleted > 0 {
            parts.append(String(localized: "\(contactsDeleted) contacts"))
        }
        if contactAddressesDeleted > 0 {
            parts.append(String(localized: "\(contactAddressesDeleted) addresses"))
        }
        if balanceCacheDeleted > 0 {
            parts.append(String(localized: "\(balanceCacheDeleted) balance cache records"))
        }
        if backupStatusDeleted > 0 {
            parts.append(String(localized: "\(backupStatusDeleted) backup status records"))
        }
        if addressHistoryDeleted > 0 {
            parts.append(String(localized: "\(addressHistoryDeleted) address history records"))
        }
        
        if parts.isEmpty {
            return String(localized: "settings_no_cloud_data_deleted", defaultValue: "No cloud data deleted")
        } else {
            return String(localized: "settings_deleted_summary %@", defaultValue: "Deleted: \(parts.joined(separator: ", "))")
        }
    }
}

/// Deletion-fate inventory for every SwiftData model in the app schema.
/// WalletWipeCoverageTests asserts these three lists exactly cover
/// SwiftDataHelper.appSchemaModels — adding a @Model without deciding its
/// deletion fate fails the test (Wallet_Deletion_And_Rejoin.md).
enum WalletWipeCoverage {
    /// Deleted directly by a delete* step in WalletDataCleanupService
    static let directlyWiped: [any PersistentModel.Type] = [
        PersistentTransaction.self,
        PersistentExitCache.self,
        PendingPaymentMetadata.self,
        PendingTagAssignment.self,
        PersistentTag.self,
        PersistentContact.self,
        ArkBalanceModel.self,
        OnchainBalanceModel.self,
        WalletConfiguration.self,
        DeviceRegistration.self,
        BackupStatus.self,
        PersistentAddress.self,
        UserProfile.self
    ]

    /// Removed via relationship cascade from a directly wiped owner
    static let cascadeWiped: [any PersistentModel.Type] = [
        TransactionTagAssignment.self,      // cascade from PersistentTransaction
        TransactionContactAssignment.self,  // cascade from PersistentTransaction
        PersistentContactAddress.self       // cascade from PersistentContact
    ]

    /// Deliberately NOT wiped — every entry must state its reason
    static let exempt: [any PersistentModel.Type] = []
}

/// Deletion-scope inventory for account-shared state OUTSIDE SwiftData:
/// iCloud Keychain items and iCloud KVS keys. A device-scoped ("local-only")
/// deletion must NEVER destroy a `.fullWipeOnly` entry — these are shared
/// property of the remaining devices. Two incidents define this inventory:
/// the seed deletion (2026-08-19) and the network-config deletion
/// (2026-08-20), both the same fault: a device-scoped action destroying
/// account-scoped state. Consistency is test-asserted
/// (WalletDeletionRejoinTests); completeness is maintained by review — every
/// new shared key gets an entry HERE with a scope.
enum SharedStateWipeCoverage {
    enum Scope {
        case fullWipeOnly   // deleted only on the last-device full wipe
        case deviceLocal    // this device's copy only; account copies untouched
    }

    struct Entry {
        let key: String
        let store: String
        let scope: Scope
    }

    static let entries: [Entry] = [
        Entry(key: "com.arke.wallet / mnemonic",           store: "iCloud Keychain", scope: .fullWipeOnly),
        Entry(key: "com.arke.wallet.mnemonicHash",         store: "iCloud KVS",      scope: .fullWipeOnly),
        Entry(key: "com.arke.wallet.networkConfigId",      store: "iCloud KVS",      scope: .fullWipeOnly),
        Entry(key: "device_<id>_* (registration mirror)",  store: "iCloud KVS",      scope: .fullWipeOnly),
        Entry(key: "com.arke.device / deviceId",           store: "local Keychain",  scope: .deviceLocal),
        Entry(key: "com.arke.wallet.deletedLocally",       store: "UserDefaults",    scope: .deviceLocal),
        Entry(key: "com.arke.wallet.hasRunLocally",        store: "UserDefaults",    scope: .deviceLocal)
    ]
}

/// Deletion strategy based on device registry state
enum DeletionStrategy {
    case localOnly             // Delete seed + unregister device, keep iCloud data
    case promptForCloudData    // Ask user if they want to delete iCloud data too
    
    var title: String {
        switch self {
        case .localOnly:
            return "Other Devices Detected"
        case .promptForCloudData:
            return "Last Device"
        }
    }
    
    var message: String {
        switch self {
        case .localOnly:
            return "Other devices have this wallet. The wallet will be removed from this device only."
        case .promptForCloudData:
            return "This is the last device with this wallet. Do you want to delete all wallet data from iCloud?"
        }
    }
    
    var recommendedAction: String {
        switch self {
        case .localOnly:
            return "Delete from This Device"
        case .promptForCloudData:
            return String(localized: "button_delete_everything", defaultValue: "Delete Everything")
        }
    }
}

/// Errors that can occur during wallet cleanup
enum WalletCleanupError: LocalizedError {
    case noModelContext
    case keychainError(OSStatus)
    case keychainDeletionFailed(Error)
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "No model context available for data deletion"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keychainDeletionFailed(let error):
            return "Failed to delete keychain data: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save deletion changes: \(error.localizedDescription)"
        }
    }
}
