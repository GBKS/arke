//
//  SecurityService.swift
//  Arké
//
//  Created by Christoph on 11/28/25.
//

import Foundation
import SwiftData
import CryptoKit
import LocalAuthentication
import Observation
import CommonCrypto
import OSLog

@MainActor
@Observable
class SecurityService {
    // MARK: - Logging
    
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "SecurityService")
    
    // MARK: - Published Properties
    
    /// Current wallet state for cross-device detection
    var walletState: WalletState = .unknown
    
    /// Error message for security operations
    var error: String?
    
    /// Loading state
    var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    private var modelContext: ModelContext?
    private let taskManager: TaskDeduplicationManager
    
    // MARK: - Constants
    
    private let keychainService = "com.arke.wallet"
    private let mnemonicAccount = "mnemonic"
    private let hashSalt = "com.arke.mnemonic.hash.v1"
    private let pbkdf2Iterations = 100_000
    private let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Static Lightweight Detection
    
    /// Lightweight synchronous check for wallet existence (no dependencies required)
    /// Use this for early app initialization before full service stack is available
    /// - Returns: `true` if a mnemonic exists in the Keychain, `false` otherwise
    static func hasMnemonicInKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arke.wallet",
            kSecAttrAccount as String: "mnemonic",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]
        
        let exists = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        
        #if DEBUG
        print("🔍 [SecurityService.static] Keychain mnemonic check: \(exists ? "✅ Found" : "⚠️ Not found") at \(Date())")
        #endif
        
        return exists
    }
    
    // MARK: - Wallet State Detection
    
    /// Detects if user has a wallet on another device
    /// Does NOT register the device - coordinator should call device registration separately
    func detectWalletState() async -> WalletState {
        return await taskManager.execute(key: "detectWalletState") {
            return await self.performWalletStateDetection()
        }
    }
    
    /// Checks if current device is primary, returns walletActiveElsewhere state if not
    private func checkDevicePrimaryStatus(modelContext: ModelContext) -> WalletState? {
        do {
            // Get the device ID from keychain
            guard let deviceIdData = getDeviceIdFromKeychain(),
                  let deviceId = String(data: deviceIdData, encoding: .utf8) else {
                Self.logger.warning("⚠️ Could not get device ID from keychain")
                return nil
            }

            // Get the current wallet hash
            guard let currentWalletHash = getUbiquitousHash() else {
                Self.logger.warning("⚠️ Could not get current wallet hash")
                return nil
            }
            
            // Fetch devices for the CURRENT wallet only
            let descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate<DeviceRegistration> { device in
                    device.walletHash == currentWalletHash && device.isActive
                }
            )
            let walletDevices = try modelContext.fetch(descriptor)
            
            // Find current device by matching deviceId
            let currentDevice = walletDevices.first { $0.deviceId == deviceId }
            
            if let current = currentDevice {
                if !current.isPrimaryDevice {
                    // Get the primary device name
                    let primaryDevice = walletDevices.first { $0.isPrimaryDevice }
                    let primaryDeviceName = primaryDevice?.deviceName ?? "Another Device"
                    
                    Self.logger.info("⚠️ Wallet exists locally but device is not primary. Primary device: \(primaryDeviceName)")
                    return .walletActiveElsewhere(deviceName: primaryDeviceName)
                }
            }
        } catch {
            Self.logger.warning("⚠️ Failed to check device primary status: \(error)")
            // Continue with normal flow if check fails
        }
        
        return nil
    }
    
    /// Gets the device ID from keychain
    private func getDeviceIdFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arke.device",
            kSecAttrAccount as String: "deviceId",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        
        return nil
    }
    
    /// Internal method that performs the actual wallet state detection
    private func performWalletStateDetection() async -> WalletState {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            Self.logger.info("⏱️ Wallet state detection took \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))s")
        }
        Self.logger.debug("Wallet state detection: checking local keychain...")

        // 1. Check local keychain first (instant)
        if self.hasMnemonic() {
            Self.logger.debug("Wallet state detection: mnemonic found, checking device primary status...")
            
            // 1.5. Check if this device is the primary device
            // If wallet exists but device is not primary, return walletActiveElsewhere
            if let modelContext = self.modelContext {
                if let state = self.checkDevicePrimaryStatus(modelContext: modelContext) {
                    return state
                }
            }
            
            return .walletWithSeed
        }
        
        Self.logger.debug("Wallet state detection: no local mnemonic, checking iCloud KVS...")

        // 2. Check NSUbiquitousKeyValueStore for synced hash
        // This is the single source of truth for cross-device wallet detection
        if self.getUbiquitousHash() != nil {
            // Wallet exists on another device
            // Check if this device is registered and whether it should have read-only access
            if self.modelContext != nil {
                do {
                    // Get device registration service
                    let deviceService = ServiceContainer.shared.deviceRegistrationService
                    
                    // Check if this device is registered
                    if try await deviceService.getCurrentDevice() != nil {
                        // Device is registered - it's a secondary device with read-only access
                        let primaryDevice = try await deviceService.getPrimaryDevice()
                        let primaryDeviceName = primaryDevice?.deviceName ?? "Another Device"
                        
                        Self.logger.info("📱 Device is registered as secondary (no seed) - enabling read-only mode")
                        return .walletActiveElsewhere(deviceName: primaryDeviceName)
                    }
                } catch {
                    Self.logger.warning("⚠️ Failed to check device registration: \(error)")
                }
            }
            
            // Device not registered or check failed - return walletWithoutSeed
            return .walletWithoutSeed
        }
        
        Self.logger.debug("Wallet state detection: no wallet found anywhere")

        return .noWallet
    }
    
    // MARK: - Mnemonic Storage (iCloud Keychain)
    
    /// Saves mnemonic to keychain and syncs via iCloud Keychain
    /// Note: Device registration should be done by coordinator after this call
    func saveMnemonic(_ mnemonic: String, requireBiometric: Bool = false) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let data = mnemonic.data(using: .utf8) else {
            throw WalletError.encodingFailed
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true  // Sync via iCloud Keychain
        ]
        
        // Set access control based on biometric requirement
        if requireBiometric {
            // Use SecAccessControl for biometric protection
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &error
            ) else {
                if let error = error?.takeRetainedValue() {
                    print("⚠️ Failed to create SecAccessControl: \(error)")
                    throw WalletError.keychainError(errSecParam)
                }
                throw WalletError.keychainError(errSecParam)
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            // Use simple accessibility without biometric requirement
            // Use kSecAttrAccessibleWhenUnlocked (not ThisDeviceOnly) to allow iCloud Keychain sync
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        }
        
        // Delete existing entry first (use a clean query with only identifying attributes)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrSynchronizable as String: true
        ]
        let deleteStartTime = CFAbsoluteTimeGetCurrent()
        SecItemDelete(deleteQuery as CFDictionary)
        let deleteTime = CFAbsoluteTimeGetCurrent() - deleteStartTime
        Self.logger.info("⏱️ [PROFILE] Keychain delete took \(String(format: "%.3f", deleteTime))s")
        
        // Add new entry
        let addStartTime = CFAbsoluteTimeGetCurrent()
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError(status)
        }
        let addTime = CFAbsoluteTimeGetCurrent() - addStartTime
        Self.logger.info("⏱️ [PROFILE] Keychain add took \(String(format: "%.3f", addTime))s")
        
        // Save hash to ubiquitous store for cross-device wallet detection
        let hashStartTime = CFAbsoluteTimeGetCurrent()
        saveHashToUbiquitousStore(mnemonic)
        let hashTime = CFAbsoluteTimeGetCurrent() - hashStartTime
        Self.logger.info("⏱️ [PROFILE] Hash generation and ubiquitous store save took \(String(format: "%.3f", hashTime))s")
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("⏱️ [PROFILE] Total saveMnemonic() took \(String(format: "%.3f", totalTime))s")
        
        #if DEBUG
        print("✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store")
        print("   ℹ️  Coordinator should call DeviceRegistrationService.registerCurrentDevice() next")
        #endif
    }
    
    /// Loads mnemonic from keychain
    func loadMnemonic() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw WalletError.keychainError(status)
        }
        
        guard let data = result as? Data else {
            throw WalletError.encodingFailed
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Checks if mnemonic exists in keychain
    func hasMnemonic() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]
        
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    
    /// Handles seed import after QR code scan
    /// Note: Device registration should be done by coordinator after this call
    func handleSeedImport(_ mnemonic: String) async throws {
        // Save mnemonic (no device registration here)
        try await saveMnemonic(mnemonic)
        
        #if DEBUG
        print("✅ [SecurityService] Seed imported - coordinator should update device registration")
        #endif
    }
    
    /// Removes mnemonic from keychain only (used for rollback during failed imports)
    /// Does not touch cloud data or device registration
    func removeMnemonic() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrSynchronizable as String: true
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletError.keychainError(status)
        }
        
        #if DEBUG
        Self.logger.debug("🗑️ [SecurityService] Removed mnemonic from keychain (rollback)")
        #endif
    }
    
    /// Deletes all wallet data including mnemonic, transactions, contacts, tags, and cloud data
    /// Note: Coordinator should handle device unregistration separately
    /// - Parameter includeCloudData: If true, deletes all data from CloudKit. If false, only local keychain.
    func deleteWalletData(includeCloudData: Bool = false) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletError.keychainError(status)
        }
        
        #if DEBUG
        print("🗑️ [SecurityService] Deleted mnemonic from Keychain")
        print("   ℹ️  Coordinator should call DeviceRegistrationService.unregisterCurrentDevice() next")
        #endif
        
        // Delete cloud data if requested
        if includeCloudData {
            #if DEBUG
            print("🗑️ [SecurityService] Starting comprehensive cloud data deletion...")
            #endif
            
            // Remove hash from ubiquitous store
            deleteHashFromUbiquitousStore()
            
            // Delete all user data from SwiftData/CloudKit if available
            if let modelContext = modelContext {
                try await deleteAllWalletDataFromSwiftData(modelContext: modelContext)
            } else {
                #if DEBUG
                print("⚠️ [SecurityService] No model context available for cloud data deletion")
                #endif
            }
            
            #if DEBUG
            print("✅ [SecurityService] Comprehensive cloud data deletion complete")
            #endif
        } else {
            #if DEBUG
            print("⏭️ [SecurityService] Keeping iCloud data (hash and configurations)")
            #endif
        }
    }
    
    /// Deletes all wallet-related data from SwiftData/CloudKit
    /// This includes transactions, tags, contacts, balances, and configuration
    private func deleteAllWalletDataFromSwiftData(modelContext: ModelContext) async throws {
        var deletionSummary: [String] = []
        
        // 1. Delete all transactions (cascade will handle TransactionTagAssignment and TransactionContactAssignment)
        do {
            let transactionDescriptor = FetchDescriptor<PersistentTransaction>()
            let transactions = try modelContext.fetch(transactionDescriptor)
            
            let tagAssignmentCount = transactions.reduce(0) { $0 + ($1.tagAssignments?.count ?? 0) }
            let contactAssignmentCount = transactions.reduce(0) { $0 + ($1.contactAssignments?.count ?? 0) }
            
            for transaction in transactions {
                modelContext.delete(transaction)
            }
            
            deletionSummary.append("\(transactions.count) transactions")
            if tagAssignmentCount > 0 {
                deletionSummary.append("\(tagAssignmentCount) transaction-tag assignments")
            }
            if contactAssignmentCount > 0 {
                deletionSummary.append("\(contactAssignmentCount) transaction-contact assignments")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(transactions.count) transactions (cascade: \(tagAssignmentCount) tag assignments, \(contactAssignmentCount) contact assignments)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete transactions: \(error)")
            #endif
        }
        
        // 2. Delete all tags (cascade will handle any remaining TransactionTagAssignment)
        do {
            let tagDescriptor = FetchDescriptor<PersistentTag>()
            let tags = try modelContext.fetch(tagDescriptor)
            
            for tag in tags {
                modelContext.delete(tag)
            }
            
            if !tags.isEmpty {
                deletionSummary.append("\(tags.count) tags")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(tags.count) tags")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete tags: \(error)")
            #endif
        }
        
        // 3. Delete all contacts (cascade will handle PersistentContactAddress and any remaining TransactionContactAssignment)
        do {
            let contactDescriptor = FetchDescriptor<PersistentContact>()
            let contacts = try modelContext.fetch(contactDescriptor)
            
            let addressCount = contacts.reduce(0) { $0 + ($1.addresses?.count ?? 0) }
            
            for contact in contacts {
                modelContext.delete(contact)
            }
            
            if !contacts.isEmpty {
                deletionSummary.append("\(contacts.count) contacts")
            }
            if addressCount > 0 {
                deletionSummary.append("\(addressCount) contact addresses")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(contacts.count) contacts (cascade: \(addressCount) addresses)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete contacts: \(error)")
            #endif
        }
        
        // 4. Delete balance cache records
        do {
            // Delete Ark balance cache
            let arkBalanceDescriptor = FetchDescriptor<ArkBalanceModel>()
            let arkBalances = try modelContext.fetch(arkBalanceDescriptor)
            for balance in arkBalances {
                modelContext.delete(balance)
            }
            
            // Delete onchain balance cache
            let onchainBalanceDescriptor = FetchDescriptor<OnchainBalanceModel>()
            let onchainBalances = try modelContext.fetch(onchainBalanceDescriptor)
            for balance in onchainBalances {
                modelContext.delete(balance)
            }
            
            let totalBalances = arkBalances.count + onchainBalances.count
            if totalBalances > 0 {
                deletionSummary.append("\(totalBalances) balance cache records")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(arkBalances.count) Ark + \(onchainBalances.count) onchain balance cache records")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete balance cache: \(error)")
            #endif
        }
        
        // 5. Delete wallet configuration
        do {
            let configDescriptor = FetchDescriptor<WalletConfiguration>()
            let configs = try modelContext.fetch(configDescriptor)
            
            for config in configs {
                modelContext.delete(config)
            }
            
            if !configs.isEmpty {
                deletionSummary.append("\(configs.count) wallet configurations")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(configs.count) wallet configurations")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete wallet configurations: \(error)")
            #endif
        }
        
        // 6. Delete all device registrations
        do {
            let deviceDescriptor = FetchDescriptor<DeviceRegistration>()
            let devices = try modelContext.fetch(deviceDescriptor)
            
            for device in devices {
                modelContext.delete(device)
            }
            
            if !devices.isEmpty {
                deletionSummary.append("\(devices.count) device registrations")
            }
            
            #if DEBUG
            print("🗑️ [SecurityService] Deleted \(devices.count) device registrations")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SecurityService] Failed to delete device registrations: \(error)")
            #endif
        }
        
        // Save all deletions
        do {
            try modelContext.save()
            
            #if DEBUG
            print("✅ [SecurityService] Successfully deleted all wallet data from SwiftData/CloudKit:")
            print("   📦 Summary: \(deletionSummary.joined(separator: ", "))")
            #endif
        } catch {
            #if DEBUG
            print("❌ [SecurityService] Failed to save deletion changes: \(error)")
            #endif
            throw WalletError.unknown("Failed to delete cloud data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Hash Management (For Validation & Cross-Device Detection)
    
    /// Generates PBKDF2 hash of mnemonic for validation
    func hashMnemonic(_ mnemonic: String) -> String {
        let passwordData = Array(mnemonic.utf8)
        let saltData = Array(hashSalt.utf8)
        
        var derivedKeyData = Data(count: 32)
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData,
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(pbkdf2Iterations),
                    derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    32
                )
            }
        }
        
        guard derivationStatus == kCCSuccess else {
            // Fallback to simple hash if PBKDF2 fails
            var combinedData = Data()
            combinedData.append(contentsOf: mnemonic.utf8)
            combinedData.append(contentsOf: hashSalt.utf8)
            return SHA256.hash(data: combinedData)
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }
        
        return derivedKeyData.base64EncodedString()
    }
    
    /// Saves hash to NSUbiquitousKeyValueStore (syncs quickly via iCloud KVS)
    /// This enables fast cross-device wallet detection before SwiftData/CloudKit is initialized
    func saveHashToUbiquitousStore(_ mnemonic: String) {
        let hash = hashMnemonic(mnemonic)
        let store = NSUbiquitousKeyValueStore.default
        store.set(hash, forKey: ubiquitousHashKey)
        store.synchronize()
        
        #if DEBUG
        print("✅ [SecurityService] Saved hash to NSUbiquitousKeyValueStore at \(Date())")
        #endif
    }
    
    /// Gets hash from NSUbiquitousKeyValueStore (fast, works before SwiftData initialization)
    func getUbiquitousHash() -> String? {
        let hash = NSUbiquitousKeyValueStore.default.string(forKey: ubiquitousHashKey)
        
        #if DEBUG
        if let hash = hash {
            print("✅ [SecurityService] Retrieved hash from NSUbiquitousKeyValueStore: \(hash.prefix(8))...")
        } else {
            print("⚠️ [SecurityService] No hash found in NSUbiquitousKeyValueStore")
        }
        #endif
        
        return hash
    }
    
    /// Saves hash to SwiftData (syncs via CloudKit, keeps metadata together)
    /// **DEPRECATED:** This method is no longer used. Hash is only stored in NSUbiquitousKeyValueStore.
    /// Kept for backward compatibility but will be removed in a future version.
    @available(*, deprecated, message: "Use NSUbiquitousKeyValueStore via saveHashToUbiquitousStore() instead")
    func saveHashToStorage(_ mnemonic: String) async throws {
        guard let modelContext = modelContext else {
            throw WalletError.unknown("No model context available")
        }
        
        let hash = hashMnemonic(mnemonic)
        
        // Check if config already exists
        let descriptor = FetchDescriptor<WalletConfiguration>()
        let existing = try? modelContext.fetch(descriptor).first
        
        if let existing = existing {
            // Update existing
            existing.mnemonicHash = hash
            existing.lastAccessedAt = Date()
        } else {
            // Create new
            let config = WalletConfiguration(mnemonicHash: hash)
            modelContext.insert(config)
        }
        
        try modelContext.save()
        
        #if DEBUG
        print("✅ [SecurityService] Saved hash to SwiftData at \(Date())")
        #endif
    }
    
    /// Deletes hash from NSUbiquitousKeyValueStore
    func deleteHashFromUbiquitousStore() {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: ubiquitousHashKey)
        store.synchronize()
        
        #if DEBUG
        print("🗑️ [SecurityService] Deleted hash from NSUbiquitousKeyValueStore at \(Date())")
        #endif
    }
    
    /// Gets locally stored hash from SwiftData
    /// **DEPRECATED:** Hash is no longer stored in SwiftData. Use getUbiquitousHash() instead.
    @available(*, deprecated, message: "Use getUbiquitousHash() instead")
    func getLocalHash() -> String? {
        guard let modelContext = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<WalletConfiguration>()
        let config = try? modelContext.fetch(descriptor).first
        
        return config?.mnemonicHash
    }
    
    /// Gets reference hash from NSUbiquitousKeyValueStore (single source of truth)
    func getReferenceHash() async -> String? {
        return getUbiquitousHash()
    }
    
    /// Gets the wallet hash for device registration purposes
    /// This allows coordinators to register devices without SecurityService doing it directly
    /// - Returns: The wallet hash if available, or nil if no wallet exists
    func getWalletHashForRegistration() -> String? {
        return getUbiquitousHash()
    }
    
    // MARK: - Validation
    
    /// Validates imported mnemonic against stored hash
    func validateMnemonic(_ mnemonic: String) async -> MnemonicValidationResult {
        // 1. Check if it's valid BIP39 format
        guard isValidBIP39(mnemonic) else {
            return .invalidFormat
        }
        
        // 2. Try to get reference hash
        guard let referenceHash = await getReferenceHash() else {
            // No reference hash exists yet - this is OK for first import
            return .validNoReference
        }
        
        // 3. Compare hashes
        let importedHash = hashMnemonic(mnemonic)
        
        return importedHash == referenceHash ? .valid : .invalid
    }
    
    /// Validates BIP39 format (basic check - enhance as needed)
    func isValidBIP39(_ mnemonic: String) -> Bool {
        let words = mnemonic.components(separatedBy: " ")
        
        // Check word count (12, 15, 18, 21, or 24 words)
        guard [12, 15, 18, 21, 24].contains(words.count) else {
            return false
        }
        
        // All words should be non-empty and lowercase
        return words.allSatisfy { !$0.isEmpty }
    }
    
    // MARK: - Biometric Authentication
    
    /// Authenticates user with Face ID / Touch ID
    func authenticateUser(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw WalletError.biometricNotAvailable
        }
        
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            throw WalletError.authenticationFailed
        }
    }
    
    /// Checks if biometrics are available
    func biometricsAvailable() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}

// MARK: - Supporting Types

enum WalletState: Equatable {
    case unknown                // Initial state, not yet checked
    case noWallet              // No wallet exists anywhere
    case walletWithoutSeed     // CloudKit has data, but no local seed
    case walletWithSeed        // Full wallet with local seed
    case walletActiveElsewhere(deviceName: String)  // Wallet exists locally but device is not primary
}

enum MnemonicValidationResult {
    case valid                 // Matches reference hash
    case invalid               // Doesn't match reference hash
    case validNoReference      // Valid BIP39, but no reference to compare
    case invalidFormat         // Not valid BIP39 format
}

enum WalletError: LocalizedError {
    // Keychain errors
    case encodingFailed
    case keychainError(OSStatus)
    case mnemonicNotFound
    
    // Security errors
    case authenticationFailed
    case biometricNotAvailable
    
    // Validation errors
    case invalidMnemonic
    case mnemonicHashMismatch
    case invalidBIP39Words
    
    // Import/Export errors
    case qrCodeGenerationFailed
    case qrCodeScanningFailed
    case exportFailed
    
    // Sync errors
    case cloudKitNotAvailable
    case syncTimeout
    case networkUnavailable
    
    // General
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode recovery phrase"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .mnemonicNotFound:
            return "No recovery phrase found"
        case .authenticationFailed:
            return "Authentication failed"
        case .biometricNotAvailable:
            return "Face ID / Touch ID not available"
        case .invalidMnemonic:
            return "Invalid recovery phrase"
        case .mnemonicHashMismatch:
            return "Recovery phrase doesn't match your wallet"
        case .invalidBIP39Words:
            return "One or more words are not valid BIP39 words"
        case .qrCodeGenerationFailed:
            return "Failed to generate QR code"
        case .qrCodeScanningFailed:
            return "Failed to scan QR code"
        case .exportFailed:
            return "Failed to export wallet"
        case .cloudKitNotAvailable:
            return "iCloud is not available"
        case .syncTimeout:
            return "Sync is taking longer than expected"
        case .networkUnavailable:
            return "No internet connection"
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .keychainError:
            return "Try restarting the app or check system settings"
        case .mnemonicNotFound:
            return "You may need to import your recovery phrase"
        case .authenticationFailed:
            return "Please try again or check your biometric settings"
        case .biometricNotAvailable:
            return "Enable Face ID or Touch ID in Settings"
        case .invalidMnemonic, .invalidBIP39Words:
            return "Check your recovery phrase and try again"
        case .mnemonicHashMismatch:
            return "Make sure you're entering the correct recovery phrase for this wallet"
        case .networkUnavailable:
            return "Check your internet connection and try again"
        default:
            return nil
        }
    }
}
