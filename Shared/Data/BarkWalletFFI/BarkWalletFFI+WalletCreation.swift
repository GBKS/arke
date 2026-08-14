//
//  BarkWalletFFI+WalletCreation.swift
//  Arke
//
//  Wallet creation and import operations
//  Handles new wallet creation, mnemonic-based import, and wallet deletion
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

// MARK: - Import recovery retry decision

/// The pure decision for a seed-only import's creating open
/// (Docs/Initialization/Launch_Sequence_Contract.md, rule 2): bark runs the
/// seed-recovery scan only on the open that creates the wallet locally, and
/// a scan that errors is swallowed into a nil report with no re-scan API —
/// so a nil report while attempts remain means wipe the seconds-old
/// database and redo the creating open.
enum ImportRecoveryLogic {

    static let maxAttempts = 3

    enum Decision: Equatable {
        /// The creating open delivered a recovery report — keep the wallet.
        case accept
        /// No report, attempts remain — wipe the database and reopen.
        case wipeAndRetry
        /// No report, attempts exhausted — keep the wallet anyway. VTXOs
        /// still pending in the regular mailbox arrive via sync; round-
        /// received ones stay missing until a future recovery succeeds.
        case acceptWithoutRecovery
    }

    static func decision(hasReport: Bool, attempt: Int, maxAttempts: Int = Self.maxAttempts) -> Decision {
        if hasReport { return .accept }
        return attempt >= maxAttempts ? .acceptWithoutRecovery : .wipeAndRetry
    }
}

extension BarkWalletFFI {
    
    // MARK: - Wallet Creation
    
    func createWallet(network: String? = nil, arkServer: String? = nil) async throws -> String {
        print("🔍 BarkWalletFFI.createWallet network: \(network ?? "none")")
        
        
        // Preview mode handling
        if isPreview {
            print("⚠️ Preview mode - using mock wallet creation")
            return "Mock: Wallet created (preview mode)"
        }
        
        // ✅ NEW: Verify clean state before creating
        print("🔍 Step 0: Verifying clean state before wallet creation...")
        
        // Ensure no wallet is currently loaded
        if wallet != nil {
            print("⚠️ Warning: Existing wallet instance found, clearing...")
            await shutdownWallet()
        }
        
        let fileManager = FileManager.default
        
        // ✅ NEW: If directory exists from previous wallet, remove it
        if fileManager.fileExists(atPath: walletDir.path) {
            print("⚠️ Old wallet directory exists, removing before creation...")
            do {
                try fileManager.removeItem(at: walletDir)
                print("✅ Old directory removed")
                
                // Brief pause to ensure filesystem has processed the deletion
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            } catch {
                print("❌ Failed to remove old directory: \(error)")
                throw BarkWalletFFIError.configurationError("Cannot create wallet: old directory exists and cannot be removed")
            }
        }
        
        // Generate a new mnemonic (12 words)
        let mnemonic = try generateMnemonic()
        
        // Never log the mnemonic itself - debug logs get exported and shared.
        print("🔍 [DEBUG] Generated mnemonic word count: \(mnemonic.split(separator: " ").count)")
        
        // Use the provided config or override with custom params.
        // Network is passed separately to the FFI as of Bark 0.11.
        let finalConfig: Config
        let net: Network
        if let network = network, let arkServer = arkServer {
            guard let ffiNetwork = Self.convertToFFINetwork(network) else {
                throw BarkWalletFFIError.configurationError("Invalid network type: \(network)")
            }
            net = ffiNetwork
            finalConfig = Self.makeConfig(from: networkConfig, serverAddressOverride: arkServer)
        } else {
            finalConfig = config
            net = ffiNetwork
        }

        print("🔧 Creating wallet with FFI...")
        print("   Network: \(net)")
        print("   Ark Server: \(finalConfig.serverAddress)")
        print("   Esplora Server: \(finalConfig.esploraAddress ?? "none")")
        print("   networkConfig.esploraBaseURL: \(networkConfig.esploraBaseURL)")
        print("   Data dir: \(datadir)")
        
        // ✅ ENHANCED: Better directory preparation
        print("🔍 Step 1: Preparing data directory...")
        if !fileManager.fileExists(atPath: datadir) {
            print("   Creating data directory...")
            do {
                #if os(macOS)
                let attributes: [FileAttributeKey: Any] = [
                    .posixPermissions: NSNumber(value: 0o755)
                ]
                try fileManager.createDirectory(
                    atPath: datadir,
                    withIntermediateDirectories: true,
                    attributes: attributes
                )
                #else
                try fileManager.createDirectory(
                    atPath: datadir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                #endif
                print("   ✅ Data directory created successfully")
            } catch {
                let errorMsg = "Failed to create data directory: \(error.localizedDescription)"
                print("   ❌ \(errorMsg)")
                throw BarkWalletFFIError.configurationError(errorMsg)
            }
        } else {
            print("   ✅ Data directory already exists")
        }
        
        // Verify directory is writable
        let testFile = walletDir.appendingPathComponent(".write-test-\(UUID().uuidString)")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            print("   ✅ Data directory is confirmed writable")
        } catch {
            let errorMsg = "Data directory is not writable: \(error.localizedDescription)"
            print("   ❌ \(errorMsg)")
            throw BarkWalletFFIError.configurationError(errorMsg)
        }
        
        // Create wallet using FFI
        print("🔍 Step 2: Creating wallet with FFI...")
        do {
            print("   About to call Wallet.open()...")

            // Create onchain wallet directory
            print("   Creating onchain wallet...")
            let bdkDataDir = walletDir.appendingPathComponent("bdk", isDirectory: true)
            
            // Clean up legacy BDK files from root directory
            let legacyBDKFile = walletDir.appendingPathComponent("bdk_wallet.db")
            if fileManager.fileExists(atPath: legacyBDKFile.path) {
                print("   ⚠️ Found legacy BDK database at root, cleaning up...")
                try? fileManager.removeItem(at: legacyBDKFile)
                ["bdk_wallet.db-journal", "bdk_wallet.db-wal", "bdk_wallet.db-shm"].forEach { suffix in
                    let file = walletDir.appendingPathComponent(suffix)
                    try? fileManager.removeItem(at: file)
                }
                print("   ✅ Legacy BDK files cleaned up")
            }
            
            // Ensure BDK directory exists
            if !fileManager.fileExists(atPath: bdkDataDir.path) {
                try fileManager.createDirectory(at: bdkDataDir, withIntermediateDirectories: true)
                print("   Created BDK data directory: \(bdkDataDir.path)")
            }
            
            // Use Bark's built-in BDK wallet
            let builtInWallet = try await OnchainWallet.default(
                network: net,
                mnemonic: mnemonic,
                config: finalConfig,
                datadir: bdkDataDir.path
            )
            print("   ✅ Built-in onchain wallet created")

            // Create Bark wallet with built-in onchain capabilities.
            // A single Wallet.open must perform the local creation itself: a
            // prior initWallet() call writes the properties row first, which
            // makes this a "subsequent" open and permanently disables bark's
            // seed-recovery scan (gated on the open that creates the wallet).
            // createWithoutServer keeps creation working when the server is
            // unreachable, as initWallet's allowUnreachableServer did.
            let newWallet = try await Wallet.open(
                network: net,
                mnemonicOrSeed: mnemonic,
                config: finalConfig,
                args: WalletOpenArgs(
                    datadir: datadir,
                    onchain: builtInWallet,
                    createIfNotExists: true,
                    createWithoutServer: true,
                    // Freshly generated seed - nothing to recover, and the scan
                    // would block creation on a network round-trip.
                    skipRecovery: true
                )
            )
            
            self.wallet = newWallet
            self.onchainWallet = builtInWallet
            self.cachedMnemonic = mnemonic
            secureWalletFilePermissions()
            
            // Check if Bark wallet data exists
            let barkWalletFiles = ["bark.sqlite", "db.sqlite"]
            for file in barkWalletFiles {
                let filePath = (datadir as NSString).appendingPathComponent(file)
                let exists = fileManager.fileExists(atPath: filePath)
                if exists {
                    if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                       let size = attrs[.size] as? Int64 {
                        Self.logger.debug("Found Bark file: \(file) (\(size) bytes)")
                    }
                }
            }
            
            print("✅ Wallet created successfully")
            
            // DIAGNOSTIC: Compare wallet state immediately after creation vs opening
            await printWalletState(newWallet, context: "After Wallet.create()")
            
            // Try immediate arkInfo() call before waiting
            print("🔍 [DIAGNOSTIC] Immediate arkInfo() check after creation...")
            if let immediateArkInfo = await newWallet.arkInfo() {
                print("✅ [SURPRISE] Server connected IMMEDIATELY after creation!")
                print("   Round interval: \(immediateArkInfo.roundIntervalSecs)s")
            } else {
                print("⚠️ [DIAGNOSTIC] No immediate server connection after creation")
            }
            
            // Try calling sync() to see if that establishes connection
            print("🔍 [DIAGNOSTIC] Attempting wallet.sync() to establish connection...")
            do {
                try await newWallet.sync()
                print("✅ [DIAGNOSTIC] sync() completed successfully")
                
                // Check connection again after sync
                if let postSyncArkInfo = await newWallet.arkInfo() {
                    print("✅ [DIAGNOSTIC] Server connected after sync()!")
                    print("   Round interval: \(postSyncArkInfo.roundIntervalSecs)s")
                } else {
                    print("⚠️ [DIAGNOSTIC] Still no connection even after sync()")
                }
            } catch {
                print("❌ [DIAGNOSTIC] sync() failed: \(error)")
            }
            
            // DIAGNOSTIC: Check if wallet has server connection immediately after creation
            print("🔍 [DIAGNOSTIC] Now starting connection polling...")
            let connected = await waitForServerConnection(intervalSeconds: 1.0, timeoutSeconds: 60.0)
            if connected {
                print("✅ [DIAGNOSTIC] Wallet has server connection after creation")
            } else {
                print("⚠️ [DIAGNOSTIC] Wallet created but NO server connection after 20s")
                print("💡 [HINT] Server connection may need to be established separately")
                print("   Possible reasons:")
                print("   1. Connection happens lazily on first server operation")
                print("   2. Network not ready at wallet creation time")
                print("   3. forceRescan parameter doesn't trigger connection")
                print("   4. Server connection requires explicit initialization")
                print("   5. New wallet needs additional initialization step")
                
                // Try one more thing: call maintenance to see if that helps
                print("🔍 [DIAGNOSTIC] Attempting wallet.maintenance() as last resort...")
                do {
                    try await newWallet.maintenance()
                    print("✅ [DIAGNOSTIC] maintenance() completed")
                    
                    if let postMaintenanceArkInfo = await newWallet.arkInfo() {
                        print("✅ [DIAGNOSTIC] Server connected after maintenance()!")
                        print("   Round interval: \(postMaintenanceArkInfo.roundIntervalSecs)s")
                    } else {
                        print("⚠️ [DIAGNOSTIC] Still no connection after maintenance()")
                    }
                } catch {
                    print("❌ [DIAGNOSTIC] maintenance() failed: \(error)")
                }
            }
            
            // NOTE: Mnemonic storage is handled by WalletManager.createWallet() to avoid duplication
            // Only importWallet() flow should call storeMnemonic() directly
            print("✅ [BarkWalletFFI] Wallet created - returning mnemonic to WalletManager for storage")
            print("   ⏭️  Skipping storeMnemonic() to prevent duplication")
            
            // Perform initial backup after wallet creation
            await backupWallet()
            
            return mnemonic
            
        } catch let error as Bark.Error {
            print("❌ FFI Error creating wallet: \(error)")
            
            // ✅ NEW: Enhanced error handling with cleanup suggestion
            if error.localizedDescription.contains("bark_properties") ||
               error.localizedDescription.contains("database") ||
               error.localizedDescription.contains("SQL") {
                print("💡 Database error detected - this may be due to stale database files")
                print("   Attempting cleanup and suggesting retry...")
                
                // Try to clean up and suggest retry
                if fileManager.fileExists(atPath: walletDir.path) {
                    try? fileManager.removeItem(at: walletDir)
                }
                
                throw BarkWalletFFIError.configurationError(
                    "Failed to create wallet due to database error. Please try again. If the issue persists, restart the app.\n\nTechnical details: \(error.localizedDescription)"
                )
            }
            
            throw BarkWalletFFIError.configurationError("Failed to create wallet: \(error.localizedDescription)")
        } catch {
            print("❌ Error creating wallet: \(error)")
            throw error
        }
    }
    
    // MARK: - Wallet Import
    
    func importWallet(network: String? = nil, arkServer: String? = nil, mnemonic: String) async throws -> String {
        // Preview mode handling
        if isPreview {
            print("⚠️ Preview mode - using mock wallet import")
            return "Mock: Wallet imported (preview mode)"
        }
        
        // Validate mnemonic (basic check - should be 12 or 24 words)
        let words = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard words.count == 12 || words.count == 24 else {
            throw BarkWalletFFIError.invalidMnemonic
        }
        
        // Never log the mnemonic itself - debug logs get exported and shared.
        print("🔍 [DEBUG] Importing mnemonic word count: \(words.count)")
        
        // Use the provided config or override with custom params.
        // Network is passed separately to the FFI as of Bark 0.11.
        let finalConfig: Config
        let net: Network
        if let network = network, let arkServer = arkServer {
            guard let ffiNetwork = Self.convertToFFINetwork(network) else {
                throw BarkWalletFFIError.configurationError("Invalid network type: \(network)")
            }
            net = ffiNetwork
            finalConfig = Self.makeConfig(from: networkConfig, serverAddressOverride: arkServer)
        } else {
            finalConfig = config
            net = ffiNetwork
        }

        print("🔧 Importing wallet with FFI...")
        print("   Network: \(net)")
        print("   Ark server: \(finalConfig.serverAddress)")
        print("   Data dir: \(datadir)")
        
        // Check if backup is available
        if hasBackupAvailable() {
            Self.logger.info("📦 iCloud backup detected - database restore available if needed")
            if let backupInfo = await getBackupInfo() {
                Self.logger.info("   Last backup: \(backupInfo.formattedDate)")
                Self.logger.info("   Size: \(backupInfo.formattedSize)")
            }
        }
        
        // Ensure the data directory exists and is writable before attempting wallet import
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: datadir) {
            print("⚠️ Data directory doesn't exist, creating it now...")
            do {
                #if os(macOS)
                let attributes: [FileAttributeKey: Any] = [
                    .posixPermissions: NSNumber(value: 0o755)
                ]
                try fileManager.createDirectory(
                    atPath: datadir,
                    withIntermediateDirectories: true,
                    attributes: attributes
                )
                #else
                try fileManager.createDirectory(
                    atPath: datadir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                #endif
                print("✅ Data directory created successfully")
            } catch {
                let errorMsg = "Failed to create data directory: \(error.localizedDescription)"
                print("❌ \(errorMsg)")
                throw BarkWalletFFIError.configurationError(errorMsg)
            }
        }
        
        // Verify directory is writable
        let testFile = walletDir.appendingPathComponent(".write-test-\(UUID().uuidString)")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            print("✅ Data directory is confirmed writable")
        } catch {
            let errorMsg = "Data directory is not writable: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            throw BarkWalletFFIError.configurationError(errorMsg)
        }
        
        // Create/restore wallet using FFI with provided mnemonic
        do {
            // Create onchain wallet for import
            print("🔧 Creating onchain wallet for import...")
            let bdkDataDir = walletDir.appendingPathComponent("bdk", isDirectory: true)
            
            // Clean up legacy BDK files
            let legacyBDKFile = walletDir.appendingPathComponent("bdk_wallet.db")
            if fileManager.fileExists(atPath: legacyBDKFile.path) {
                print("   ⚠️ Found legacy BDK database at root, cleaning up...")
                try? fileManager.removeItem(at: legacyBDKFile)
                ["bdk_wallet.db-journal", "bdk_wallet.db-wal", "bdk_wallet.db-shm"].forEach { suffix in
                    let file = walletDir.appendingPathComponent(suffix)
                    try? fileManager.removeItem(at: file)
                }
                print("   ✅ Legacy BDK files cleaned up")
            }
            
            // Ensure BDK directory exists
            if !fileManager.fileExists(atPath: bdkDataDir.path) {
                try fileManager.createDirectory(at: bdkDataDir, withIntermediateDirectories: true)
                print("   Created BDK data directory: \(bdkDataDir.path)")
            }
            
            // Use Bark's built-in BDK wallet
            let builtInWallet = try await OnchainWallet.default(
                network: net,
                mnemonic: mnemonic,
                config: finalConfig,
                datadir: bdkDataDir.path
            )
            print("✅ Built-in onchain wallet created")

            // Open or create Bark wallet with built-in onchain capabilities
            // If backup was restored, wallet data already exists, so we should open it
            // Otherwise, create a new wallet
            let dbSqlitePath = (datadir as NSString).appendingPathComponent(WalletBackupService.currentDatabaseFileName)
            let walletExists = fileManager.fileExists(atPath: dbSqlitePath)
            let restoredWallet: Wallet

            if walletExists {
                print("📂 Wallet database detected at \(dbSqlitePath) - opening existing wallet...")
                restoredWallet = try await Wallet.open(
                    network: net,
                    mnemonicOrSeed: mnemonic,
                    config: finalConfig,
                    args: WalletOpenArgs(
                        datadir: datadir,
                        onchain: builtInWallet,
                        createIfNotExists: false
                    )
                )
                print("✅ Existing wallet opened successfully")
            } else {
                print("🆕 No wallet database found - creating new wallet...")
                restoredWallet = try await openImportedWallet(
                    network: net,
                    mnemonic: mnemonic,
                    config: finalConfig,
                    onchain: builtInWallet
                )
                print("✅ New wallet created successfully")
            }
            
            self.wallet = restoredWallet
            self.onchainWallet = builtInWallet
            self.cachedMnemonic = mnemonic
            secureWalletFilePermissions()

            // NOTE: Mnemonic storage is handled by WalletManager.importWalletWithBackup() to avoid duplication
            // WalletManager calls securityService.handleSeedImport() which saves the mnemonic
            // Only call storeMnemonic() here if NOT coming from WalletManager (e.g., direct import without backup)
            // Since we can't easily detect that, we skip it here and let WalletManager handle it
            print("✅ [BarkWalletFFI] Wallet imported - mnemonic storage handled by WalletManager")
            print("   ⏭️  Skipping storeMnemonic() to prevent duplication")
            
            // Check if Bark wallet data exists
            let barkWalletFiles = ["bark.sqlite", "db.sqlite"]
            for file in barkWalletFiles {
                let filePath = (datadir as NSString).appendingPathComponent(file)
                let exists = fileManager.fileExists(atPath: filePath)
                if exists {
                    if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                       let size = attrs[.size] as? Int64 {
                        Self.logger.debug("Found Bark file: \(file) (\(size) bytes)")
                    }
                }
            }

            // Perform initial backup after wallet import
            await backupWallet()

            print("✅ Wallet imported successfully")
            return "Wallet imported successfully. Syncing with network..."
            
        } catch let error as Bark.Error {
            print("❌ FFI Error importing wallet: \(error)")
            // Existing wallet data from another network fails the bdk or bark
            // open with a network mismatch. Surface it as a typed error so the
            // caller can decide whether the data is stale and may be wiped.
            if String(describing: error).contains("Network mismatch") {
                throw BarkWalletFFIError.networkMismatch(error.localizedDescription)
            }
            throw BarkWalletFFIError.configurationError("Failed to import wallet: \(error.localizedDescription)")
        } catch {
            print("❌ Error importing wallet: \(error)")
            throw error
        }
    }
    
    // MARK: - Recovery Report

    /// Opens the wallet for a seed-only import, creating it locally.
    ///
    /// bark runs the seed-recovery mailbox scan only on the open that performs
    /// the local creation, and a scan that errors out (e.g. the server was
    /// unreachable in that window) is swallowed into a nil report with no API
    /// to re-run it. The database is seconds old at that point, so the retry
    /// for a nil report is to wipe it and redo the creating open.
    private func openImportedWallet(
        network net: Network,
        mnemonic: String,
        config finalConfig: Config,
        onchain builtInWallet: OnchainWallet
    ) async throws -> Wallet {
        for attempt in 1...ImportRecoveryLogic.maxAttempts {
            let wallet = try await Wallet.open(
                network: net,
                mnemonicOrSeed: mnemonic,
                config: finalConfig,
                args: WalletOpenArgs(
                    datadir: datadir,
                    onchain: builtInWallet,
                    createIfNotExists: true,
                    // Import must succeed even when the server is briefly
                    // unreachable; unlike an initWallet-then-open split, this
                    // flag does not suppress the recovery scan.
                    createWithoutServer: true,
                    // skipRecovery stays false: this is a seed import, so the
                    // recovery mailbox scan is what restores existing VTXOs.
                    skipRecovery: false
                )
            )

            let report = wallet.recoveryReport()
            switch ImportRecoveryLogic.decision(hasReport: report != nil, attempt: attempt) {
            case .accept:
                if let report {
                    logRecoveryReport(report)
                    await retryFailedRecoveries(from: report, wallet: wallet)
                }
                return wallet

            case .acceptWithoutRecovery:
                Self.logger.error("Recovery scan never completed after \(ImportRecoveryLogic.maxAttempts) attempts - continuing import; VTXOs still pending in the regular mailbox arrive via sync, but round-received VTXOs may be missing until a future recovery succeeds")
                return wallet

            case .wipeAndRetry:
                Self.logger.warning("Recovery scan produced no report (attempt \(attempt)/\(ImportRecoveryLogic.maxAttempts)) - the scan errored before completing")
                // The scan only runs on the open that creates the wallet
                // locally, so retrying requires wiping the seconds-old
                // database first.
                try? await wallet.stopDaemon()
                try? await Task.sleep(nanoseconds: 500_000_000) // let Rust release sqlite handles
                removeBarkDatabase()
            }
        }
        throw BarkWalletFFIError.configurationError("Wallet open retry loop exited unexpectedly")
    }

    /// Removes the bark database (and sqlite sidecars) so the next open
    /// re-creates the wallet and re-runs the recovery scan.
    private func removeBarkDatabase() {
        let fileManager = FileManager.default
        let base = (datadir as NSString).appendingPathComponent(WalletBackupService.currentDatabaseFileName)
        for path in [base, base + "-wal", base + "-shm"] where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }

    /// Retries the VTXO ids a recovery scan bucketed as `failed` (per-VTXO
    /// transient errors; the scan itself still completed).
    private func retryFailedRecoveries(from report: RecoveryReport, wallet: Wallet) async {
        guard !report.failed.vtxoIds.isEmpty else { return }
        do {
            let retried = try await wallet.recoverVtxos(vtxoIds: report.failed.vtxoIds)
            Self.logger.info("Recovery retry of \(report.failed.vtxoIds.count) failed id(s): recovered \(retried.recovered.vtxoIds.count) (\(retried.recovered.totalSats) sats), still failed \(retried.failed.vtxoIds.count)")
        } catch {
            Self.logger.warning("Recovery retry of failed ids errored: \(error)")
        }
    }

    /// Logs the seed-recovery scan result bark produced on the creating open.
    private func logRecoveryReport(_ report: RecoveryReport) {
        Self.logger.info("""
            Recovery scan complete=\(report.isComplete): \
            recovered \(report.recovered.vtxoIds.count) (\(report.recovered.totalSats) sats), \
            skipped \(report.skipped.vtxoIds.count), \
            foreign \(report.foreign.vtxoIds.count), \
            failed \(report.failed.vtxoIds.count), \
            exited \(report.exited.vtxoIds.count)
            """)
        if !report.failed.vtxoIds.isEmpty {
            Self.logger.warning("Recovery scan failed VTXO ids (retryable via recoverVtxos): \(report.failed.vtxoIds)")
        }
        if !report.foreign.vtxoIds.isEmpty {
            Self.logger.warning("Recovery scan foreign VTXO ids (possibly beyond gap limit): \(report.foreign.vtxoIds)")
        }
    }

    // MARK: - Wallet Deletion

    func deleteWallet() async throws -> String {
        // Preview mode handling
        if isPreview {
            print("⚠️ Preview mode - wallet deletion skipped")
            return "Mock: Wallet deleted (preview mode)"
        }
        
        let fileManager = FileManager.default
        
        // Safety check: verify the wallet directory path looks correct
        guard walletDir.path.contains("bark-data-ffi") else {
            throw BarkWalletFFIError.configurationError("Invalid wallet directory path: \(walletDir.path)")
        }
        
        // ✅ NEW: Explicit shutdown before deletion
        print("🛑 Step 1: Shutting down wallet...")
        await shutdownWallet()
        
        // Delete from SecurityService (Keychain only - local deletion)
        if let securityService = securityService {
            print("🗑️ Step 2: Deleting mnemonic from Keychain via SecurityService")
            do {
                try await securityService.deleteWalletData(includeCloudData: false)
                print("✅ Mnemonic deleted from Keychain")
            } catch {
                print("⚠️ Failed to delete from Keychain: \(error)")
                // Continue to delete file system data anyway
            }
        }
        
        // Check if wallet directory exists
        guard fileManager.fileExists(atPath: walletDir.path) else {
            print("⚠️ Wallet directory does not exist at: \(walletDir.path)")
            return "Wallet directory does not exist (already deleted)"
        }
        
        print("🗑️ Step 3: Deleting wallet directory: \(walletDir.path)")
        
        do {
            // Remove the entire wallet directory and its contents
            try fileManager.removeItem(at: walletDir)
            print("✅ Successfully deleted wallet directory")
            
            // ✅ NEW: Extra verification that directory is gone
            let stillExists = fileManager.fileExists(atPath: walletDir.path)
            if stillExists {
                print("⚠️ Warning: Directory still exists after deletion attempt")
                throw BarkWalletFFIError.configurationError("Failed to fully delete wallet directory")
            }
            
            return "Successfully deleted wallet directory at \(walletDir.path)"
        } catch {
            print("❌ Failed to delete wallet directory: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to delete wallet directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Print detailed wallet state for diagnostics
    func printWalletState(_ wallet: Wallet, context: String) async {
        print("🔍 [WALLET STATE] \(context)")
        let config = await wallet.config()
        print("   Config server: \(config.serverAddress)")
        print("   Config esplora: \(config.esploraAddress ?? "nil")")
        print("   Config network: \(self.ffiNetwork)")
        
        // Try to get properties if available
        do {
            let props = try await wallet.properties()
            print("   Wallet network: \(props.network)")
            print("   Wallet fingerprint: \(props.fingerprint)")
        } catch {
            print("   ⚠️ Could not get wallet properties: \(error)")
        }
        
        // Check if arkInfo is available
        if let arkInfo = await wallet.arkInfo() {
            print("   ✅ Has server connection (arkInfo available)")
            print("      Round interval: \(arkInfo.roundIntervalSecs)s")
            print("      Server pubkey: \(String(arkInfo.serverPubkey.prefix(20)))...")
        } else {
            print("   ❌ No server connection (arkInfo returns nil)")
        }
        
        // Try to get balance (requires server connection)
        do {
            let balance = try await wallet.balance()
            print("   ✅ Can fetch balance (server accessible)")
            print("      Spendable: \(balance.spendableSats) sats")
        } catch {
            print("   ❌ Cannot fetch balance: \(error)")
        }
    }
    
    /// Convert our NetworkConfig networkType string to FFI Network enum
    static func convertToFFINetwork(_ networkType: String) -> Network? {
        switch networkType.lowercased() {
        case "mainnet", "bitcoin":
            return .bitcoin
        case "testnet":
            return .testnet
        case "signet":
            return .signet
        case "regtest":
            return .regtest
        default:
            return nil
        }
    }
}
