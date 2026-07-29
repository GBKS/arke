//
//  BarkWalletFFI+WalletLifecycle.swift
//  Arke
//
//  Wallet lifecycle operations: open, close, shutdown
//  Handles wallet state management and cleanup
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import OSLog

extension BarkWalletFFI {
    
    // MARK: - Wallet Opening
    
    /// Explicitly opens the wallet if one exists and hasn't been opened yet
    /// This should be called after initialization when you're ready to use the wallet
    /// - Returns: `true` if wallet was opened or already open, `false` if no wallet exists
    @discardableResult
    func openWalletIfNeeded() async -> Bool {
        // If wallet is already open, nothing to do
        if wallet != nil {
            Self.logger.info("Wallet already open")
            return true
        }
        
        // Try to open existing wallet
        await tryOpenExistingWallet()
        
        // Return whether we successfully have an open wallet
        return wallet != nil
    }
    
    /// Attempt to open an existing wallet if one exists
    private func tryOpenExistingWallet() async {
        guard !isPreview else { return }
        
        #if DEBUG
        // Skip wallet opening in debug builds if environment variable OR launch argument is set
        let skipWalletOpen = ProcessInfo.processInfo.environment["SKIP_WALLET_OPEN"] == "1" ||
                             CommandLine.arguments.contains("-skipWalletOpen")
        
        if skipWalletOpen {
            Self.logger.debug("[DEBUG] Skipping wallet open for fast debugging. To enable wallet opening: Remove 'SKIP_WALLET_OPEN' environment variable, OR Remove '-skipWalletOpen' launch argument")
            return
        }
        #endif
        
        // Check if wallet data exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: walletDir.path) else {
            Self.logger.info("No existing wallet found")
            return
        }
        
        // Try to load mnemonic
        guard let mnemonic = try? loadMnemonic() else {
            Self.logger.warning("Wallet directory exists but no mnemonic found")
            return
        }
        
        // DEBUG: Print mnemonic
        //Self.logger.debug("[DEBUG] Loaded mnemonic: \(mnemonic)")
        //Self.logger.debug("[DEBUG] Mnemonic word count: \(mnemonic.split(separator: " ").count)")
        
        // DIAGNOSTIC: Check if datadir exists and list contents
        Self.logger.debug("🔍 [DIAGNOSTIC] Checking wallet directory contents...")
        Self.logger.debug("   Wallet directory path: \(self.walletDir.path)")
        
        var isDirectory: ObjCBool = false
        let walletDirExists = fileManager.fileExists(atPath: walletDir.path, isDirectory: &isDirectory)
        Self.logger.debug("   Exists: \(walletDirExists)")
        Self.logger.debug("   Is Directory: \(isDirectory.boolValue)")
        
        if walletDirExists {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: walletDir.path)
                Self.logger.debug("   Wallet directory contents (\(contents.count) items):")
                for item in contents {
                    let itemPath = (walletDir.path as NSString).appendingPathComponent(item)
                    var itemIsDir: ObjCBool = false
                    fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDir)
                    let itemType = itemIsDir.boolValue ? "DIR" : "FILE"
                    
                    // Get file size if it's a file
                    if !itemIsDir.boolValue {
                        if let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
                           let size = attrs[.size] as? Int64 {
                            Self.logger.debug("     [\(itemType)] \(item) (\(size) bytes)")
                        } else {
                            Self.logger.debug("     [\(itemType)] \(item)")
                        }
                    } else {
                        Self.logger.debug("     [\(itemType)] \(item)/")
                        
                        // Also list subdirectory contents
                        if let subContents = try? fileManager.contentsOfDirectory(atPath: itemPath) {
                            for subItem in subContents {
                                let subItemPath = (itemPath as NSString).appendingPathComponent(subItem)
                                if let attrs = try? fileManager.attributesOfItem(atPath: subItemPath),
                                   let size = attrs[.size] as? Int64 {
                                    Self.logger.debug("       - \(subItem) (\(size) bytes)")
                                } else {
                                    Self.logger.debug("       - \(subItem)")
                                }
                            }
                        }
                    }
                }
            } catch {
                Self.logger.warning("   ⚠️ Could not list directory contents: \(error)")
            }
        } else {
            Self.logger.warning("   ⚠️ Wallet directory does not exist!")
        }
        
        Self.logger.debug("Opening existing wallet - Config: Server Address: \(self.config.serverAddress), Esplora Address: \(self.config.esploraAddress ?? "not set"), Network: \(String(describing: self.ffiNetwork)), VTXO Refresh Expiry Threshold: \(self.config.vtxoRefreshExpiryThreshold.map { String(describing: $0) } ?? "nil"), VTXO Exit Margin: \(self.config.vtxoExitMargin.map { String(describing: $0) } ?? "nil"), HTLC Recv Claim Delta: \(self.config.htlcRecvClaimDelta.map { String(describing: $0) } ?? "nil"), Data Directory: \(self.datadir)")
        
        printFullConfig()
        
        setenv("RUST_LOG", "trace", 1)
        setenv("RUST_BACKTRACE", "1", 1)
        
        // DIAGNOSTIC: Check network availability
        // print("🔍 [DIAGNOSTIC] Checking network status...")
        // await checkNetworkStatus()
        
        // DIAGNOSTIC: Try a simple network request
        // print("🔍 [DIAGNOSTIC] Testing network connectivity to server...")
        // await testServerConnectivity()
        
        // iOS-specific: Add delay to allow network stack to initialize
        // #if os(iOS)
        // print("📱 iOS detected: Waiting for network initialization...")
        // let delayStart = Date()
        // try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        // let delayEnd = Date()
        // print("🔍 [DIAGNOSTIC] Delay completed after \(delayEnd.timeIntervalSince(delayStart)) seconds")
        // #endif
        
        // DIAGNOSTIC: Log before opening wallet
        // let beforeOpen = Date()
        // print("🔍 [DIAGNOSTIC] About to call Wallet.open() at \(beforeOpen)")
        // print("🔍 [DIAGNOSTIC] Time elapsed since start: \(beforeOpen.timeIntervalSince(startTime)) seconds")
        
        do {
            // Create BDK onchain wallet first in a dedicated subdirectory
            Self.logger.debug("Creating BDK onchain wallet...")
            let bdkDataDir = walletDir.appendingPathComponent("bdk", isDirectory: true)
            
            // Ensure BDK directory exists
            let fileManager = FileManager.default
            
            // Clean up legacy BDK files from root directory (from before subdirectory migration)
            let legacyBDKFile = walletDir.appendingPathComponent("bdk_wallet.db")
            if fileManager.fileExists(atPath: legacyBDKFile.path) {
                Self.logger.warning("Found legacy BDK database at root, cleaning up...")
                try? fileManager.removeItem(at: legacyBDKFile)
                // Also remove any associated files (journal, wal, etc.)
                ["bdk_wallet.db-journal", "bdk_wallet.db-wal", "bdk_wallet.db-shm"].forEach { suffix in
                    let file = walletDir.appendingPathComponent(suffix)
                    try? fileManager.removeItem(at: file)
                }
                Self.logger.info("Legacy BDK files cleaned up")
            }
            
            // Check if BDK directory exists
            let bdkDirExists = fileManager.fileExists(atPath: bdkDataDir.path)
            Self.logger.debug("BDK directory exists: \(bdkDirExists)")
            
            if !bdkDirExists {
                Self.logger.debug("Creating BDK data directory: \(bdkDataDir.path)")
                try fileManager.createDirectory(at: bdkDataDir, withIntermediateDirectories: true)
                Self.logger.info("BDK directory created")
            }
            
            // List BDK directory contents
            if let contents = try? fileManager.contentsOfDirectory(atPath: bdkDataDir.path) {
                Self.logger.debug("BDK directory contents (\(contents.count) items):")
                for item in contents {
                    let itemPath = bdkDataDir.appendingPathComponent(item)
                    if let attrs = try? fileManager.attributesOfItem(atPath: itemPath.path),
                       let size = attrs[.size] as? Int64 {
                        Self.logger.debug("  - \(item) (\(size) bytes)")
                    } else {
                        Self.logger.debug("  - \(item)")
                    }
                }
            }
            
            Self.logger.debug("Using Bark's built-in BDK wallet - Mnemonic word count: \(mnemonic.split(separator: " ").count), Network: \(String(describing: self.ffiNetwork)), Esplora: \(self.config.esploraAddress ?? self.networkConfig.esploraBaseURL)")

            // Use Bark's built-in BDK wallet (handles CPFP internally)
            let builtInWallet = try await OnchainWallet.default(
                network: ffiNetwork,
                mnemonic: mnemonic,
                config: config,
                datadir: bdkDataDir.path
            )
            Self.logger.info("Built-in onchain wallet created")

            // Create lightweight transaction reader for history
            Self.logger.debug("Creating transaction history reader...")
            let txReader = try BDKTransactionReader(
                mnemonic: mnemonic,
                network: ffiNetwork,
                esploraURL: config.esploraAddress ?? networkConfig.esploraBaseURL,
                dataDir: bdkDataDir
            )
            Self.logger.info("Transaction reader created")
            
            /*
            // DIAGNOSTIC: Compare wallet configurations
            Self.logger.debug("WALLET CONFIGURATION COMPARISON:")
            do {
                // Get first address from built-in wallet
                let builtInAddress = try await builtInWallet.newAddress()
                Self.logger.debug("Built-in wallet first address: \(builtInAddress)")
                
                // Get first 5 addresses from transaction reader
                let txReaderAddresses = txReader.getFirstNAddresses(count: 25)
                Self.logger.debug("Transaction reader first 25 addresses:")
                for (index, address) in txReaderAddresses.enumerated() {
                    Self.logger.debug("  [\(index)]: \(address)")
                }
                
                // Compare built-in address with first TX reader address
                let builtInStr = String(describing: builtInAddress)
                if let firstTxReaderAddress = txReaderAddresses.first {
                    if builtInStr == firstTxReaderAddress {
                        Self.logger.debug("Addresses MATCH - wallets are using same descriptors")
                    } else {
                        Self.logger.warning("Addresses DIFFER - wallets may have different descriptors! Built-in: \(builtInStr), TX Reader [0]: \(firstTxReaderAddress)")
                        // Check if built-in matches any of the first 5 addresses
                        if let matchIndex = txReaderAddresses.firstIndex(of: builtInStr) {
                            Self.logger.info("Built-in address matches TX Reader[\(matchIndex)] - possible offset!")
                        }
                    }
                }
            } catch {
                Self.logger.warning("Could not compare wallet addresses: \(error)")
            }
             */
            
            // PERFORMANCE: Esplora connectivity test disabled to prevent main thread blocking
            // This synchronous network call was causing ~1+ second UI freeze during wallet opening
            // because WalletManager is @MainActor. The actual wallet opening will test connectivity
            // when it needs to, and any connection issues will surface then with proper error handling.
            // If diagnostic connectivity testing is needed, it should happen:
            // 1. In a background Task.detached {} to avoid blocking main thread
            // 2. After wallet initialization completes, not before
            // 3. As a fire-and-forget operation that doesn't block the UI
            /*
            Self.logger.debug("Testing Esplora connection...")
            let esploraURL = config.esploraAddress ?? networkConfig.esploraBaseURL
            Self.logger.debug("Esplora URL: \(esploraURL)")
            
            if let url = URL(string: "\(esploraURL)/blocks/tip/hash") {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse {
                        Self.logger.debug("HTTP Status: \(httpResponse.statusCode)")
                    }
                    if let hashString = String(data: data, encoding: .utf8) {
                        Self.logger.debug("Block hash received: \(hashString.prefix(16))... (length: \(hashString.count))")
                    }
                } catch {
                    Self.logger.warning("Esplora connection test failed: \(error)")
                }
            }
            */
            
            // Open Bark wallet with BDK-backed onchain capabilities
            Self.logger.debug("Opening Bark wallet with onchain capabilities - Mnemonic word count: \(mnemonic.split(separator: " ").count), Config network: \(String(describing: self.ffiNetwork)), Data directory: \(self.datadir)")
            
            // Check if Bark wallet data exists
            let barkWalletFiles = ["bark.sqlite", "db.sqlite", "wallet.db", "state.json", "wallet.dat"]
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
            
            let openedWallet = try await Wallet.open(
                network: ffiNetwork,
                mnemonicOrSeed: mnemonic,
                config: config,
                args: WalletOpenArgs(
                    datadir: datadir,
                    onchain: builtInWallet
                )
            )
            Self.logger.info("Bark Wallet.open() succeeded!")
            
            self.wallet = openedWallet
            self.onchainWallet = builtInWallet
            self.transactionReader = txReader
            self.cachedMnemonic = mnemonic
            secureWalletFilePermissions()
            
            // Perform initial transaction reader sync in background (non-blocking)
            // This proactively syncs transaction history without blocking wallet opening
            // If sync fails, it will be retried when transaction history is accessed
            // CRITICAL: Use Task.detached to avoid inheriting main actor isolation
            // A plain Task {} would inherit @MainActor and block the UI during fullScan
            Task.detached { [weak self] in
                guard self != nil else { return }
                do {
                    Self.logger.debug("Starting background transaction sync...")
                    try await txReader.sync(fullScan: true)
                    Self.logger.info("Background transaction sync complete - history ready")
                } catch {
                    Self.logger.warning("Background transaction sync failed (will retry on demand): \(error.localizedDescription)")
                }
            }
            
            // let afterOpen = Date()
            Self.logger.info("Existing wallet opened successfully")
            // Self.logger.debug("[DIAGNOSTIC] Wallet.open() took \(afterOpen.timeIntervalSince(beforeOpen)) seconds")
            // Self.logger.debug("[DIAGNOSTIC] Total time: \(afterOpen.timeIntervalSince(startTime)) seconds")
            
            // DIAGNOSTIC: Print wallet state immediately after opening
            await printWalletState(openedWallet, context: "After Wallet.open()")
            
            // DIAGNOSTIC: Check server connection immediately after opening
            Self.logger.debug("[DIAGNOSTIC] Checking server connection after wallet open...")
            let connected = await waitForServerConnection(intervalSeconds: 1.0, timeoutSeconds: 20.0)
            if connected {
                Self.logger.debug("[DIAGNOSTIC] Server connection available after open")
            } else {
                Self.logger.warning("[DIAGNOSTIC] No server connection after wallet open - May need explicit connection step or network delay")
            }
            
        } catch let error as Bark.Error {
            Self.logger.error("Could not open existing wallet: BarkError - Error: \(error), Description: \(error.localizedDescription), Type: \(type(of: error))")
            
            // Print error string representation to see if it contains "DataAlreadyExists"
            let errorString = String(describing: error)
            Self.logger.debug("Error string: \(errorString)")
            if errorString.contains("DataAlreadyExists") {
                Self.logger.error("This appears to be a DataAlreadyExists error - This should NOT happen - BDK Wallet() should load existing data")
            }
            
            // Don't fail init - user can create a new wallet
        } catch {
            Self.logger.error("Could not open existing wallet: Unknown error - Error: \(error), Description: \(error.localizedDescription), Type: \(type(of: error))")
            
            // Print error string to check for specific error messages
            let errorString = String(describing: error)
            Self.logger.debug("Error string: \(errorString)")
            
            // If it's an NSError, print more details
            let nsError = error as NSError
            Self.logger.debug("NSError domain: \(nsError.domain), NSError code: \(nsError.code), NSError userInfo: \(nsError.userInfo)")
        }
    }
    
    // MARK: - Daemon
    
    /// Start a background daemon for the wallet
    ///
    /// The daemon performs periodic syncs, exit progression and other background work.
    /// It uses the onchain wallet bound at `Wallet.open()` (via `WalletOpenArgs.onchain`).
    /// It is stopped automatically when the wallet is dropped.
    /// Calling this multiple times stops the previous daemon and starts a new one.
    func runDaemon() async throws {
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        Self.logger.debug("Starting wallet daemon - Onchain support: \(self.onchainWallet != nil)")

        do {
            // Call FFI method to start the daemon
            try await wallet.runDaemon()
            
            Self.logger.info("Wallet daemon started successfully")
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error starting daemon: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to start daemon: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Unexpected error starting daemon: \(error)")
            throw error
        }
    }
    
    /// Stop the wallet daemon
    ///
    /// Explicitly stops any running background daemon, releasing all resources and file locks.
    /// This should be called before deleting a wallet to ensure clean shutdown.
    func stopDaemon() async throws {
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            // If wallet is nil, daemon is already stopped
            Self.logger.debug("Wallet is nil, daemon already stopped")
            return
        }
        
        Self.logger.debug("Stopping wallet daemon...")
        
        do {
            // Call FFI method to stop the daemon
            try await wallet.stopDaemon()
            
            Self.logger.info("Wallet daemon stopped successfully")
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error stopping daemon: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to stop daemon: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Unexpected error stopping daemon: \(error)")
            throw error
        }
    }
    
    // MARK: - Wallet Shutdown
    
    /// Explicitly shutdown and cleanup wallet resources
    /// Call this BEFORE deleting wallet files to ensure proper cleanup
    func shutdownWallet() async {
        guard let wallet = wallet else { return }
        
        Self.logger.debug("[BarkWalletFFI] Shutting down wallet...")
        
        // CRITICAL: Stop the daemon first to release datadir locks
        do {
            try await stopDaemon()
            Self.logger.info("Daemon stopped successfully")
        } catch {
            Self.logger.warning("Failed to stop daemon (may not be running): \(error)")
        }
        
        // Give daemon time to fully stop and release resources
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Try to sync any pending state before shutdown
        do {
            try await wallet.sync()
            Self.logger.info("Final sync completed")
        } catch {
            Self.logger.warning("Final sync failed (non-critical): \(error)")
        }
        
        // Give the FFI time to flush any pending database writes
        // This is critical - the Rust layer may have buffered writes
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Perform backup before clearing wallet references
        await backupWallet()
        
        // Clear references (this should trigger Rust cleanup)
        self.wallet = nil
        self.onchainWallet = nil
        self.cachedMnemonic = nil
        
        Self.logger.info("Wallet references cleared")
        
        // Additional delay to ensure Rust has fully released database handles
        // SQLite may need time to close connections properly
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        Self.logger.info("Wallet shutdown complete")
    }

    /// Tighten wallet data files to owner-only (0600). bark's fs_perms check
    /// logs an error for any database file left at the default 0644, and
    /// sqlite recreates sidecar files (-wal/-shm) with default permissions,
    /// so this runs after every successful open, not just at creation.
    func secureWalletFilePermissions() {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: datadir) else { return }
        for case let relativePath as String in enumerator {
            let fullPath = (datadir as NSString).appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fullPath)
        }
    }
}
