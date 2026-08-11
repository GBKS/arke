//
//  WalletManager+Wallet.swift
//  Arké
//
//  Wallet lifecycle operations
//  Create, import, delete, and mnemonic management
//

import Foundation
import os

extension WalletManager {
    
    // MARK: - Mnemonic Management
    
    /// Get the wallet's mnemonic phrase from secure storage
    /// Biometric authentication is currently disabled
    func getMnemonic() async throws -> String {
        // Biometric authentication disabled for now
        // TODO: Re-enable biometric authentication when ready
        // let authenticated = try await securityService.authenticateUser(
        //     reason: "Access your wallet recovery phrase"
        // )
        //
        // guard authenticated else {
        //     throw BarkErrorArke.commandFailed("Authentication failed")
        // }
        
        // Load from secure keychain through SecurityService
        guard let mnemonic = try securityService.loadMnemonic() else {
            throw BarkErrorArke.commandFailed("Mnemonic not found in keychain")
        }
        
        return mnemonic
    }
    
    // MARK: - Wallet Import
    
    /// Import wallet with both recovery phrase and backup file
    /// This is the complete restoration flow that prevents data corruption
    /// - Parameters:
    ///   - mnemonic: The BIP39 mnemonic phrase
    ///   - backupFileURL: URL of the backup file selected by user
    ///   - networkConfig: Optional network configuration. If nil, uses wallet's current networkConfig.
    /// - Returns: Result message from wallet initialization
    func importWalletWithBackup(
        mnemonic: String,
        backupFileURL: URL,
        networkConfig: NetworkConfig? = nil
    ) async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMnemonic.isEmpty else {
            throw BarkErrorArke.commandFailed("Mnemonic phrase cannot be empty")
        }
        
        // Step 1: Validate the mnemonic using SecurityService
        let validation = await securityService.validateMnemonic(trimmedMnemonic)
        
        switch validation {
        case .valid:
            Self.logger.info("✅ Mnemonic is valid and matches existing wallet hash - recovering wallet")
            
        case .validNoReference:
            Self.logger.info("✅ Mnemonic is valid, proceeding with first-time import")
            
        case .invalid:
            throw BarkErrorArke.commandFailed("Invalid mnemonic phrase - doesn't match your wallet")
            
        case .invalidFormat:
            throw BarkErrorArke.commandFailed("Invalid mnemonic format - must be 12, 15, 18, 21, or 24 words")
        }
        
        // Track what we've done for rollback purposes
        var backupRestored = false
        var mnemonicSaved = false

        // Capture detection state before the import mutates it. saveMnemonic()
        // writes the wallet hash to iCloud KVS and sets the local-evidence
        // breadcrumb; if the import then fails, a leftover hash with no local
        // seed routes the next launch into read-only mode (walletActiveElsewhere).
        let preImportUbiquitousHash = securityService.getUbiquitousHash()
        let hadLocalWalletEvidence = SecurityService.hasLocalWalletEvidence()
        
        // Get services for rollback
        let walletDirectory = getWalletDirectory()
        let backupService = WalletBackupService(walletDirectory: walletDirectory)
        
        do {
            // Step 2: Restore backup file to wallet directory BEFORE wallet initialization
            // This is critical - the wallet must open with the correct database state
            Self.logger.info("📦 Restoring backup file from user selection...")
            
            let restored = try await backupService.restoreFromUserBackup(sourceFileURL: backupFileURL)
            if !restored {
                throw BarkErrorArke.commandFailed("Failed to restore backup file")
            }
            backupRestored = true
            Self.logger.info("✅ Backup file restored successfully")
            
            // Step 3: Save mnemonic to keychain
            try await securityService.handleSeedImport(trimmedMnemonic)
            mnemonicSaved = true
            Self.logger.info("✅ Mnemonic saved to keychain and device updated")
            
            // Step 4: Use provided networkConfig or fall back to wallet's current config
            let config = networkConfig ?? wallet.networkConfig
            
            // Step 5: Update the wallet's network configuration
            wallet.updateNetworkConfig(config)
            
            // Step 6: Import the wallet (it will now open the restored database).
            // A network mismatch here means the backup file belongs to another
            // network than the user selected - surface it, never wipe the restore.
            let result = try await wallet.importWallet(
                network: config.networkType,
                arkServer: config.arkServerBaseURL,
                mnemonic: trimmedMnemonic
            )
            
            // Step 7: Persist the network configuration
            NetworkConfigPersistence.save(config)
            
            isInitialized = true
            freshWalletOrigin = .imported
            Self.logger.info("🌱 Fresh wallet origin: imported (with backup) - transaction list shows skeleton until first sync completes")

            // Step 8: Register device after wallet import
            do {
                // Get wallet hash from ubiquitous store (set during mnemonic save)
                if let walletHash = securityService.getUbiquitousHash() {
                    let deviceService = ServiceContainer.shared.deviceRegistrationService
                    
                    // Register as device with seed access
                    try await deviceService.registerCurrentDevice(walletHash: walletHash, hasSeed: true)
                    Self.logger.info("✅ Device registered after wallet import")
                } else {
                    Self.logger.warning("⚠️ Could not get wallet hash for device registration")
                }
            } catch {
                Self.logger.warning("⚠️ Failed to register device (non-critical): \(error)")
                // Continue anyway - device registration can be retried
            }
            
            // Step 9: Start background progression services
            exitProgressionService?.start()
            roundProgressionService?.start()
            lightningClaimService?.start()
            
            // Step 10: Start wallet notification service
            if let transactionService = transactionService {
                walletNotificationService?.setTransactionService(transactionService)
                walletNotificationService?.start()
            }
            
            Self.logger.info("✅ Wallet imported successfully with backup restoration")
            
            return result
            
        } catch {
            // ROLLBACK: Clean up any partial state on failure
            Self.logger.error("❌ Import failed, rolling back changes: \(error.localizedDescription)")
            
            // Rollback Step 3: Remove mnemonic from keychain if it was saved
            if mnemonicSaved {
                Self.logger.info("🔄 Rolling back: Removing mnemonic from keychain...")
                do {
                    try await securityService.removeMnemonic()
                    Self.logger.info("✅ Rollback: Mnemonic removed")
                } catch {
                    Self.logger.error("⚠️ Rollback failed: Could not remove mnemonic: \(error.localizedDescription)")
                }

                // Restore the iCloud KVS hash and local-evidence breadcrumb that
                // saveMnemonic() wrote. Without this, the next launch finds a
                // wallet hash but no seed and enters read-only mode.
                if let previousHash = preImportUbiquitousHash {
                    securityService.restoreUbiquitousHash(previousHash)
                    Self.logger.info("✅ Rollback: Restored pre-import wallet hash to iCloud KVS")
                } else {
                    securityService.deleteHashFromUbiquitousStore()
                    Self.logger.info("✅ Rollback: Removed wallet hash from iCloud KVS")
                }

                if !hadLocalWalletEvidence {
                    SecurityService.clearLocalWalletEvidence()
                    Self.logger.info("✅ Rollback: Cleared local wallet evidence breadcrumb")
                }
            }
            
            // Rollback Step 2: Remove restored backup database if it was restored
            if backupRestored {
                Self.logger.info("🔄 Rolling back: Removing restored database...")
                do {
                    try backupService.removeRestoredDatabase()
                    Self.logger.info("✅ Rollback: Database removed")
                } catch {
                    Self.logger.error("⚠️ Rollback failed: Could not remove database: \(error.localizedDescription)")
                }
            }
            
            // Ensure wallet is not marked as initialized
            isInitialized = false
            
            Self.logger.info("✅ Rollback complete - import state cleaned up")
            
            // Re-throw the original error
            throw error
        }
    }
    
    /// Import an existing wallet using a mnemonic phrase
    /// Validates the mnemonic and saves it to secure storage
    /// - Parameters:
    ///   - mnemonic: The BIP39 mnemonic phrase to import
    ///   - networkConfig: Optional network configuration. If nil, uses wallet's current networkConfig.
    func importWallet(mnemonic: String, networkConfig: NetworkConfig? = nil) async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMnemonic.isEmpty else {
            throw BarkErrorArke.commandFailed("Mnemonic phrase cannot be empty")
        }
        
        // Validate the mnemonic using SecurityService
        let validation = await securityService.validateMnemonic(trimmedMnemonic)
        
        switch validation {
        case .valid:
            // Mnemonic matches hash in SwiftData - this is a recovery
            Self.logger.info("✅ Mnemonic is valid and matches existing wallet hash - recovering wallet")
            
        case .validNoReference:
            // Valid BIP39 but no reference hash exists - this is a first import
            Self.logger.info("✅ Mnemonic is valid, proceeding with first-time import")
            
        case .invalid:
            throw BarkErrorArke.commandFailed("Invalid mnemonic phrase - doesn't match your wallet")
            
        case .invalidFormat:
            throw BarkErrorArke.commandFailed("Invalid mnemonic format - must be 12, 15, 18, 21, or 24 words")
        }
        
        // Use provided networkConfig or fall back to wallet's current config
        let config = networkConfig ?? wallet.networkConfig

        // Update the wallet's network configuration BEFORE importing: the FFI
        // derives its esplora URL from the stored config, so importing first
        // pairs the new network with the old network's esplora endpoint
        wallet.updateNetworkConfig(config)

        // Import the wallet. Seed-only import: leftover wallet data from another
        // network is stale (nothing restored it deliberately - common on macOS,
        // where the container survives app reinstalls), and data from another
        // network cannot be the wallet being imported, so wipe it and retry
        // once; the fresh creating open recovers funds via the seed-recovery
        // scan. importWalletWithBackup deliberately does NOT do this: there a
        // mismatch means the user picked the wrong network for their backup
        // file and needs to see the error, not lose the restored copy.
        let result: String
        do {
            result = try await wallet.importWallet(
                network: config.networkType,
                arkServer: config.arkServerBaseURL,
                mnemonic: trimmedMnemonic
            )
        } catch BarkWalletFFIError.networkMismatch(let message) {
            Self.logger.warning("⚠️ Existing wallet data belongs to another network (\(message)) - wiping stale data and retrying import")
            try? await Task.sleep(nanoseconds: 500_000_000) // let Rust release sqlite handles
            try? FileManager.default.removeItem(at: wallet.walletDir)
            // Not caught again: a second mismatch surfaces as an error
            result = try await wallet.importWallet(
                network: config.networkType,
                arkServer: config.arkServerBaseURL,
                mnemonic: trimmedMnemonic
            )
        }

        // Persist the network configuration so it's restored on next app launch
        NetworkConfigPersistence.save(config)
        
        // Save mnemonic to keychain and update device registration
        // Note: This also saves hash to NSUbiquitousKeyValueStore for cross-device detection
        do {
            try await securityService.handleSeedImport(trimmedMnemonic)
            Self.logger.info("✅ Mnemonic saved to keychain and device updated")
        } catch {
            Self.logger.error("⚠️ Failed to save mnemonic to keychain: \(error)")
            throw BarkErrorArke.commandFailed("Failed to secure mnemonic: \(error.localizedDescription)")
        }
        
        isInitialized = true
        freshWalletOrigin = .imported
        Self.logger.info("🌱 Fresh wallet origin: imported - transaction list shows skeleton until first sync completes")

        // Register device after wallet import (handleSeedImport saves the mnemonic
        // but leaves device registration to the coordinator)
        do {
            if let walletHash = securityService.getUbiquitousHash() {
                let deviceService = ServiceContainer.shared.deviceRegistrationService
                try await deviceService.registerCurrentDevice(walletHash: walletHash, hasSeed: true)
                Self.logger.info("✅ Device registered after wallet import")
            } else {
                Self.logger.warning("⚠️ Could not get wallet hash for device registration")
            }
        } catch {
            Self.logger.warning("⚠️ Failed to register device (non-critical): \(error)")
            // Continue anyway - device registration can be retried
        }

        // Start background progression services for imported wallet
        exitProgressionService?.start()
        roundProgressionService?.start()
        lightningClaimService?.start()
        
        // Start wallet notification service
        if let transactionService = transactionService {
            walletNotificationService?.setTransactionService(transactionService)
            walletNotificationService?.start()
        }
        
        return result
    }
    
    // MARK: - Wallet Creation
    
    /// Create a new wallet with a randomly generated mnemonic
    /// Saves the mnemonic to secure storage and syncs hash via iCloud KVS
    /// - Parameters:
    ///   - networkConfig: Optional network configuration. If nil, uses wallet's current networkConfig.
    func createWallet(networkConfig: NetworkConfig? = nil) async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        let overallStartTime = CFAbsoluteTimeGetCurrent()
        Self.logger.info("⏱️ [PROFILE] Starting wallet creation")
        Self.logger.debug("WalletManager.createWallet name: \(networkConfig?.name ?? "none")")
        Self.logger.debug("WalletManager.createWallet arkServerBaseURL: \(networkConfig?.arkServerBaseURL ?? "none")")
        Self.logger.debug("WalletManager.createWallet esploraBaseURL: \(networkConfig?.esploraBaseURL ?? "none")")
        
        // Execute creation through task manager for deduplication
        return try await taskManager.execute(key: "createWallet") {
            var stepStartTime = CFAbsoluteTimeGetCurrent()
            
            // Use provided networkConfig or fall back to wallet's current config
            let config = networkConfig ?? wallet.networkConfig
            
            // Update the wallet's network configuration to match what was actually created
            wallet.updateNetworkConfig(config)
            
            // Persist the network configuration so it's restored on next app launch
            NetworkConfigPersistence.save(config)
            
            Self.logger.info("⏱️ [PROFILE] Config setup took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - stepStartTime))s")
            
            // FFI wallet creation (mnemonic generation + Rust wallet setup)
            stepStartTime = CFAbsoluteTimeGetCurrent()
            let mnemonic = try await wallet.createWallet(
                network: config.networkType,
                arkServer: config.arkServerBaseURL
            )
            let walletCreationTime = CFAbsoluteTimeGetCurrent() - stepStartTime
            Self.logger.info("⏱️ [PROFILE] FFI wallet.createWallet() took \(String(format: "%.3f", walletCreationTime))s")
            Self.logger.info("✅ New wallet created successfully on \(config.name)")
            
            // Save mnemonic to keychain (this also saves hash to NSUbiquitousKeyValueStore)
            stepStartTime = CFAbsoluteTimeGetCurrent()
            do {
                try await self.securityService.saveMnemonic(mnemonic)
                let keychainTime = CFAbsoluteTimeGetCurrent() - stepStartTime
                Self.logger.info("⏱️ [PROFILE] securityService.saveMnemonic() took \(String(format: "%.3f", keychainTime))s")
                Self.logger.info("✅ Mnemonic saved to keychain and hash synced via iCloud KVS")
            } catch {
                Self.logger.error("⚠️ Failed to save mnemonic to keychain: \(error)")
                throw BarkErrorArke.commandFailed("Failed to secure mnemonic: \(error.localizedDescription)")
            }
            
            self.isInitialized = true
            self.freshWalletOrigin = .created
            Self.logger.info("🌱 Fresh wallet origin: created - transaction list will skip the initial-sync skeleton")

            // Start background progression services for new wallet
            stepStartTime = CFAbsoluteTimeGetCurrent()
            self.exitProgressionService?.start()
            self.roundProgressionService?.start()
            self.lightningClaimService?.start()
            
            // Start wallet notification service
            if let transactionService = self.transactionService {
                self.walletNotificationService?.setTransactionService(transactionService)
                self.walletNotificationService?.start()
            }
            let servicesTime = CFAbsoluteTimeGetCurrent() - stepStartTime
            Self.logger.info("⏱️ [PROFILE] Service initialization took \(String(format: "%.3f", servicesTime))s")
            
            let totalTime = CFAbsoluteTimeGetCurrent() - overallStartTime
            Self.logger.info("⏱️ [PROFILE] Total wallet creation took \(String(format: "%.3f", totalTime))s")
            
            return mnemonic
        }
    }
    
    // MARK: - Wallet Closing
    
    /// Close the current wallet without deleting it
    /// Shuts down all services and clears state, but preserves wallet files on disk
    /// Useful for device migration or switching wallets without deletion
    func closeWallet() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        Self.logger.info("🔒 [WalletManager] Closing wallet...")
        
        // Step 1: Reset manager state (stops services, clears caches)
        Self.logger.debug("   Step 1: Resetting manager state...")
        await resetManagerState()
        
        // Step 2: Unregister from push notifications
        #if os(iOS)
        Self.logger.debug("   Step 2: Unregistering from push notifications...")
        await unregisterFromPushNotifications()
        #endif
        
        // Step 3: Give services time to settle
        Self.logger.debug("   Step 3: Waiting for services to settle...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Step 4: Shutdown wallet (FFI cleanup, backup, resource release)
        Self.logger.debug("   Step 4: Shutting down wallet FFI...")
        if let ffiWallet = wallet as? BarkWalletFFI {
            await ffiWallet.shutdownWallet()
        } else {
            // Mock wallet - just clear the reference
            Self.logger.debug("   Mock wallet detected - skipping FFI shutdown")
        }
        
        Self.logger.info("✅ Wallet closed successfully")
    }
    
    // MARK: - Wallet Deletion
    
    /// Delete the current wallet and reset all manager state
    /// Note: Mnemonic deletion is handled separately by the caller (DeleteWalletSettingView)
    /// to allow for intelligent deletion strategies based on device registry
    func deleteWallet() async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        // Execute deletion through task manager for deduplication
        return try await taskManager.execute(key: "deleteWallet") {
            Self.logger.info("🗑️ [WalletManager] Starting wallet deletion...")
            
            // ✅ NEW: Reset manager state FIRST to prevent any operations during deletion
            Self.logger.debug("   Step 1: Resetting manager state...")
            await self.resetManagerState()
            
            // ✅ Unregister from push notifications before deletion
            #if os(iOS)
            Self.logger.debug("   Step 2: Unregistering from push notifications...")
            await self.unregisterFromPushNotifications()
            #endif
            
            // ✅ NEW: Give services time to release any resources
            Self.logger.debug("   Step 3: Waiting for services to settle...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Now delete the wallet (this handles FFI cleanup internally)
            Self.logger.debug("   Step 4: Deleting wallet files...")
            let result = try await wallet.deleteWallet()
            
            // Clear the saved network configuration
            Self.logger.debug("   Step 5: Clearing saved network configuration...")
            NetworkConfigPersistence.clear()

            // Clear the local wallet evidence breadcrumb (files are gone; the caller
            // handles mnemonic deletion, which clears it again - harmless)
            SecurityService.clearLocalWalletEvidence()
            
            // Note: Mnemonic deletion is now handled by the caller (DeleteWalletSettingView)
            // This allows for intelligent deletion strategies based on device registry
            
            Self.logger.info("✅ Wallet deleted and manager state reset")
            return result
        }
    }
    
    // MARK: - Private Helpers
    
    /// Gets the wallet directory path
    private func getWalletDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        return appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GBKS.Arke")
            .appendingPathComponent("bark-data-ffi")
    }
    
    /// Reset all manager and service state after wallet deletion
    /// Clears all cached data, stops background services, and resets flags
    private func resetManagerState() async {
        // Stop all background services
        exitProgressionService?.stop()
        roundProgressionService?.stop()
        vtxoRefreshService?.stop()
        lightningClaimService?.stop()
        walletNotificationService?.stop()
        
        // Reset coordinator state
        isInitialized = false
        error = nil
        isRefreshing = false
        hasLoadedOnce = false
        freshWalletOrigin = nil
        hasEverSyncedSuccessfully = false
        UserDefaults.standard.removeObject(forKey: UserDefaults.initialSyncCompletedKey)

        // Reset balance service state
        balanceService?.arkBalance = nil
        balanceService?.onchainBalance = nil
        balanceService?.totalBalance = nil
        balanceService?.error = nil
        
        // Reset transaction service state (clear transactions)
        await transactionService?.clearTransactionModels()
        transactionService?.error = nil
        transactionService?.hasLoadedTransactions = false

        // Reset address service state
        addressService?.arkAddress = ""
        addressService?.onchainAddress = ""
        addressService?.error = nil

        // Clear persisted balance data (full deletion for wallet removal)
        balanceService?.resetBalancesAndDeletePersisted()

        // Clear in-memory exit state (persistent exit history is cleared by
        // WalletDataCleanupService during wallet deletion)
        exitStore.clear()
        
        Self.logger.info("🔄 All manager and service state reset")
    }
    
    /// Lightweight reset for device migration - stops services but preserves SwiftData
    /// This is used when demoting from primary to secondary device
    /// We want to close the wallet file but keep transaction history, tags, and contacts
    /// Internal access to allow calling from WalletManager.swift
    func resetManagerStateForMigration() async {
        Self.logger.info("🔄 [WalletManager] Resetting state for migration (preserving SwiftData)...")
        
        // Stop all background services
        exitProgressionService?.stop()
        roundProgressionService?.stop()
        vtxoRefreshService?.stop()
        lightningClaimService?.stop()
        walletNotificationService?.stop()
        
        // Reset coordinator state
        isInitialized = false
        error = nil
        isRefreshing = false
        hasLoadedOnce = false
        freshWalletOrigin = nil

        // DON'T reset balance service state - secondary device needs to display balances
        // The ReadOnlyBalanceService will take over and use the existing in-memory data
        // or reload from SwiftData/CloudKit if needed
        
        // Reset transaction service state (in-memory only - DO NOT clear SwiftData)
        transactionService?.error = nil
        transactionService?.hasLoadedTransactions = false
        
        // DON'T reset address service state - secondary device needs to display addresses
        // The ReadOnlyAddressService will load addresses from SwiftData/CloudKit
        // Addresses are just display strings for receiving, no wallet needed
        addressService?.error = nil
        
        // Note: We deliberately preserve:
        // - Balance data (balances display via ReadOnlyBalanceService from CloudKit)
        // - Address data (addresses display via ReadOnlyAddressService from CloudKit)
        // - Transaction data (already in SwiftData, synced via CloudKit)
        // - Tags and contacts (managed by ServiceContainer, synced via CloudKit)
        // Secondary devices are just viewers - they need all this data to display properly
        
        Self.logger.info("🔄 Manager state reset for migration (SwiftData preserved, display data retained)")
    }
}
