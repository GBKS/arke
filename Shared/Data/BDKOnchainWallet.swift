//
//  BDKOnchainWallet.swift
//  Arké
//
//  BDK-based onchain wallet that implements CustomOnchainWalletCallbacks
//  Provides full Bitcoin wallet functionality including transaction history
//
//  Based on actual BDK Swift 2.3.0 API from installed package

import Foundation
import BitcoinDevKit
import Bark

/// BDK-based Bitcoin wallet that integrates with Bark via CustomOnchainWalletCallbacks
/// Provides full transaction history and UTXO management that OnchainWallet.default() lacks
final class BDKOnchainWallet: @unchecked Sendable, CustomOnchainWalletCallbacks {
    
    // MARK: - Properties
    
    private let wallet: BitcoinDevKit.Wallet
    private let esploraClient: EsploraClient
    private let barkNetwork: Bark.Network
    private let persister: Persister
    private let descriptor: Descriptor
    private let changeDescriptor: Descriptor
    
    /// Serial queue for thread-safe access to BDK wallet operations
    private let queue = DispatchQueue(label: "com.arke.bdkwallet", qos: .userInitiated)
    
    /// Track if initial sync has completed to prevent returning stale balance data
    private var hasSyncedOnce: Bool = false
    private var syncCompletionContinuation: CheckedContinuation<Void, Never>?
    
    // MARK: - Initialization
    
    /// Initialize a BDK wallet from mnemonic (does not sync - call performInitialSync afterwards)
    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase (12 or 24 words)
    ///   - network: Bark Network type (.bitcoin, .testnet, .signet, .regtest)
    ///   - esploraURL: Esplora server URL for blockchain data
    ///   - dataDir: Directory to store wallet database
    ///   - stopGap: Number of consecutive unused addresses before stopping scan (default: 10)
    init(mnemonic: String, network: Bark.Network, esploraURL: String, dataDir: URL, stopGap: UInt64 = 10) throws {
        self.barkNetwork = network
        
        print("🔧 Initializing BDK wallet...")
        print("   Network: \(network)")
        print("   Esplora: \(esploraURL)")
        print("   Data dir: \(dataDir.path)")
        
        // Check if database already exists
        let dbPath = dataDir.appendingPathComponent("bdk_wallet.db")
        let dbExists = FileManager.default.fileExists(atPath: dbPath.path)
        print("   Database exists: \(dbExists)")
        if dbExists {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
               let size = attrs[.size] as? Int64 {
                print("   Database size: \(size) bytes")
            }
        }
        
        // Convert Bark Network to BDK Network
        let bdkNetwork = try Self.convertBarkNetworkToBDK(network)
        print("   BDK Network: \(bdkNetwork)")
        
        // Create descriptors from mnemonic
        print("   Creating descriptors from mnemonic (word count: \(mnemonic.split(separator: " ").count))...")
        let (desc, changeDesc) = try Self.createDescriptors(mnemonic: mnemonic, network: bdkNetwork)
        self.descriptor = desc
        self.changeDescriptor = changeDesc
        
        print("   ✅ Descriptors created")
        print("      External: \(String(describing: desc).prefix(80))...")
        print("      Change:   \(String(describing: changeDesc).prefix(80))...")
        
        // Create Esplora client
        self.esploraClient = EsploraClient(url: esploraURL)
        print("   ✅ Esplora client created")
        
        // Create persister (SQLite store)
        print("   Creating SQLite persister at: \(dbPath.path)")
        do {
            self.persister = try Persister.newSqlite(path: dbPath.path)
            print("   ✅ Database persister created")
        } catch {
            print("   ❌ Failed to create persister: \(error)")
            throw error
        }
        
        // Create new wallet OR load existing wallet
        // BDK 2.x distinguishes between creating and loading:
        // - Wallet() creates a NEW wallet (throws DataAlreadyExists if DB exists)
        // - Wallet.load() loads an EXISTING wallet (throws if DB doesn't exist)
        do {
            if dbExists {
                print("   Database exists - calling Wallet.load()...")
                self.wallet = try BitcoinDevKit.Wallet.load(
                    descriptor: descriptor,
                    changeDescriptor: changeDescriptor,
                    persister: persister
                )
                print("   ✅ Wallet.load() succeeded!")
                print("      → Loaded existing wallet from database")
            } else {
                print("   Database doesn't exist - calling Wallet() to create new...")
                self.wallet = try BitcoinDevKit.Wallet(
                    descriptor: descriptor,
                    changeDescriptor: changeDescriptor,
                    network: bdkNetwork,
                    persister: persister
                )
                print("   ✅ Wallet() succeeded!")
                print("      → Created new wallet")
            }
            print("✅ BDK wallet initialized (sync required - call performInitialSync)")
        } catch {
            print("   ❌ BDK Wallet initialization FAILED!")
            print("      Error type: \(type(of: error))")
            print("      Error: \(error)")
            print("      Database existed: \(dbExists)")
            throw error
        }
    }
    
    /// Perform initial sync after wallet creation
    /// - Parameters:
    ///   - stopGap: Number of consecutive unused addresses before stopping (default: 10)
    ///   - parallelRequests: Number of parallel requests to Esplora (default: 3)
    func performInitialSync(stopGap: UInt64 = 10, parallelRequests: UInt64 = 3) async throws {
        print("🔄 Performing initial sync...")
        try await Task {
            try self.syncInternal(fullScan: true, stopGap: stopGap, parallelRequests: parallelRequests)
        }.value
        
        // Mark sync as complete and resume any waiting continuations
        hasSyncedOnce = true
        syncCompletionContinuation?.resume()
        syncCompletionContinuation = nil
        
        print("✅ Initial sync complete")
    }
    
    /// Wait for initial sync to complete before returning
    /// This prevents returning stale balance data before the first sync
    private func waitForInitialSync() async {
        guard !hasSyncedOnce else { return }
        
        print("⏳ [BDK] Waiting for initial sync to complete before querying balance...")
        await withCheckedContinuation { continuation in
            if hasSyncedOnce {
                // Sync already completed while we were setting up the continuation
                continuation.resume()
            } else {
                // Store continuation to be resumed when sync completes
                syncCompletionContinuation = continuation
            }
        }
        print("✅ [BDK] Initial sync complete, proceeding with balance query")
    }
    
    // MARK: - Network Conversion
    
    /// Convert Bark.Network to BitcoinDevKit.Network
    private static func convertBarkNetworkToBDK(_ barkNetwork: Bark.Network) throws -> BitcoinDevKit.Network {
        switch barkNetwork {
        case .bitcoin:
            return .bitcoin
        case .testnet:
            return .testnet
        case .signet:
            return .signet
        case .regtest:
            return .regtest
        @unknown default:
            throw BDKWalletError.networkError("Unknown network type")
        }
    }
    
    // MARK: - Descriptor Creation
    
    /// Creates BIP86 (taproot) descriptors from mnemonic
    private static func createDescriptors(
        mnemonic: String,
        network: BitcoinDevKit.Network
    ) throws -> (Descriptor, Descriptor) {
        
        // Parse mnemonic into Mnemonic object
        let mnemonicObj = try Mnemonic.fromString(mnemonic: mnemonic)
        
        // Create descriptor secret key from mnemonic
        let descriptorSecretKey = DescriptorSecretKey(
            network: network,
            mnemonic: mnemonicObj,
            password: nil
        )
        
        
        // Create BIP86 descriptors using the built-in method
        // This is cleaner than manually constructing the descriptor strings
        
        let externalDescriptor = Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            keychainKind: KeychainKind.external,
            network: network
        )
        
        let changeDescriptor = Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            keychainKind: KeychainKind.internal,
            network: network
        )
        
        return (externalDescriptor, changeDescriptor)
    }
    
    // MARK: - CustomOnchainWalletCallbacks Implementation
    
    func getBalance() throws -> UInt64 {
        let balance = wallet.balance()
        return balance.total.toSat()
    }
    
    func prepareTx(destinations: [Bark.Destination], feeRateSatPerVb: UInt64) throws -> String {
        print("🔧 BDK: Preparing transaction...")
        print("   Destinations: \(destinations.count)")
        print("   Fee rate: \(feeRateSatPerVb) sat/vB")
        
        var txBuilder = TxBuilder()
        
        // Add all recipients
        for dest in destinations {
            let address = try Address(address: dest.address, network: wallet.network())
            let amount = Amount.fromSat(satoshi: dest.amountSats)
            txBuilder = txBuilder.addRecipient(script: address.scriptPubkey(), amount: amount)
        }
        
        // Set fee rate
        let feeRate = try FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)
        txBuilder = txBuilder.feeRate(feeRate: feeRate)
        
        // Note: RBF is enabled by default in BDK 2.x unless explicitly disabled
        // Transactions will have sequence numbers set to allow fee bumping
        
        // Build PSBT
        let psbt = try txBuilder.finish(wallet: wallet)
        
        // Serialize to base64 (serialize() already returns String for Psbt)
        let psbtBase64 = psbt.serialize()
        
        print("✅ BDK: Transaction prepared")
        
        return psbtBase64
    }
    
    func prepareDrainTx(address: String, feeRateSatPerVb: UInt64) throws -> String {
        print("🔧 BDK: Preparing drain transaction...")
        
        let destAddress = try Address(address: address, network: wallet.network())
        let feeRate = try FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)
        
        let txBuilder = TxBuilder()
            .drainWallet()
            .drainTo(script: destAddress.scriptPubkey())
            .feeRate(feeRate: feeRate)
        
        let psbt = try txBuilder.finish(wallet: wallet)
        let psbtBase64 = psbt.serialize()
        
        print("✅ BDK: Drain transaction prepared")
        
        return psbtBase64
    }
    
    func finishTx(psbtBase64: String) throws -> String {
        print("🔧 BDK: Finishing transaction...")
        
        let psbt = try Psbt(psbtBase64: psbtBase64)
        
        // Sign the PSBT
        _ = try wallet.sign(psbt: psbt)
        
        // Extract signed transaction
        let tx = try psbt.extractTx()
        let txData = tx.serialize()
        let txHex = txData.map { String(format: "%02x", $0) }.joined()
        
        let txid = tx.computeTxid()
        print("✅ BDK: Transaction finalized")
        print("   Txid: \(txid)")
        
        return txHex
    }
    
    func getWalletTx(txid: String) throws -> String? {
        // Get all transactions
        let transactions = wallet.transactions()
        
        for canonicalTx in transactions {
            let tx = canonicalTx.transaction
            let thisTxid = String(describing: tx.computeTxid())
            if thisTxid == txid {
                // Return the transaction as hex
                let txData = tx.serialize()
                return txData.map { String(format: "%02x", $0) }.joined()
            }
        }
        
        return nil
    }
    
    func getWalletTxConfirmedBlock(txid: String) throws -> Bark.BlockRef? {
        let transactions = wallet.transactions()
        
        for canonicalTx in transactions {
            let tx = canonicalTx.transaction
            let thisTxid = String(describing: tx.computeTxid())
            
            if thisTxid == txid {
                // Check chain position
                switch canonicalTx.chainPosition {
                case .confirmed(let confirmationBlockTime, _):
                    return Bark.BlockRef(
                        height: confirmationBlockTime.blockId.height,
                        hash: String(describing: confirmationBlockTime.blockId.hash)
                    )
                case .unconfirmed:
                    return nil
                }
            }
        }
        
        return nil
    }
    
    func getSpendingTx(outpoint: Bark.OutPoint) throws -> String? {
        let transactions = wallet.transactions()
        
        for canonicalTx in transactions {
            let transaction = canonicalTx.transaction
            
            // Check if this transaction spends the outpoint
            let inputs = transaction.input()
            for input in inputs {
                let prevOut = input.previousOutput
                let prevOutTxid = String(describing: prevOut.txid)
                if prevOutTxid == outpoint.txid && prevOut.vout == outpoint.vout {
                    let txData = transaction.serialize()
                    return txData.map { String(format: "%02x", $0) }.joined()
                }
            }
        }
        
        return nil
    }
    
    func makeSignedP2aCpfp(params: Bark.CpfpParams) throws -> String {
        // CPFP implementation is complex - not needed for basic functionality
        print("⚠️ BDK: CPFP not implemented (optional feature)")
        throw BDKWalletError.notImplemented("CPFP transactions")
    }
    
    func storeSignedP2aCpfp(txHex: String) throws {
        // CPFP storage - not needed for basic functionality
        print("⚠️ BDK: CPFP storage not implemented (optional feature)")
    }
    
    // MARK: - Additional Public Methods
    
    /// Sync wallet with blockchain (async version)
    /// - Parameters:
    ///   - fullScan: If true, performs a full scan. If false, performs incremental sync.
    ///   - stopGap: Number of consecutive unused addresses before stopping (default: 10)
    ///   - parallelRequests: Number of parallel requests to Esplora (default: 3)
    @discardableResult
    func sync(fullScan: Bool = false, stopGap: UInt64 = 10, parallelRequests: UInt64 = 3) async throws -> UInt64 {
        try await Task {
            try self.syncInternal(fullScan: fullScan, stopGap: stopGap, parallelRequests: parallelRequests)
        }.value
        return try getBalance()
    }
    
    /// Sync wallet with blockchain (synchronous version for CustomOnchainWalletCallbacks compatibility)
    /// - Parameters:
    ///   - fullScan: If true, performs a full scan. If false, performs incremental sync.
    ///   - stopGap: Number of consecutive unused addresses before stopping (default: 10)
    ///   - parallelRequests: Number of parallel requests to Esplora (default: 3)
    @discardableResult
    func syncSync(fullScan: Bool = false, stopGap: UInt64 = 10, parallelRequests: UInt64 = 3) throws -> UInt64 {
        try syncInternal(fullScan: fullScan, stopGap: stopGap, parallelRequests: parallelRequests)
        return try getBalance()
    }
    
    /// Internal sync method with configurable parameters
    private func syncInternal(fullScan: Bool = false, stopGap: UInt64 = 10, parallelRequests: UInt64 = 3) throws {
        if fullScan {
            // Create full scan request (slower, but finds all addresses)
            let fullScanRequest = try wallet.startFullScan().build()
            
            // Perform full scan with Esplora
            let update = try esploraClient.fullScan(
                request: fullScanRequest,
                stopGap: stopGap,
                parallelRequests: parallelRequests
            )
            
            // Apply the update
            try wallet.applyUpdate(update: update)
        } else {
            // Create sync request for incremental sync (faster)
            // Uses revealed script pubkeys (addresses we've already generated)
            let syncRequest = try wallet.startSyncWithRevealedSpks().build()
            
            // Perform sync with Esplora
            let update = try esploraClient.sync(
                request: syncRequest,
                parallelRequests: parallelRequests
            )
            
            // Apply the update
            try wallet.applyUpdate(update: update)
        }
    }
    
    /// Generate a new receiving address
    func newAddress() throws -> String {
        let addressInfo = wallet.revealNextAddress(keychain: KeychainKind.external)
        return String(describing: addressInfo.address)
    }
    
    /// Send Bitcoin to an address
    /// - Returns: Transaction ID if successful
    /// - Throws: BDKWalletError.broadcastFailed with PSBT if broadcast fails
    func send(address: String, amountSats: UInt64, feeRateSatPerVb: UInt64) throws -> String {
        print("🔧 BDK: Sending Bitcoin...")
        print("   To: \(address)")
        print("   Amount: \(amountSats) sats")
        
        let destAddress = try Address(address: address, network: wallet.network())
        let amount = Amount.fromSat(satoshi: amountSats)
        let feeRate = try FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)
        
        // Build and sign transaction
        let txBuilder = TxBuilder()
            .addRecipient(script: destAddress.scriptPubkey(), amount: amount)
            .feeRate(feeRate: feeRate)
        
        let psbt = try txBuilder.finish(wallet: wallet)
        _ = try wallet.sign(psbt: psbt)
        
        let tx = try psbt.extractTx()
        let txid = String(describing: tx.computeTxid())
        
        // Attempt broadcast with error handling
        do {
            try esploraClient.broadcast(transaction: tx)
            print("✅ BDK: Transaction broadcast - Txid: \(txid)")
            return txid
        } catch {
            // Broadcast failed - return PSBT so it can be re-broadcast later
            let psbtBase64 = psbt.serialize()
            print("❌ BDK: Broadcast failed - \(error.localizedDescription)")
            print("   PSBT saved for later broadcast: \(psbtBase64.prefix(50))...")
            throw BDKWalletError.broadcastFailed(psbt: psbtBase64, txid: txid, underlyingError: error)
        }
    }
    
    /// Broadcast a raw transaction hex
    /// - Parameter txHex: Transaction in hex format
    /// - Returns: Transaction ID if successful
    func broadcastTransaction(txHex: String) throws -> String {
        // Convert hex to bytes
        let txBytes = try hexToBytes(txHex)
        
        // Deserialize transaction
        let tx = try Transaction(transactionBytes: Data(txBytes))
        let txid = String(describing: tx.computeTxid())
        
        // Broadcast
        do {
            try esploraClient.broadcast(transaction: tx)
            print("✅ BDK: Transaction broadcast - Txid: \(txid)")
            return txid
        } catch {
            print("❌ BDK: Broadcast failed - \(error.localizedDescription)")
            throw BDKWalletError.broadcastFailed(psbt: nil, txid: txid, underlyingError: error)
        }
    }
    
    /// Bump the fee of an RBF transaction
    /// - Parameters:
    ///   - txid: Transaction ID to bump
    ///   - newFeeRateSatPerVb: New fee rate (must be higher than original)
    /// - Returns: New transaction ID
    func bumpFee(txid: String, newFeeRateSatPerVb: UInt64) throws -> String {
        print("🔧 BDK: Bumping fee for transaction \(txid)")
        print("   New fee rate: \(newFeeRateSatPerVb) sat/vB")
        
        // Find the transaction
        let transactions = wallet.transactions()
        var targetTx: BitcoinDevKit.Transaction?
        
        for canonicalTx in transactions {
            let tx = canonicalTx.transaction
            let thisTxid = String(describing: tx.computeTxid())
            if thisTxid == txid {
                targetTx = tx
                break
            }
        }
        
        guard targetTx != nil else {
            throw BDKWalletError.invalidTransaction
        }
        
        // Create RBF transaction with higher fee
        let newFeeRate = try FeeRate.fromSatPerVb(satVb: newFeeRateSatPerVb)
        let txBuilder = TxBuilder()
            .feeRate(feeRate: newFeeRate)
        
        // Build, sign and broadcast
        let psbt = try txBuilder.finish(wallet: wallet)
        _ = try wallet.sign(psbt: psbt)
        let newTx = try psbt.extractTx()
        
        do {
            try esploraClient.broadcast(transaction: newTx)
            let newTxid = String(describing: newTx.computeTxid())
            print("✅ BDK: Fee bumped - New Txid: \(newTxid)")
            return newTxid
        } catch {
            let newTxid = String(describing: newTx.computeTxid())
            let psbtBase64 = psbt.serialize()
            throw BDKWalletError.broadcastFailed(psbt: psbtBase64, txid: newTxid, underlyingError: error)
        }
    }
    
    /// Helper to convert hex string to bytes
    private func hexToBytes(_ hex: String) throws -> [UInt8] {
        var bytes = [UInt8]()
        var hexStr = hex
        
        // Remove any whitespace
        hexStr = hexStr.replacingOccurrences(of: " ", with: "")
        
        // Must be even length
        guard hexStr.count % 2 == 0 else {
            throw BDKWalletError.invalidTransaction
        }
        
        var index = hexStr.startIndex
        while index < hexStr.endIndex {
            let nextIndex = hexStr.index(index, offsetBy: 2)
            let byteString = String(hexStr[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                throw BDKWalletError.invalidTransaction
            }
            bytes.append(byte)
            index = nextIndex
        }
        
        return bytes
    }
    
    /// Get detailed balance information
    /// Waits for initial sync to complete to avoid returning stale data
    func getOnchainBalance() async throws -> Bark.OnchainBalance {
        // Wait for initial sync to complete before querying balance
        await waitForInitialSync()
        
        let balance = wallet.balance()
        
        return Bark.OnchainBalance(
            confirmedSats: balance.confirmed.toSat(),
            pendingSats: balance.trustedPending.toSat() + balance.untrustedPending.toSat(),
            totalSats: balance.total.toSat()
        )
    }
    
    /// List all unspent outputs (UTXOs)
    /// Returns UTXOs owned by this wallet
    func listUnspentOutputs() throws -> [LocalOutput] {
        return wallet.listUnspent()
    }
    
    /// Get UTXO details in a more user-friendly format
    func getUTXODetails() throws -> [(outpoint: String, amount: UInt64, confirmations: UInt32?)] {
        let utxos = wallet.listUnspent()
        var result: [(outpoint: String, amount: UInt64, confirmations: UInt32?)] = []
        
        for utxo in utxos {
            let outpoint = "\(utxo.outpoint.txid):\(utxo.outpoint.vout)"
            let amount = utxo.txout.value.toSat()
            
            // Try to get confirmations from the transaction
            let confirmations: UInt32? = {
                // Get the transaction to find its confirmation status
                let transactions = wallet.transactions()
                for canonicalTx in transactions {
                    let tx = canonicalTx.transaction
                    let txid = String(describing: tx.computeTxid())
                    if txid == String(describing: utxo.outpoint.txid) {
                        switch canonicalTx.chainPosition {
                        case .confirmed(let confirmationBlockTime, _):
                            // Return height (UI should calculate actual confirmations)
                            return confirmationBlockTime.blockId.height
                        case .unconfirmed:
                            return 0
                        }
                    }
                }
                return nil
            }()
            
            result.append((outpoint: outpoint, amount: amount, confirmations: confirmations))
        }
        
        return result
    }
    
    /// Get current blockchain tip height (for confirmation calculations)
    func getCurrentBlockHeight() async -> UInt32? {
        // Query Esplora for current tip height.
        // If network query fails, fall back to wallet's latest checkpoint height.
        return await Task {
            do {
                return try self.esploraClient.getHeight()
            } catch {
                return self.wallet.latestCheckpoint().height
            }
        }.value
    }
    
    /// List all wallet transactions - THIS IS THE KEY FEATURE!
    /// Returns transactions in reverse chronological order (newest first)
    /// - Parameters:
    ///   - includeRaw: Reserved for future use (raw transaction data)
    ///   - currentHeight: Current blockchain height for accurate confirmation counts (optional)
    func listTransactions(includeRaw: Bool = false, currentHeight: UInt32? = nil) throws -> [OnchainTransactionModel] {
        // Get all canonical transactions from BDK
        let canonicalTransactions = wallet.transactions()
        
        // Convert to our model
        var transactions: [OnchainTransactionModel] = []
        
        for canonicalTx in canonicalTransactions {
            let tx = canonicalTx.transaction
            let txid = String(describing: tx.computeTxid())
            
            // Use BDK's sentAndReceived method to get accurate amounts
            let sentAndReceived = wallet.sentAndReceived(tx: tx)
            let received = sentAndReceived.received.toSat()
            let sent = sentAndReceived.sent.toSat()
            
            // Calculate fee if this is a transaction we sent
            let fee: UInt64? = {
                // Only calculate fee for transactions where we sent funds
                if sent > 0 {
                    // Try BDK's calculateFee first
                    do {
                        let feeAmount = try wallet.calculateFee(tx: tx)
                        let feeSats = feeAmount.toSat()
                        print("✅ Fee calculated via BDK for tx \(String(txid.prefix(8))): \(feeSats) sats")
                        return feeSats
                    } catch {
                        print("⚠️ BDK calculateFee failed for tx \(String(txid.prefix(8))): \(error)")
                        print("   Attempting manual fee calculation...")
                        
                        // Fallback: Calculate fee manually
                        // For a transaction we sent: fee = sent - received
                        // This works because:
                        // - sent = total inputs we owned
                        // - received = total outputs we now own (change)
                        // - fee = what we lost = sent - received - amount_to_recipient
                        // But since amount_to_recipient is part of sent but not received,
                        // we can simplify to: fee = sent - received when sent > received
                        if sent > received {
                            let calculatedFee = sent - received
                            print("✅ Manually calculated fee: \(calculatedFee) sats (sent: \(sent), received: \(received))")
                            return calculatedFee
                        } else {
                            print("❌ Cannot calculate fee: sent (\(sent)) <= received (\(received))")
                            return nil
                        }
                    }
                }
                return nil
            }()
            
            // Extract confirmation info
            let confirmationTime: ConfirmationTime? = {
                switch canonicalTx.chainPosition {
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
            }()
            
            let model = OnchainTransactionModel(
                txid: txid,
                received: received,
                sent: sent,
                fee: fee,
                confirmationTime: confirmationTime
            )
            
            transactions.append(model)
        }
        
        // Sort: unconfirmed first, then by timestamp descending
        return transactions.sorted { tx1, tx2 in
            if tx1.confirmationTime == nil && tx2.confirmationTime != nil {
                return true
            }
            if tx1.confirmationTime != nil && tx2.confirmationTime == nil {
                return false
            }
            if let time1 = tx1.confirmationTime?.timestamp,
               let time2 = tx2.confirmationTime?.timestamp {
                return time1 > time2
            }
            return false
        }
    }
}

// MARK: - Error Types

enum BDKWalletError: Error, LocalizedError {
    case walletNotInitialized
    case psbtNotFinalized
    case notImplemented(String)
    case invalidTransaction
    case insufficientFunds
    case networkError(String)
    case broadcastFailed(psbt: String?, txid: String, underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .walletNotInitialized:
            return "BDK wallet not initialized"
        case .psbtNotFinalized:
            return "PSBT could not be finalized - missing signatures or inputs"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .invalidTransaction:
            return "Invalid transaction"
        case .insufficientFunds:
            return "Insufficient funds for transaction"
        case .networkError(let message):
            return "Network error: \(message)"
        case .broadcastFailed(let psbt, let txid, let error):
            var msg = "Transaction broadcast failed: \(error.localizedDescription)\nTxid: \(txid)"
            if psbt != nil {
                msg += "\nSigned PSBT available for manual broadcast"
            }
            return msg
        }
    }
}
