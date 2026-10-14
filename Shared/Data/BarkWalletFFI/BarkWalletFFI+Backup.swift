//
//  BarkWalletFFI+Backup.swift
//  Arké
//
//  Wallet backup and restoration operations
//  Provides integration between BarkWalletFFI and WalletBackupService
//
//  Created by Claude on 5/7/26.
//

import Foundation
import OSLog

extension BarkWalletFFI {
    
    // MARK: - Backup Operations
    
    /// Performs an immediate backup of the wallet database to iCloud. This is
    /// the opportunistic entry point (app background hook, manual button); it
    /// is refused while a wallet deletion runs, because the full wipe empties
    /// the backup slot several seconds before the handle is cleared and a
    /// backup in that window would refill it with the database being deleted
    /// (Launch_Sequence_Contract rule 17).
    /// - Returns: BackupResult indicating success, already up-to-date, or failure
    @discardableResult
    func backupWallet() async -> BackupResult {
        guard !opportunisticBackupsSuspended else {
            Self.logger.notice("Backup skipped - wallet deletion in progress")
            return .failed
        }
        return await runBackupNow()
    }

    /// The backup itself, without the deletion suspension. Used by
    /// `shutdownWallet(backingUp: true)` so a local-only deletion still writes
    /// its final backup (the copy a promoted secondary restores from).
    @discardableResult
    func runBackupNow() async -> BackupResult {
        guard !isPreview else {
            return .failed
        }

        guard wallet != nil else {
            Self.logger.debug("Backup skipped - wallet not initialized")
            return .failed
        }

        let backupService = WalletBackupService(walletDirectory: walletDir)
        return await backupService.performBackup()
    }
    
    // MARK: - Restore Operations
    
    /// Checks if an iCloud backup is available for restoration
    /// - Returns: True if backup exists in iCloud
    func hasBackupAvailable() -> Bool {
        guard !isPreview else {
            return false
        }
        
        let backupService = WalletBackupService(walletDirectory: walletDir)
        return backupService.hasBackupAvailable()
    }
    
    /// Gets information about the available backup
    /// - Returns: Backup metadata if available
    func getBackupInfo() async -> BackupInfo? {
        guard !isPreview else {
            return nil
        }
        
        let backupService = WalletBackupService(walletDirectory: walletDir)
        return await backupService.getBackupInfo()
    }
    
    /// Gets the URL of the backup file for sharing/exporting
    /// - Returns: URL of the backup file if available
    func getBackupFileURL() -> URL? {
        guard !isPreview else {
            return nil
        }
        
        let backupService = WalletBackupService(walletDirectory: walletDir)
        return backupService.getBackupFileURL()
    }
    
    /// Creates a temporary shareable copy of the backup file for export/sharing
    /// - Returns: URL of the temporary shareable copy if available
    func getShareableBackupFileURL() -> URL? {
        guard !isPreview else {
            return nil
        }
        
        let backupService = WalletBackupService(walletDirectory: walletDir)
        return backupService.getShareableBackupFileURL()
    }
    
    /// Restores wallet database from iCloud backup
    /// WARNING: This will shutdown the current wallet and replace the database
    /// - Returns: Success status
    @discardableResult
    func restoreWalletFromBackup() async throws -> Bool {
        guard !isPreview else {
            return false
        }
        
        Self.logger.info("Starting wallet restoration from iCloud backup")
        
        // Shutdown current wallet if running
        if wallet != nil {
            Self.logger.debug("Shutting down wallet before restore")
            await shutdownWallet()
        }
        
        // Restore database
        let backupService = WalletBackupService(walletDirectory: walletDir)
        let restored = await backupService.restoreFromBackup(overwriteExisting: true)
        
        guard restored else {
            throw BarkWalletFFIError.configurationError("Failed to restore database from backup")
        }
        
        Self.logger.info("✅ Wallet database restored from backup")
        return true
    }
}
