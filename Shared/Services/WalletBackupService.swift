//
//  WalletBackupService.swift
//  Arké
//
//  Manages backup and restoration of the Bark wallet database to iCloud Drive
//
//  Created by Claude on 5/7/26.
//

import Foundation
import OSLog

/// Service for backing up and restoring wallet database to/from iCloud
class WalletBackupService {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "WalletBackup")
    
    private let walletDirectory: URL

    /// Live database filename as of bark 0.11
    nonisolated static let currentDatabaseFileName = "db.sqlite"
    /// Pre-0.11 filename; survives only in legacy iCloud backup artifacts
    nonisolated static let legacyDatabaseFileName = "bark.sqlite"

    private static let backupSubdirectory = "Backups"
    
    /// iCloud ubiquity container URL (nil if iCloud unavailable)
    private var ubiquityContainer: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    /// iCloud backup directory (nil if iCloud unavailable)
    private var backupDirectory: URL? {
        ubiquityContainer?.appendingPathComponent(Self.backupSubdirectory, isDirectory: true)
    }

    /// Existing iCloud backup artifact, preferring the current name over the legacy one
    private var existingBackupFile: URL? {
        backupDirectory.flatMap { Self.existingDatabaseURL(in: $0) }
    }

    /// Local wallet database file (current name)
    private var localDatabaseFile: URL {
        walletDirectory.appendingPathComponent(Self.currentDatabaseFileName)
    }
    
    // MARK: - Static Helpers for Device Migration

    /// First existing database file in a directory, preferring the current name
    private static func existingDatabaseURL(in directory: URL) -> URL? {
        for name in [currentDatabaseFileName, legacyDatabaseFileName] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// One-time normalization to the bark 0.11 database name.
    /// When `bark.sqlite` sits next to a live `db.sqlite`, `db.sqlite` wins,
    /// but the legacy file is archived rather than deleted: builds from the
    /// 0.11 transition window could create a fresh `db.sqlite` alongside a
    /// `bark.sqlite` that still holds the real pre-0.11 wallet state.
    static func migrateLegacyDatabaseFileIfNeeded() {
        let walletDirectory = getWalletDirectory()
        let legacyFile = walletDirectory.appendingPathComponent(legacyDatabaseFileName)
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return }

        let currentFile = walletDirectory.appendingPathComponent(currentDatabaseFileName)
        do {
            if FileManager.default.fileExists(atPath: currentFile.path) {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let archiveFile = walletDirectory.appendingPathComponent("\(legacyDatabaseFileName).archived-\(timestamp)")
                try FileManager.default.moveItem(at: legacyFile, to: archiveFile)
                logger.info("📦 Archived \(legacyDatabaseFileName) next to live \(currentDatabaseFileName) as \(archiveFile.lastPathComponent)")
            } else {
                try FileManager.default.moveItem(at: legacyFile, to: currentFile)
                logger.info("📦 Renamed legacy \(legacyDatabaseFileName) to \(currentDatabaseFileName)")
            }
        } catch {
            logger.error("❌ Failed to migrate legacy database file: \(error.localizedDescription)")
        }
    }

    /// Check if wallet database file exists locally
    /// Used to determine if restore from backup is needed during device migration
    /// - Returns: True if a wallet database (current or legacy name) exists in the wallet directory
    static func hasLocalWalletFile() -> Bool {
        let walletFile = existingDatabaseURL(in: getWalletDirectory())

        logger.debug("Wallet file exists check: \(walletFile != nil) (\(walletFile?.lastPathComponent ?? "no db file"))")
        return walletFile != nil
    }

    /// Get the modification date of the local wallet database file
    /// Used to compare with backup timestamps to determine which is newer
    /// - Returns: Modification date of the wallet database, or nil if file doesn't exist or error occurs
    static func getLocalWalletFileModificationDate() -> Date? {
        guard let walletFilePath = existingDatabaseURL(in: getWalletDirectory()) else {
            logger.debug("Local wallet file does not exist")
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: walletFilePath.path)
            let modificationDate = attributes[.modificationDate] as? Date

            logger.debug("Local wallet file modification date: \(modificationDate?.description ?? "unknown")")
            return modificationDate
        } catch {
            logger.warning("⚠️ Error getting local wallet file date: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Gets the wallet directory path (duplicated from BarkWalletFFI for static access)
    private static func getWalletDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        return appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GBKS.Arke")
            .appendingPathComponent("bark-data-ffi")
    }
    
    // MARK: - Initialization
    
    init(walletDirectory: URL) {
        self.walletDirectory = walletDirectory
        
        if ubiquityContainer != nil {
            Self.logger.info("✅ iCloud available for wallet backup")
        } else {
            Self.logger.warning("⚠️ iCloud not available - backups disabled")
        }
    }
    
    // MARK: - Backup Operations
    
    /// Performs a backup of the wallet database to iCloud
    /// - Returns: BackupResult indicating success, already up-to-date, or failure
    func performBackup() async -> BackupResult {
        guard ubiquityContainer != nil, let backupDir = backupDirectory else {
            Self.logger.debug("Backup skipped - iCloud unavailable")
            return .failed
        }

        // Check if source exists
        guard let sourceFile = Self.existingDatabaseURL(in: walletDirectory) else {
            Self.logger.debug("Backup skipped - database file not found in: \(self.walletDirectory.path)")
            
            // Log all files in wallet directory for debugging
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: walletDirectory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: []
                )
                Self.logger.debug("Wallet directory contains \(contents.count) items:")
                for item in contents {
                    let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    Self.logger.debug("  - \(item.lastPathComponent) (\(isDirectory ? "directory" : "file"), \(size) bytes)")
                }
            } catch {
                Self.logger.debug("Failed to list wallet directory contents: \(error.localizedDescription)")
            }
            
            return .failed
        }
        
        // Create backup directory if needed
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Create current backup file
        let currentBackup = backupDir.appendingPathComponent(Self.currentDatabaseFileName)
        
        // Check if backup already exists and is identical
        if FileManager.default.fileExists(atPath: currentBackup.path) {
            if await filesAreIdentical(sourceFile, currentBackup) {
                Self.logger.debug("Backup skipped - no changes detected")
                return .alreadyUpToDate
            }
        }
        
        do {
            // Remove old current backup
            if FileManager.default.fileExists(atPath: currentBackup.path) {
                try FileManager.default.removeItem(at: currentBackup)
            }
            
            // Copy database to iCloud
            try FileManager.default.copyItem(at: sourceFile, to: currentBackup)

            Self.logger.info("✅ Wallet backup completed")

            // A current-name backup now exists - the legacy artifact is obsolete
            let legacyBackup = backupDir.appendingPathComponent(Self.legacyDatabaseFileName)
            if FileManager.default.fileExists(atPath: legacyBackup.path) {
                try? FileManager.default.removeItem(at: legacyBackup)
                Self.logger.info("🧹 Removed legacy backup artifact \(Self.legacyDatabaseFileName)")
            }

            // Create timestamped backup for versioning
            await createTimestampedBackup(from: sourceFile, in: backupDir)

            return .success
            
        } catch {
            Self.logger.error("❌ Backup failed: \(error.localizedDescription)")
            return .failed
        }
    }
    
    /// Creates a timestamped backup and cleans up old ones
    private func createTimestampedBackup(from sourceFile: URL, in backupDir: URL) async {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let timestampedBackup = backupDir.appendingPathComponent("\(Self.currentDatabaseFileName).\(timestamp)")
        
        do {
            try FileManager.default.copyItem(at: sourceFile, to: timestampedBackup)
            Self.logger.debug("Created timestamped backup: \(timestamp)")
            
            // Clean up old backups (keep 5 most recent)
            await cleanupOldBackups(in: backupDir, keepCount: 5)
            
        } catch {
            Self.logger.warning("Failed to create timestamped backup: \(error.localizedDescription)")
        }
    }
    
    /// Removes old timestamped backups
    private func cleanupOldBackups(in directory: URL, keepCount: Int) async {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            // Filter timestamped backups only
            let timestampedBackups = files.filter { $0.lastPathComponent.hasPrefix("\(Self.currentDatabaseFileName).") }
            
            // Sort by creation date (newest first)
            let sortedBackups = try timestampedBackups.sorted { file1, file2 in
                let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                return date1 > date2
            }
            
            // Remove old backups
            for backup in sortedBackups.dropFirst(keepCount) {
                try FileManager.default.removeItem(at: backup)
                Self.logger.debug("Removed old backup: \(backup.lastPathComponent)")
            }
            
        } catch {
            Self.logger.warning("Failed to cleanup old backups: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Restore Operations
    
    /// Restores the wallet database from iCloud backup
    /// - Parameter overwriteExisting: If true, will overwrite existing database
    /// - Returns: Success status
    func restoreFromBackup(overwriteExisting: Bool = false) async -> Bool {
        guard ubiquityContainer != nil else {
            Self.logger.warning("Restore failed - iCloud unavailable")
            return false
        }

        // Check if backup exists (current name preferred, legacy artifact as fallback)
        guard let sourceBackup = existingBackupFile else {
            Self.logger.warning("Restore failed - no backup found")
            return false
        }

        // Always restore to the current name - it's the only file bark opens
        let destinationFile = localDatabaseFile
        
        // Check if destination exists
        if FileManager.default.fileExists(atPath: destinationFile.path) {
            guard overwriteExisting else {
                Self.logger.debug("Restore skipped - database exists and overwrite=false")
                return false
            }
            
            // Remove existing file
            do {
                try FileManager.default.removeItem(at: destinationFile)
            } catch {
                Self.logger.error("Failed to remove existing database: \(error.localizedDescription)")
                return false
            }
        }
        
        // Create wallet directory if needed
        try? FileManager.default.createDirectory(
            at: walletDirectory,
            withIntermediateDirectories: true
        )
        
        // Copy backup to wallet directory
        do {
            try FileManager.default.copyItem(at: sourceBackup, to: destinationFile)
            Self.logger.info("✅ Wallet database restored from backup")
            return true
        } catch {
            Self.logger.error("❌ Restore failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Restores wallet database from a user-selected backup file
    /// - Parameter sourceFileURL: URL of the backup file selected by user
    /// - Returns: Success status
    /// - Throws: Error if restoration fails
    func restoreFromUserBackup(sourceFileURL: URL) async throws -> Bool {
        let destinationFile = localDatabaseFile
        
        // Start accessing security-scoped resource (required for file picker selections)
        let accessGranted = sourceFileURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceFileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check if source file exists
        guard FileManager.default.fileExists(atPath: sourceFileURL.path) else {
            Self.logger.error("Backup file not found at: \(sourceFileURL.path)")
            throw BackupError.fileNotFound
        }
        
        // Basic validation: Check if it's a SQLite file by reading the header
        do {
            let fileHandle = try FileHandle(forReadingFrom: sourceFileURL)
            defer { try? fileHandle.close() }
            
            let headerData = fileHandle.readData(ofLength: 16)
            let sqliteHeader = "SQLite format 3\0".data(using: .utf8)
            
            guard headerData.prefix(16) == sqliteHeader else {
                Self.logger.error("Invalid backup file - not a SQLite database")
                throw BackupError.invalidFormat
            }
        } catch let error as BackupError {
            throw error
        } catch {
            Self.logger.error("Failed to validate backup file: \(error.localizedDescription)")
            throw BackupError.validationFailed(error.localizedDescription)
        }
        
        // Remove existing database if present
        if FileManager.default.fileExists(atPath: destinationFile.path) {
            do {
                try FileManager.default.removeItem(at: destinationFile)
                Self.logger.debug("Removed existing database file")
            } catch {
                Self.logger.error("Failed to remove existing database: \(error.localizedDescription)")
                throw BackupError.removalFailed(error.localizedDescription)
            }
        }
        
        // Create wallet directory if needed
        try? FileManager.default.createDirectory(
            at: walletDirectory,
            withIntermediateDirectories: true
        )
        
        // Copy backup to wallet directory
        do {
            try FileManager.default.copyItem(at: sourceFileURL, to: destinationFile)
            Self.logger.info("✅ Wallet database restored from user backup: \(sourceFileURL.lastPathComponent)")
            return true
        } catch {
            Self.logger.error("❌ Failed to copy backup file: \(error.localizedDescription)")
            throw BackupError.copyFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Status Checks
    
    /// Checks if a backup exists in iCloud
    func hasBackupAvailable() -> Bool {
        existingBackupFile != nil
    }

    /// Gets information about the backup
    func getBackupInfo() async -> BackupInfo? {
        guard let backupFile = existingBackupFile else { return nil }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: backupFile.path)
            let modificationDate = attributes[.modificationDate] as? Date
            let fileSize = attributes[.size] as? Int64
            
            return BackupInfo(
                lastBackupDate: modificationDate,
                fileSize: fileSize,
                isAvailable: true
            )
        } catch {
            Self.logger.warning("Failed to get backup info: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Gets the URL of the backup file for sharing/exporting
    func getBackupFileURL() -> URL? {
        existingBackupFile
    }

    /// Removes the restored database file (used for rollback during failed imports)
    /// This deletes the wallet database file from the wallet directory
    func removeRestoredDatabase() throws {
        let databaseFile = localDatabaseFile
        
        // Only remove if file exists
        guard FileManager.default.fileExists(atPath: databaseFile.path) else {
            Self.logger.debug("No database file to remove (rollback)")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: databaseFile)
            Self.logger.info("🗑️ Removed restored database file (rollback)")
        } catch {
            Self.logger.error("❌ Failed to remove database file during rollback: \(error.localizedDescription)")
            throw BackupError.removalFailed(error.localizedDescription)
        }
    }
    
    /// Removes every wallet backup artifact from the iCloud container
    /// (current, legacy, and timestamped copies). Used when the wallet is
    /// deleted permanently - a leftover backup would otherwise resurface
    /// via the restore-on-launch path after a new wallet is created.
    /// - Returns: True if all present artifacts were removed (or none existed)
    static func deleteAllBackups() -> Bool {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            logger.debug("Backup deletion skipped - iCloud unavailable")
            return false
        }

        let backupDir = container.appendingPathComponent(backupSubdirectory, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return true // No backup directory - nothing to delete
        }

        var allRemoved = true
        for file in files {
            let name = file.lastPathComponent
            let isBackupArtifact = name == currentDatabaseFileName
                || name == legacyDatabaseFileName
                || name.hasPrefix("\(currentDatabaseFileName).")
            guard isBackupArtifact else { continue }

            do {
                try FileManager.default.removeItem(at: file)
                logger.info("🗑️ Deleted iCloud backup artifact: \(name)")
            } catch {
                logger.error("❌ Failed to delete backup artifact \(name): \(error.localizedDescription)")
                allRemoved = false
            }
        }
        return allRemoved
    }

    /// Creates a temporary shareable copy of the backup file for export/sharing
    /// - Returns: URL of the temporary copy, or nil if backup unavailable
    func getShareableBackupFileURL() -> URL? {
        guard let backupFile = existingBackupFile else { return nil }

        // Create temp directory for shareable backup
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArkeBackups", isDirectory: true)
        
        // Create temp directory if needed
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let tempFileName = "arke-backup-\(timestamp).sqlite"
        let tempFile = tempDir.appendingPathComponent(tempFileName)
        
        // Remove old temp file if it exists
        if FileManager.default.fileExists(atPath: tempFile.path) {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Copy backup to temp location
        do {
            try FileManager.default.copyItem(at: backupFile, to: tempFile)
            Self.logger.debug("Created shareable backup at: \(tempFile.path)")
            return tempFile
        } catch {
            Self.logger.error("Failed to create shareable backup: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    /// Compares two files to see if they are identical
    private func filesAreIdentical(_ file1: URL, _ file2: URL) async -> Bool {
        do {
            let data1 = try Data(contentsOf: file1)
            let data2 = try Data(contentsOf: file2)
            return data1 == data2
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Types

enum BackupResult {
    case success           // Backup was performed
    case alreadyUpToDate   // No changes, already backed up
    case failed            // Error occurred
}

enum BackupError: LocalizedError {
    case fileNotFound
    case invalidFormat
    case validationFailed(String)
    case removalFailed(String)
    case copyFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Backup file not found"
        case .invalidFormat:
            return "Invalid backup file - not a SQLite database"
        case .validationFailed(let message):
            return "Failed to validate backup file: \(message)"
        case .removalFailed(let message):
            return "Failed to remove existing database: \(message)"
        case .copyFailed(let message):
            return "Failed to copy backup file: \(message)"
        }
    }
}

struct BackupInfo {
    let lastBackupDate: Date?
    let fileSize: Int64?
    let isAvailable: Bool
    
    var formattedDate: String {
        guard let date = lastBackupDate else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var formattedSize: String {
        guard let size = fileSize else { return "Unknown" }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
