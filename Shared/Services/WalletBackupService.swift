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
    /// Where a restore parks the database it replaces until the open that
    /// follows either succeeds (`discardPreservedDatabase`) or fails
    /// (`rollBackUserBackupRestore` puts it back). Both restores park:
    /// `restoreFromUserBackup` (range review 2026-11-16, I1: a replaced
    /// database was removed outright, so a failed import left no database
    /// at all) and the slot restore `restoreFromBackup(overwriteExisting:)`
    /// (same review, D2: a slot refilled by a live, unlinked primary replaced
    /// a newer local database with no copy kept).
    nonisolated static let preservedDatabaseFileName = "db.sqlite.pre-import"
    /// Written beside a slot restore's parked database until the open that
    /// follows confirms the copy (`discardPreservedDatabase`) or rejects it
    /// (`rollBackUserBackupRestore`). A launch that finds it still there was
    /// killed between the copy and the open; the parked file is this device's
    /// database and goes back before anything opens or compares (adversarial
    /// pass 2026-11-17 on the D2 fix, F1).
    nonisolated static let pendingSlotRestoreMarkerFileName = "db.sqlite.slot-restore-pending"
    /// Pre-0.11 filename; survives only in legacy iCloud backup artifacts
    nonisolated static let legacyDatabaseFileName = "bark.sqlite"

    private static let backupSubdirectory = "Backups"

    /// Test seam: a slot directory standing in for the iCloud container, so
    /// the slot restore can run where no ubiquity container exists
    private let backupDirectoryOverride: URL?
    
    /// iCloud ubiquity container URL (nil if iCloud unavailable)
    private var ubiquityContainer: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    /// iCloud backup directory (nil if iCloud unavailable)
    private var backupDirectory: URL? {
        backupDirectoryOverride ?? ubiquityContainer?.appendingPathComponent(Self.backupSubdirectory, isDirectory: true)
    }

    /// Existing iCloud backup artifact, preferring the current name over the legacy one
    private var existingBackupFile: URL? {
        backupDirectory.flatMap { Self.existingDatabaseURL(in: $0) }
    }

    /// Local wallet database file (current name)
    private var localDatabaseFile: URL {
        walletDirectory.appendingPathComponent(Self.currentDatabaseFileName)
    }

    /// The database `restoreFromUserBackup` replaced, kept until the import's outcome
    private var preservedDatabaseFile: URL {
        walletDirectory.appendingPathComponent(Self.preservedDatabaseFileName)
    }

    /// bark runs SQLite in rollback-journal mode (no pragma set at bark-0.8.0),
    /// so a hot journal can sit beside the database after a crash; it is
    /// parked and put back together with the database, or the put-back copy
    /// would lose that transaction's rollback
    private var journalFile: URL { walletDirectory.appendingPathComponent(Self.currentDatabaseFileName + "-journal") }
    private var preservedJournalFile: URL { walletDirectory.appendingPathComponent(Self.preservedDatabaseFileName + "-journal") }
    private var pendingSlotRestoreMarker: URL { walletDirectory.appendingPathComponent(Self.pendingSlotRestoreMarkerFileName) }

    /// A parked database no running restore owns, i.e. this device's own
    /// database stranded by a process kill: either no live database sits
    /// beside it (killed between park and copy, any restore) or a slot
    /// restore's copy was never confirmed by an open (marker still present,
    /// killed between copy and open). A backup-file import's parked database
    /// with a live one beside it is NOT stranded: the import owns it until
    /// its own rollback or discard. Callers put a stranded database back with
    /// `rollBackUserBackupRestore` before anything opens or compares.
    var hasStrandedParkedDatabase: Bool {
        let parked = FileManager.default.fileExists(atPath: preservedDatabaseFile.path)
        guard parked else { return false }
        return !FileManager.default.fileExists(atPath: localDatabaseFile.path)
            || FileManager.default.fileExists(atPath: pendingSlotRestoreMarker.path)
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
    
    init(walletDirectory: URL, backupDirectory: URL? = nil) {
        self.walletDirectory = walletDirectory
        self.backupDirectoryOverride = backupDirectory
        
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
                // The slot is current. Still stamp it: the handover watches the
                // slot's modification date as "a backup pass completed at T",
                // and an idle wallet's final backup must count even when its
                // bytes did not change (Device_Linking.md §14.3)
                Self.stampBackupTime(currentBackup)
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

            // copyItem preserves the source's modification date, which is the
            // database's last write, not the backup time. The slot's date must
            // mean "backed up at T": the handover compares it with the old
            // primary's demotion time, and `restoreWalletIfNeeded` guards the
            // self-restore this would otherwise cause with an identity check.
            Self.stampBackupTime(currentBackup)

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
    
    /// Restores the wallet database from the account's iCloud backup slot.
    /// An existing local database is parked, never removed: the caller
    /// (`WalletManager.restoreWalletIfNeeded`) opens the restored copy next
    /// and puts the parked one back with `rollBackUserBackupRestore` if that
    /// open fails, or drops it with `discardPreservedDatabase` once it
    /// succeeded (range review 2026-11-16, D2).
    /// - Parameter overwriteExisting: If true, an existing database is parked and replaced
    /// - Returns: Success status
    func restoreFromBackup(overwriteExisting: Bool = false) async -> Bool {
        guard backupDirectory != nil else {
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
        
        if FileManager.default.fileExists(atPath: destinationFile.path), !overwriteExisting {
            Self.logger.debug("Restore skipped - database exists and overwrite=false")
            return false
        }

        // A parked file still present here belongs to a backup-file import in
        // flight (a stranded one was put back by the caller's pre-open guard):
        // the slot restore must not clear it, so it refuses instead
        let parkedExisting: Bool
        do {
            parkedExisting = try parkLiveDatabase(clearingStaleParkedFile: false)
        } catch {
            Self.logger.error("Failed to park the existing database: \(error.localizedDescription)")
            return false
        }
        if parkedExisting {
            // Marks the parked database as this device's until the copy opens;
            // cleared by the rollback or the discard, never by the copy alone
            FileManager.default.createFile(atPath: pendingSlotRestoreMarker.path, contents: nil)
        }
        
        // Create wallet directory if needed
        try? FileManager.default.createDirectory(
            at: walletDirectory,
            withIntermediateDirectories: true
        )
        
        // Copy backup to wallet directory
        do {
            try FileManager.default.copyItem(at: sourceBackup, to: destinationFile)
            Self.logger.info("✅ Wallet database restored from backup\(parkedExisting ? " (previous database parked until it opens)" : "")")
            return true
        } catch {
            Self.logger.error("❌ Restore failed: \(error.localizedDescription)")
            if parkedExisting {
                putParkedDatabaseBackAfterFailedCopy()
            }
            return false
        }
    }

    /// Moves the live database, and its hot journal if any, under the parked
    /// name. Returns whether there was a database to park.
    ///
    /// - Parameter clearingStaleParkedFile: the backup-file import passes
    ///   `true`: a parked file from an earlier, interrupted attempt belongs to
    ///   no one and is cleared first, whether or not a live database exists,
    ///   so a later rollback can only ever put back what this attempt parked.
    ///   The slot restore passes `false`: after its caller's stranded put-back,
    ///   a parked file still present is owned by an import in flight, and
    ///   the restore throws rather than clear it (adversarial pass
    ///   2026-11-17 on the D2 fix, second round, F5).
    private func parkLiveDatabase(clearingStaleParkedFile: Bool) throws -> Bool {
        if clearingStaleParkedFile {
            try? FileManager.default.removeItem(at: preservedDatabaseFile)
            try? FileManager.default.removeItem(at: preservedJournalFile)
            try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
        } else if FileManager.default.fileExists(atPath: preservedDatabaseFile.path) {
            throw BackupError.removalFailed("a parked database is still owned by a running import")
        }
        guard FileManager.default.fileExists(atPath: localDatabaseFile.path) else { return false }
        try FileManager.default.moveItem(at: localDatabaseFile, to: preservedDatabaseFile)
        if FileManager.default.fileExists(atPath: journalFile.path) {
            try FileManager.default.moveItem(at: journalFile, to: preservedJournalFile)
        }
        Self.logger.info("Existing database parked as \(Self.preservedDatabaseFileName) until the restored copy opens")
        return true
    }

    /// Undoes `parkLiveDatabase` when the copy that was to replace the parked
    /// database failed: the caller's rollback runs only after a successful
    /// restore, and the previous database must not be left under the parked
    /// name where no reader finds it (adversarial pass 2026-11-17, F1)
    private func putParkedDatabaseBackAfterFailedCopy() {
        try? FileManager.default.removeItem(at: localDatabaseFile)  // a partial copy, if any
        do {
            try FileManager.default.moveItem(at: preservedDatabaseFile, to: localDatabaseFile)
            if FileManager.default.fileExists(atPath: preservedJournalFile.path) {
                try? FileManager.default.moveItem(at: preservedJournalFile, to: journalFile)
            }
            // The marker goes only once the move it protects has happened
            try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
            Self.logger.info("↩️ Previous database put back after the failed copy")
        } catch {
            Self.logger.error("❌ Could not put the previous database back after the failed copy: \(error.localizedDescription)")
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
        
        // Park the existing database instead of removing it: the import that
        // follows can still fail (another phrase, network or server mismatch,
        // keychain), and the file being replaced may be the only copy of a
        // wallet's offchain state (the launch-check restore exit). Rolled
        // back by `rollBackUserBackupRestore`, dropped by
        // `discardPreservedDatabase` once the import succeeded.
        let parkedExisting: Bool
        do {
            parkedExisting = try parkLiveDatabase(clearingStaleParkedFile: true)
        } catch {
            Self.logger.error("Failed to park the existing database: \(error.localizedDescription)")
            throw BackupError.removalFailed(error.localizedDescription)
        }
        
        // Create wallet directory if needed
        try? FileManager.default.createDirectory(
            at: walletDirectory,
            withIntermediateDirectories: true
        )
        
        // Copy backup to wallet directory. A failed copy undoes the park itself
        do {
            try FileManager.default.copyItem(at: sourceFileURL, to: destinationFile)
            Self.logger.info("✅ Wallet database restored from user backup: \(sourceFileURL.lastPathComponent)")
            return true
        } catch {
            Self.logger.error("❌ Failed to copy backup file: \(error.localizedDescription)")
            if parkedExisting {
                putParkedDatabaseBackAfterFailedCopy()
            }
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

    /// Rollback of `restoreFromUserBackup` and of the slot restore: the
    /// restored copy goes, and the database it replaced, if any, comes back
    /// under its own name.
    func rollBackUserBackupRestore() throws {
        let databaseFile = localDatabaseFile
        let restoredExists = FileManager.default.fileExists(atPath: databaseFile.path)
        let parkedExists = FileManager.default.fileExists(atPath: preservedDatabaseFile.path)

        // Putting the previous database back does not depend on a separate
        // removal succeeding first: the replace is one step when both exist
        if parkedExists {
            do {
                if restoredExists {
                    _ = try FileManager.default.replaceItemAt(databaseFile, withItemAt: preservedDatabaseFile)
                } else {
                    try FileManager.default.moveItem(at: preservedDatabaseFile, to: databaseFile)
                }
                // The restored copy's own journal, if any, belongs to the file
                // that just went away; the parked journal to the one coming back
                try? FileManager.default.removeItem(at: journalFile)
                if FileManager.default.fileExists(atPath: preservedJournalFile.path) {
                    try? FileManager.default.moveItem(at: preservedJournalFile, to: journalFile)
                }
                // The marker goes only once the move it protects has happened,
                // so a kill in between still reads as stranded next launch
                try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
                Self.logger.info("↩️ Previous database put back after the failed import")
            } catch {
                Self.logger.error("❌ Failed to put the previous database back: \(error.localizedDescription)")
                throw BackupError.copyFailed(error.localizedDescription)
            }
            return
        }

        // Nothing parked: a marker without a parked file protects nothing
        try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
        guard restoredExists else {
            Self.logger.debug("No restored database file to remove (rollback)")
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

    /// The restored copy opened: the parked previous database is no longer needed
    func discardPreservedDatabase() {
        try? FileManager.default.removeItem(at: preservedJournalFile)
        guard FileManager.default.fileExists(atPath: preservedDatabaseFile.path) else {
            try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
            return
        }
        do {
            try FileManager.default.removeItem(at: preservedDatabaseFile)
            try? FileManager.default.removeItem(at: pendingSlotRestoreMarker)
            Self.logger.info("🗑️ Discarded the previous database after the restored copy opened")
        } catch {
            Self.logger.warning("Could not discard the parked previous database: \(error.localizedDescription)")
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

    /// Creates a temporary shareable copy of the iCloud backup file for export/sharing
    /// - Returns: URL of the temporary copy, or nil if backup unavailable
    func getShareableBackupFileURL() -> URL? {
        guard let backupFile = existingBackupFile else { return nil }
        return shareableCopy(of: backupFile)
    }

    /// A temporary shareable copy of the wallet database for the export step
    /// of a full wipe: the newer of the live local file and the iCloud
    /// backup file, by modification date, the local file on a tie or when
    /// a date cannot be read. On an open primary that is the live file,
    /// which may postdate the slot by a payment and needs no iCloud. On a
    /// demoted device the local file is frozen at demotion while the
    /// promoted device keeps writing the slot, so the slot wins there
    /// (review 2026-11-12; the same newest-wins rule the launch restore
    /// applies). A secondary that never opened a wallet has only the slot.
    /// Same plain file copy as the automatic backup, with the same caveat
    /// that a copy taken mid-write is not consistent
    /// (`Features/Backup_Restore.md`).
    /// - Returns: URL of the temporary copy, or nil if no database exists anywhere
    func getShareableWalletFileURL() -> URL? {
        let localFile = Self.existingDatabaseURL(in: walletDirectory)
        guard let source = Self.newerFile(preferred: localFile, other: existingBackupFile) else {
            Self.logger.info("No wallet database to export, locally or in the iCloud backup slot")
            return nil
        }
        if source != localFile {
            Self.logger.info("Exporting the iCloud backup file: it is newer than the local database, or there is no local database")
        }
        return shareableCopy(of: source)
    }

    /// Picks `other` only when both exist and `other` is strictly newer by
    /// modification date; `preferred` otherwise, including when either date
    /// is unreadable. Nil when neither exists.
    static func newerFile(preferred: URL?, other: URL?) -> URL? {
        guard let preferred else { return other }
        guard let other,
              let preferredDate = modificationDate(of: preferred),
              let otherDate = modificationDate(of: other) else { return preferred }
        return otherDate > preferredDate ? other : preferred
    }

    private static func modificationDate(of file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// `getShareableWalletFileURL()` for callers without a wallet handle
    /// (the delete flow on a read-only secondary).
    static func shareableWalletFileURL() -> URL? {
        WalletBackupService(walletDirectory: getWalletDirectory()).getShareableWalletFileURL()
    }

    /// Copies a database file into the temp directory under a timestamped
    /// name the share sheet can hand out. The copy stays in the app's temp
    /// directory until the system purges it, as before.
    private func shareableCopy(of sourceFile: URL) -> URL? {
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
        
        // Copy to temp location
        do {
            try FileManager.default.copyItem(at: sourceFile, to: tempFile)
            Self.logger.debug("Created shareable copy of \(sourceFile.lastPathComponent) at: \(tempFile.path)")
            return tempFile
        } catch {
            Self.logger.error("Failed to create shareable copy: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Whether the slot holds exactly the local database's bytes. Used by
    /// `restoreWalletIfNeeded` so a slot stamped newer than the local file
    /// (every backup is) never triggers a restore of identical content.
    func backupMatchesLocal() async -> Bool {
        guard let backup = existingBackupFile,
              let source = Self.existingDatabaseURL(in: walletDirectory) else { return false }
        return await filesAreIdentical(source, backup)
    }

    // MARK: - Private Helpers

    /// Sets the slot file's modification date to now, so the date reads as
    /// the backup time on every device that lists the slot
    private static func stampBackupTime(_ file: URL) {
        do {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        } catch {
            logger.warning("Could not stamp the backup time: \(error.localizedDescription, privacy: .public)")
        }
    }
    
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
