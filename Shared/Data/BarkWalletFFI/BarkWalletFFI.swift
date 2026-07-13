//
//  BarkWalletFFI.swift
//  Ark wallet prototype
//
//  FFI-based implementation of BarkWalletProtocol using Rust library
//
//  ARCHITECTURE:
//  This file contains the core class definition. Functionality is organized into
//  extensions across multiple files for maintainability:
//
//  📁 Core (this file):
//     - Properties: wallet, onchainWallet, transactionReader, config
//     - Initialization and setup
//     - Utility methods: extractTxFromPsbt(), broadcastTx()
//     - Error types: BarkWalletFFIError
//
//  📁 Extensions (see individual files):
//     - BarkWalletFFI+Balance.swift - Ark & onchain balance, address generation
//     - BarkWalletFFI+Configuration.swift - Config, ArkInfo, network conversion
//     - BarkWalletFFI+Console.swift - Custom command execution (not supported)
//     - BarkWalletFFI+Exit.swift - Unilateral exit system (11 methods)
//     - BarkWalletFFI+Fees.swift - Fee estimation (6 methods)
//     - BarkWalletFFI+Lightning.swift - Lightning operations, invoices, BOLT12
//     - BarkWalletFFI+Mailbox.swift - Mailbox ID, authorization, notifications
//     - BarkWalletFFI+Maintenance.swift - Maintenance refresh operations
//     - BarkWalletFFI+Mnemonic.swift - BIP39 generation, validation, secure storage
//     - BarkWalletFFI+Network.swift - Network helpers, block height, diagnostics
//     - BarkWalletFFI+Rounds.swift - Round cancellation, progress, sync
//     - BarkWalletFFI+Server.swift - Server connection, sync, polling
//     - BarkWalletFFI+Transactions.swift - Send, receive, transaction history
//     - BarkWalletFFI+VTXO.swift - VTXO operations, boarding, refresh (15+ methods)
//     - BarkWalletFFI+WalletCreation.swift - Create, import, delete wallet
//     - BarkWalletFFI+WalletLifecycle.swift - Open, shutdown, state management
//
//  IMPLEMENTATION STATUS:
//  ✅ Fully implemented: 100+ wallet operations across 17 files
//  ✅ Exit System: Complete unilateral exit implementation
//  ✅ VTXO Operations: Advanced VTXO management and refresh
//  ✅ Lightning: Full BOLT11/BOLT12 support with invoices
//  ✅ Maintenance: Automated and delegated refresh operations
//  ✅ Boarding: Onchain to Ark conversion
//  ✅ Transactions: Ark, onchain, and offboard payments
//  ✅ Security: Keychain-based mnemonic storage with biometric protection
//
//  ⚠️ Cannot implement (not in FFI):
//     - getUTXOs() - UTXOs managed internally by wallet
//

import Foundation
import Bark
import OSLog

/// FFI-based implementation of BarkWalletProtocol using the Rust bark library
/// This provides better performance and type safety compared to the CLI-based approach
class BarkWalletFFI: BarkWalletProtocol {
    // MARK: - Logging
    
    /// Logger for BarkWalletFFI operations
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "BarkWalletFFI")

    /// Bridges bark's internal Rust logs (round streams, mailbox subscription,
    /// esplora calls) into the unified logging system under the
    /// "tech.second.bark" subsystem, so they appear in debug log exports.
    /// The FFI bridge can only be installed once per process, hence the
    /// lazily-evaluated static.
    private static let barkRustLoggerInstalled: Bool = {
        do {
            try barkAttachOSLogger(maxLevel: .debug)
            logger.info("Bark Rust logger attached (subsystem: tech.second.bark)")
            return true
        } catch {
            logger.warning("Could not attach bark Rust logger: \(error)")
            return false
        }
    }()
    
    // MARK: - Properties
    
    /// The underlying FFI wallet object (nil until wallet is created/opened)
    var wallet: Wallet?
    
    /// The onchain wallet (managed internally, created alongside main wallet)
    var onchainWallet: OnchainWallet?
    
    /// Read-only transaction history reader (runs alongside OnchainWallet.default())
    var transactionReader: BDKTransactionReader?
    
    /// FFI configuration object, always derived from the current `networkConfig`.
    /// Computed (not stored) so that `updateNetworkConfig()` propagates to every
    /// FFI call - a snapshot taken at init would keep the launch-time network
    /// (e.g. the mainnet default) and make `Wallet.open` fail with a network
    /// mismatch after creating a wallet on another network.
    var config: Config {
        Self.makeConfig(from: networkConfig)
    }

    /// FFI network (no longer carried by `Config` as of Bark 0.11 — passed
    /// separately to `initWallet` / `Wallet.open` / `OnchainWallet.default`).
    /// Derived from `networkConfig` for the same reason as `config`.
    var ffiNetwork: Network {
        Self.convertToFFINetwork(networkConfig.networkType) ?? .signet
    }

    /// Network configuration (our app's model)
    var networkConfig: NetworkConfig
    
    /// Wallet directory URL
    let walletDir: URL
    
    /// Data directory path string (for FFI calls)
    let datadir: String
    
    /// Cached mnemonic (stored securely in production)
    var cachedMnemonic: String?
    
    /// Whether this is a preview/mock instance
    let isPreview: Bool
    
    /// Security service for secure mnemonic storage and biometric authentication
    let securityService: SecurityService?
    
    /// Fallback fee rate (sat/vB) for bark's internal fee estimation.
    /// Without it, bark seeds its fee cache at 1 sat/vB (broadcast minimum)
    /// and errors on fee estimation whenever the Esplora backend is unreachable.
    static let defaultFallbackFeeRateSatPerVb: UInt64 = 10

    /// User agent reported to the Ark server, e.g. "arke-ios/17".
    /// The number is the app's build number (CFBundleVersion).
    static var userAgent: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        #if os(iOS)
        return "arke-ios/\(build)"
        #else
        return "arke-macos/\(build)"
        #endif
    }

    // MARK: - Initialization

    init?(networkConfig: NetworkConfig = .signet, securityService: SecurityService? = nil) {
        self.networkConfig = networkConfig
        self.isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        self.securityService = securityService

        // Route bark's internal Rust logs into the unified log (once per process)
        _ = Self.barkRustLoggerInstalled
        
        // Set up wallet directory
        self.walletDir = Self.getWalletDirectory()
        self.datadir = walletDir.path

        // Validate the network type (config/ffiNetwork are derived on access)
        guard Self.convertToFFINetwork(networkConfig.networkType) != nil else {
            Self.logger.error("Invalid network type: \(networkConfig.networkType)")
            return nil
        }

        // Normalize a pre-0.11 bark.sqlite to db.sqlite before anything
        // checks for or opens the wallet database
        WalletBackupService.migrateLegacyDatabaseFileIfNeeded()

        Self.logger.info("BarkWalletFFI initialized - Network: \(networkConfig.name)")
        Self.logger.debug("Wallet dir: \(self.walletDir.path)")
        
        // Note: Wallet opening is now explicit via openWalletIfNeeded()
        // This prevents uncoordinated background opening during init
    }
    
    // MARK: - Utilities
    
    func extractTxFromPsbt(psbtBase64: String) throws -> String {
        Self.logger.debug("Extracting transaction from PSBT")
        
        do {
            // Call FFI method on onchain wallet to extract transaction hex from PSBT
            let txHex = try Bark.extractTxFromPsbt(psbtBase64: psbtBase64)
            
            Self.logger.info("Transaction extracted from PSBT")
            Self.logger.debug("Tx hex length: \(txHex.count) characters")
            
            return txHex
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error extracting transaction from PSBT: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to extract transaction: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Unexpected error extracting transaction from PSBT: \(error)")
            throw error
        }
    }
    
    func broadcastTx(txHex: String) async throws -> String {
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Broadcasting transaction on network: \(self.networkConfig.name)")
        
        do {
            // Call FFI method to broadcast transaction
            let txid = try await wallet.broadcastTx(txHex: txHex)
            
            Self.logger.info("Transaction broadcast successfully - Txid: \(txid)")
            
            return txid
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error broadcasting transaction: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to broadcast transaction: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Unexpected error broadcasting transaction: \(error)")
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private static func getWalletDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let walletDir = appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GBKS.Arke")
            .appendingPathComponent("bark-data-ffi")
        
        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: walletDir.path) {
            do {
                // Create directory with explicit permissions that allow file creation
                #if os(macOS)
                let attributes: [FileAttributeKey: Any] = [
                    .posixPermissions: NSNumber(value: 0o755)
                ]
                try fileManager.createDirectory(
                    at: walletDir,
                    withIntermediateDirectories: true,
                    attributes: attributes
                )
                #else
                try fileManager.createDirectory(
                    at: walletDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                #endif
                
                logger.debug("Created wallet directory: \(walletDir.path)")
                
                // Verify directory is writable by attempting to create a test file
                let testFile = walletDir.appendingPathComponent(".test")
                do {
                    try "test".write(to: testFile, atomically: true, encoding: .utf8)
                    try fileManager.removeItem(at: testFile)
                    logger.debug("Wallet directory is writable")
                } catch {
                    logger.warning("Wallet directory may not be writable: \(error)")
                }
                
            } catch {
                logger.error("Failed to create wallet directory: \(error)")
            }
        } else {
            logger.debug("FFI Wallet directory exists: \(walletDir.path)")
            
            // Verify existing directory is writable
            let testFile = walletDir.appendingPathComponent(".test")
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try fileManager.removeItem(at: testFile)
                logger.debug("Wallet directory is writable")
            } catch {
                logger.warning("Existing wallet directory may not be writable: \(error)")
            }
        }
        
        return walletDir
    }
}

// MARK: - Error Types

enum BarkWalletFFIError: Swift.Error, LocalizedError {
    case notImplemented(String)
    case notSupported(String)
    case walletNotInitialized
    case invalidMnemonic
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let method):
            return "Method not yet implemented: \(method)"
        case .notSupported(let method):
            return "Method not supported in FFI implementation: \(method)"
        case .walletNotInitialized:
            return "Wallet has not been created or opened"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
