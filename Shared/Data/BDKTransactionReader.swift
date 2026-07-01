//
//  BDKTransactionReader.swift
//  Arké
//
//  Lightweight BDK wallet wrapper for reading onchain transaction history
//  Used alongside Bark's OnchainWallet.default() - does NOT replace it
//

import Foundation
import BitcoinDevKit
import Bark

/// Read-only BDK wallet service for listing onchain transactions
/// 
/// This service runs in parallel with Bark's built-in OnchainWallet to provide
/// transaction history functionality that is not exposed in the Bark FFI.
/// 
/// Architecture:
/// - OnchainWallet.default() → Main wallet (CPFP, boarding, exits)
/// - BDKTransactionReader → Transaction history only
///
/// Wallet Configuration (matches Bark's built-in wallet):
/// - Uses Wallet.createSingle() / loadSingle() - same as Bark's Wallet::create_single()
/// - BIP86 (Taproot) derivation: m/86'/coin_type'/0'/0/*
/// - Single-descriptor wallet (no separate change descriptor)
/// - Empty BIP39 passphrase (matches Bark's mnemonic.to_seed(""))
/// - Same network as Bark wallet
final class BDKTransactionReader {
    
    private let wallet: BitcoinDevKit.Wallet
    private let esploraClient: EsploraClient
    
    // MARK: - Initialization
    
    /// Initialize a read-only BDK wallet for transaction queries
    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - network: Bark Network type
    ///   - esploraURL: Esplora server URL
    ///   - dataDir: Directory to store wallet database
    init(mnemonic: String, network: Bark.Network, esploraURL: String, dataDir: URL) throws {
        print("📜 Initializing BDKTransactionReader...")
        
        // Convert Bark Network to BDK Network
        let bdkNetwork = try Self.convertToBDKNetwork(network)
        
        // Create descriptor from mnemonic
        // IMPORTANT: Must match Bark's onchain wallet configuration:
        // - BIP86 (Taproot) 
        // - Empty BIP39 passphrase
        // - External path: m/86'/coin_type'/0'/0/*
        // - Single-descriptor wallet using Wallet.createSingle() (same as Bark's Wallet::create_single)
        let mnemonicObj = try Mnemonic.fromString(mnemonic: mnemonic)
        let secretKey = DescriptorSecretKey(
            network: bdkNetwork,
            mnemonic: mnemonicObj,
            password: nil  // Empty passphrase to match Bark's mnemonic.to_seed("")
        )
        
        let descriptor = Descriptor.newBip86(
            secretKey: secretKey,
            keychainKind: .external,
            network: bdkNetwork
        )
        
        // Diagnostic: log the descriptor string
        print("   📋 Descriptor: \(String(describing: descriptor))")
        
        // Create persister (separate database from main wallet)
        let dbPath = dataDir.appendingPathComponent("bdk_transactions.db")
        let persister = try Persister.newSqlite(path: dbPath.path)
        
        // Create or load single-descriptor wallet to match Bark's Wallet::create_single()
        if FileManager.default.fileExists(atPath: dbPath.path) {
            print("   Loading existing single-descriptor transaction database...")
            do {
                self.wallet = try BitcoinDevKit.Wallet.loadSingle(
                    descriptor: descriptor,
                    persister: persister
                )
            } catch {
                print("   ⚠️ Failed to load existing database, recreating: \(error)")
                // Delete old database and create new one
                try? FileManager.default.removeItem(at: dbPath)
                let newPersister = try Persister.newSqlite(path: dbPath.path)
                self.wallet = try BitcoinDevKit.Wallet.createSingle(
                    descriptor: descriptor,
                    network: bdkNetwork,
                    persister: newPersister
                )
            }
        } else {
            print("   Creating new single-descriptor transaction database...")
            self.wallet = try BitcoinDevKit.Wallet.createSingle(
                descriptor: descriptor,
                network: bdkNetwork,
                persister: persister
            )
        }
        
        self.esploraClient = EsploraClient(url: esploraURL)
        print("✅ BDKTransactionReader initialized")
        
        // Testing: Clear database on init for clean load
        // try clearDatabase()
    }
    
    // MARK: - Public Methods
    
    /// Sync the wallet to fetch latest transactions
    /// - Parameters:
    ///   - fullScan: If true, performs full scan. If false, incremental sync.
    ///   - stopGap: Number of consecutive unused addresses before stopping
    ///   - parallelRequests: Number of parallel requests to Esplora
    /// 
    /// IMPORTANT: This method bridges BDK's blocking Esplora client to async Swift.
    /// The underlying fullScan/sync calls are synchronous and do blocking thread joins.
    /// We use withCheckedThrowingContinuation + DispatchQueue.global to ensure this
    /// runs on a background thread and never blocks the main thread/UI.
    func sync(fullScan: Bool = false, stopGap: UInt64 = 10, parallelRequests: UInt64 = 3) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: BDKTransactionReaderError.syncFailed(NSError(domain: "BDKTransactionReader", code: -1)))
                    return
                }
                
                do {
                    if fullScan {
                        let fullScanRequest = try self.wallet.startFullScan().build()
                        let update = try self.esploraClient.fullScan(
                            request: fullScanRequest,
                            stopGap: stopGap,
                            parallelRequests: parallelRequests
                        )
                        try self.wallet.applyUpdate(update: update)
                    } else {
                        let syncRequest = try self.wallet.startSyncWithRevealedSpks().build()
                        let update = try self.esploraClient.sync(
                            request: syncRequest,
                            parallelRequests: parallelRequests
                        )
                        try self.wallet.applyUpdate(update: update)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get the first receiving address (for diagnostic comparison)
    /// - Returns: First external address as string
    func getFirstAddress() -> String {
        let addressInfo = wallet.revealNextAddress(keychain: .external)
        return String(describing: addressInfo.address)
    }
    
    /// Get the first N receiving addresses (for diagnostic comparison)
    /// - Parameter count: Number of addresses to generate
    /// - Returns: Array of addresses as strings
    func getFirstNAddresses(count: Int) -> [String] {
        var addresses: [String] = []
        for _ in 0..<count {
            let addressInfo = wallet.revealNextAddress(keychain: .external)
            addresses.append(String(describing: addressInfo.address))
        }
        return addresses
    }
    
    /// List all transactions in the wallet
    /// - Returns: Array of transactions with confirmation status
    func listTransactions() -> [CanonicalTx] {
        return wallet.transactions()
    }
    
    /// Clear the BDK transaction database to force fresh interpretation on next sync
    /// Useful for testing changes to transaction parsing logic
    func clearDatabase() throws {
        // Get the database path
        let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bdk")
            .appendingPathComponent("bdk_transactions.db")
        
        // Remove database file if it exists
        if FileManager.default.fileExists(atPath: dbPath.path) {
            try FileManager.default.removeItem(at: dbPath)
            print("🗑️ Cleared BDK transaction database: \(dbPath.path)")
            
            // Also remove associated SQLite files (journal, wal, shm)
            ["bdk_transactions.db-journal", "bdk_transactions.db-wal", "bdk_transactions.db-shm"].forEach { suffix in
                let file = dbPath.deletingLastPathComponent().appendingPathComponent(suffix)
                try? FileManager.default.removeItem(at: file)
            }
        } else {
            print("ℹ️ BDK transaction database does not exist at: \(dbPath.path)")
        }
    }
    
    /// Estimate fee for sending a specific amount to an address
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - amountSats: Amount to send in satoshis
    ///   - feeRateSatPerVb: Fee rate in sat/vB
    /// - Returns: Estimated fee in satoshis
    /// - Throws: Error if transaction building or fee calculation fails
    func estimateFee(address: String, amountSats: UInt64, feeRateSatPerVb: UInt64) throws -> UInt64 {
        print("💰 [BDKTransactionReader] Estimating fee...")
        print("   Address: \(address)")
        print("   Amount: \(amountSats) sats")
        print("   Fee rate: \(feeRateSatPerVb) sat/vB")
        
        // Convert address string to BDK Address
        let destAddress = try BitcoinDevKit.Address(address: address, network: wallet.network())
        let amount = BitcoinDevKit.Amount.fromSat(satoshi: amountSats)
        let feeRate = try BitcoinDevKit.FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)
        
        // Build transaction (doesn't broadcast, just estimates)
        let txBuilder = BitcoinDevKit.TxBuilder()
            .addRecipient(script: destAddress.scriptPubkey(), amount: amount)
            .feeRate(feeRate: feeRate)
        
        let psbt = try txBuilder.finish(wallet: wallet)
        let tx = try psbt.extractTx()
        
        // Calculate exact fee
        let feeAmount = try wallet.calculateFee(tx: tx)
        let feeSats = feeAmount.toSat()
        
        print("✅ [BDKTransactionReader] Fee estimated: \(feeSats) sats")
        
        return feeSats
    }
    
    /// Calculate maximum sendable amount (send full balance) with fee deduction
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - feeRateSatPerVb: Fee rate in sat/vB
    /// - Returns: Tuple of (sendAmount, fee) both in satoshis
    /// - Throws: Error if transaction building or fee calculation fails
    func calculateMaxSendable(address: String, feeRateSatPerVb: UInt64) throws -> (sendAmount: UInt64, fee: UInt64) {
        print("💰 [BDKTransactionReader] Calculating max sendable...")
        print("   Address: \(address)")
        print("   Fee rate: \(feeRateSatPerVb) sat/vB")
        
        // Convert address string to BDK Address
        let destAddress = try BitcoinDevKit.Address(address: address, network: wallet.network())
        let feeRate = try BitcoinDevKit.FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)
        
        // Build drain transaction (sends entire balance minus fee)
        let txBuilder = BitcoinDevKit.TxBuilder()
            .drainWallet()
            .drainTo(script: destAddress.scriptPubkey())
            .feeRate(feeRate: feeRate)
        
        let psbt = try txBuilder.finish(wallet: wallet)
        let tx = try psbt.extractTx()
        
        // Get send amount from transaction outputs
        let outputs = tx.output()
        guard outputs.count > 0 else {
            throw BDKTransactionReaderError.invalidTransaction
        }
        
        let sendAmount = outputs[0].value.toSat()
        
        // Calculate fee
        let feeAmount = try wallet.calculateFee(tx: tx)
        let feeSats = feeAmount.toSat()
        
        print("✅ [BDKTransactionReader] Max sendable calculated")
        print("   Send amount: \(sendAmount) sats")
        print("   Fee: \(feeSats) sats")
        
        return (sendAmount, feeSats)
    }
    
    /// Get detailed transaction information
    /// - Returns: Array of tuples with txid, sent, received, fee, confirmation details, and self-transfer flag
    func getTransactionDetails() -> [(txid: String, sent: UInt64, received: UInt64, fee: UInt64?, confirmationTime: ConfirmationTime?, isSelfTransfer: Bool)] {
        let transactions = wallet.transactions()
        
        print("🔍 BDKTransactionReader analyzing \(transactions.count) transactions...")
        
        // Get current block height for confirmation calculations
        let currentHeight = getCurrentBlockHeight()
        
        return transactions.map { canonicalTx in
            let tx = canonicalTx.transaction
            let txid = String(describing: tx.computeTxid())
            
            print("\n   📝 TX: \(txid.prefix(16))...")
            
            // Use BDK's sentAndReceived method to get accurate amounts
            // This properly handles all inputs/outputs including spent ones
            let sentAndReceived = wallet.sentAndReceived(tx: tx)
            let received = sentAndReceived.received.toSat()
            let sent = sentAndReceived.sent.toSat()
            
            // Count outputs owned by wallet to detect self-transfers
            var outputsOwnedByWallet = 0
            let totalOutputs = tx.output().count
            
            for (vout, output) in tx.output().enumerated() {
                if wallet.isMine(script: output.scriptPubkey) {
                    outputsOwnedByWallet += 1
                    print("      Output #\(vout): \(output.value.toSat()) sats → OURS ✓")
                } else {
                    print("      Output #\(vout): \(output.value.toSat()) sats → not ours")
                }
            }
            
            // Detect self-transfer: we spent inputs AND all outputs belong to us
            // This identifies unilateral exit intermediary transactions and other self-transfers
            let isSelfTransfer = sent > 0 && outputsOwnedByWallet == totalOutputs && totalOutputs > 0
            
            print("      Summary: sent=\(sent), received=\(received), ours=\(outputsOwnedByWallet)/\(totalOutputs), selfTransfer=\(isSelfTransfer)")
            
            // Calculate fee if this is a transaction we sent
            let fee: UInt64? = {
                if sent > 0 {
                    // Try BDK's calculateFee first
                    do {
                        let feeAmount = try wallet.calculateFee(tx: tx)
                        let feeSats = feeAmount.toSat()
                        print("      ✅ Fee calculated via BDK: \(feeSats) sats")
                        return feeSats
                    } catch {
                        // Fallback to manual calculation if BDK can't calculate
                        // (e.g., if we don't have all previous outputs)
                        if sent > received {
                            let manualFee = sent - received
                            print("      ⚠️ Fee estimated manually: \(manualFee) sats (BDK error: \(error))")
                            return manualFee
                        }
                        print("      ⚠️ Could not calculate fee: \(error)")
                        return nil
                    }
                }
                return nil
            }()
            
            // Get confirmation info
            let confirmationTime = getConfirmationTime(chainPosition: canonicalTx.chainPosition, currentHeight: currentHeight)
            
            return (txid, sent, received, fee, confirmationTime, isSelfTransfer)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Get current block height from wallet's latest checkpoint
    /// - Returns: Current block height, or nil if unavailable
    private func getCurrentBlockHeight() -> UInt32? {
        // Use wallet's latest checkpoint height (from most recent sync)
        // This avoids an extra network call since we just synced
        return wallet.latestCheckpoint().height
    }
    
    private func getConfirmationTime(chainPosition: ChainPosition, currentHeight: UInt32?) -> ConfirmationTime? {
        switch chainPosition {
        case .confirmed(let confirmationBlockTime, _):
            return ConfirmationTime(
                height: confirmationBlockTime.blockId.height,
                timestamp: confirmationBlockTime.confirmationTime,
                blockHash: String(describing: confirmationBlockTime.blockId.hash),
                currentHeight: currentHeight
            )
        case .unconfirmed:
            return nil
        }
    }
    
    private static func convertToBDKNetwork(_ network: Bark.Network) throws -> BitcoinDevKit.Network {
        switch network {
        case .bitcoin:
            return .bitcoin
        case .testnet:
            return .testnet
        case .signet:
            return .signet
        case .regtest:
            return .regtest
        @unknown default:
            throw BDKTransactionReaderError.unsupportedNetwork
        }
    }
}

// MARK: - Errors

enum BDKTransactionReaderError: Swift.Error {
    case unsupportedNetwork
    case syncFailed(Swift.Error)
    case invalidTransaction
}
