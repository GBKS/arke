//
//  BDKFeeEstimator.swift
//  Arké
//
//  Shadow BDK wallet used solely for send-flow onchain fee estimation.
//
//  Formerly BDKTransactionReader, which also served transaction history;
//  history now comes from bark's OnchainWallet.transactions() and this
//  wallet is created lazily on the first fee estimate (see
//  Docs/Features/BDK_Transaction_Reader_Removal.md). It exists only
//  because bark exposes no fee-estimation / drain-preview API on its
//  onchain wallet (feedback §2.5b) — once that ships, this file goes away
//  along with the bdk-swift dependency.
//
//  Wallet configuration (matches bark's built-in wallet):
//  - Wallet.createSingle() / loadSingle() — same as bark's Wallet::create_single()
//  - BIP86 (Taproot) derivation: m/86'/coin_type'/0'/0/*
//  - Single-descriptor wallet (no separate change descriptor)
//  - Empty BIP39 passphrase (matches bark's mnemonic.to_seed(""))
//

import Foundation
import BitcoinDevKit
import Bark

/// Read-only shadow BDK wallet for previewing onchain send fees.
///
/// Caveat: its coin selection is not guaranteed to match what bark's
/// internal wallet picks when `send()` actually runs, so estimates are
/// close but not authoritative — an exact upstream estimate API is the
/// tracked replacement.
final class BDKFeeEstimator {

    private let wallet: BitcoinDevKit.Wallet
    private let esploraClient: EsploraClient
    /// Kept so every applied update can be written: in bdk 1.0+ the wallet
    /// only stages changes and `persist` is what reaches SQLite. Until
    /// 2026-10-27 nothing ever persisted and every launch started blind
    /// (the shadow db held zero transactions after a day of estimates).
    private let persister: Persister

    /// True when init created a brand-new database — the caller must run
    /// one `sync(fullScan: true)` before estimates mean anything.
    let createdFreshDatabase: Bool

    /// When the last successful sync finished. Coins do not change while
    /// someone types an amount, so a sync within `minimumSyncInterval` of
    /// the last one is skipped and the estimate builds from memory.
    private var lastSyncedAt: Date?
    private let syncClock = NSLock()
    static let minimumSyncInterval: TimeInterval = 30

    // MARK: - Initialization

    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - network: Bark Network type
    ///   - esploraURL: Esplora server URL
    ///   - dataDir: Directory holding the wallet database
    init(mnemonic: String, network: Bark.Network, esploraURL: String, dataDir: URL) throws {
        let bdkNetwork = try Self.convertToBDKNetwork(network)
        // bdk-swift 3.x: key and descriptor constructors take the coarse
        // mainnet/testnet kind (it only selects the xprv/tprv prefix and the
        // BIP86 coin type); the full Network still drives the wallet itself.
        let bdkNetworkKind: NetworkKind = bdkNetwork == .bitcoin ? .main : .test

        // Must match bark's onchain wallet configuration: BIP86, empty
        // passphrase, single descriptor, external path m/86'/coin'/0'/0/*
        let mnemonicObj = try Mnemonic.fromString(mnemonic: mnemonic)
        let secretKey = DescriptorSecretKey(
            networkKind: bdkNetworkKind,
            mnemonic: mnemonicObj,
            password: nil  // Empty passphrase to match bark's mnemonic.to_seed("")
        )

        let descriptor = Descriptor.newBip86(
            secretKey: secretKey,
            keychainKind: .external,
            networkKind: bdkNetworkKind
        )

        let dbPath = dataDir.appendingPathComponent("bdk_transactions.db")
        let persister = try Persister.newSqlite(path: dbPath.path)

        if FileManager.default.fileExists(atPath: dbPath.path) {
            do {
                self.wallet = try BitcoinDevKit.Wallet.loadSingle(
                    descriptor: descriptor,
                    persister: persister
                )
                self.persister = persister
                self.createdFreshDatabase = false
            } catch {
                print("⚠️ [BDKFeeEstimator] Failed to load existing database, recreating: \(error)")
                try? FileManager.default.removeItem(at: dbPath)
                let newPersister = try Persister.newSqlite(path: dbPath.path)
                self.wallet = try BitcoinDevKit.Wallet.createSingle(
                    descriptor: descriptor,
                    network: bdkNetwork,
                    persister: newPersister
                )
                self.persister = newPersister
                self.createdFreshDatabase = true
            }
        } else {
            self.wallet = try BitcoinDevKit.Wallet.createSingle(
                descriptor: descriptor,
                network: bdkNetwork,
                persister: persister
            )
            self.persister = persister
            self.createdFreshDatabase = true
        }

        self.esploraClient = EsploraClient(url: esploraURL)
    }

    /// True when the last successful sync is recent enough to reuse
    private var isRecentlySynced: Bool {
        syncClock.lock(); defer { syncClock.unlock() }
        guard let lastSyncedAt else { return false }
        return Date().timeIntervalSince(lastSyncedAt) < Self.minimumSyncInterval
    }

    private func markSynced() {
        syncClock.lock(); defer { syncClock.unlock() }
        lastSyncedAt = Date()
    }

    // MARK: - Sync

    /// Sync the wallet so estimates reflect the current UTXO set, and write
    /// the result to disk. An incremental sync within
    /// `minimumSyncInterval` of the last successful one is skipped; a full
    /// scan always runs.
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
        if !fullScan, isRecentlySynced {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: BDKFeeEstimatorError.syncFailed(NSError(domain: "BDKFeeEstimator", code: -1)))
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
                    // Staged changes reach SQLite only here; without it the
                    // next launch starts from nothing and full-scans again
                    _ = try self.wallet.persist(persister: self.persister)
                    self.markSynced()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Fee Estimation

    /// Estimate fee for sending a specific amount to an address
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - amountSats: Amount to send in satoshis
    ///   - feeRateSatPerVb: Fee rate in sat/vB
    /// - Returns: Estimated fee in satoshis
    /// - Throws: Error if transaction building or fee calculation fails
    func estimateFee(address: String, amountSats: UInt64, feeRateSatPerVb: UInt64) throws -> UInt64 {
        let destAddress = try BitcoinDevKit.Address(address: address, network: wallet.network())
        let amount = BitcoinDevKit.Amount.fromSat(satoshi: amountSats)
        let feeRate = try BitcoinDevKit.FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)

        // Build transaction (doesn't broadcast, just estimates)
        let txBuilder = BitcoinDevKit.TxBuilder()
            .addRecipient(script: destAddress.scriptPubkey(), amount: amount)
            .feeRate(feeRate: feeRate)

        let psbt: Psbt
        do {
            psbt = try txBuilder.finish(wallet: wallet)
        } catch CreateTxError.InsufficientFunds(let needed, let available) {
            // Typed so callers can tell "this amount plus this fee does not
            // fit" from a real failure; after "Max" at one tier every faster
            // tier lands here by construction
            throw BDKFeeEstimatorError.insufficientFunds(neededSat: needed, availableSat: available)
        } catch CreateTxError.CoinSelection(let message) {
            throw BDKFeeEstimatorError.insufficientFunds(neededSat: nil, availableSat: nil, detail: message)
        }
        let tx = try psbt.extractTx()

        let feeAmount = try wallet.calculateFee(tx: tx)
        return feeAmount.toSat()
    }

    /// Calculate maximum sendable amount (send full balance) with fee deduction
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - feeRateSatPerVb: Fee rate in sat/vB
    /// - Returns: Tuple of (sendAmount, fee) both in satoshis
    /// - Throws: Error if transaction building or fee calculation fails
    func calculateMaxSendable(address: String, feeRateSatPerVb: UInt64) throws -> (sendAmount: UInt64, fee: UInt64) {
        let destAddress = try BitcoinDevKit.Address(address: address, network: wallet.network())
        let feeRate = try BitcoinDevKit.FeeRate.fromSatPerVb(satVb: feeRateSatPerVb)

        // Build drain transaction (sends entire balance minus fee)
        let txBuilder = BitcoinDevKit.TxBuilder()
            .drainWallet()
            .drainTo(script: destAddress.scriptPubkey())
            .feeRate(feeRate: feeRate)

        let psbt = try txBuilder.finish(wallet: wallet)
        let tx = try psbt.extractTx()

        let outputs = tx.output()
        guard outputs.count > 0 else {
            throw BDKFeeEstimatorError.invalidTransaction
        }

        let sendAmount = outputs[0].value.toSat()
        let feeAmount = try wallet.calculateFee(tx: tx)

        return (sendAmount, feeAmount.toSat())
    }

    // MARK: - Private Helpers

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
            throw BDKFeeEstimatorError.unsupportedNetwork
        }
    }
}

// MARK: - Errors

enum BDKFeeEstimatorError: Swift.Error {
    case unsupportedNetwork
    case syncFailed(Swift.Error)
    case invalidTransaction
    /// The shadow wallet cannot fund amount plus fee at the requested rate.
    /// Either the send really does not fit, or the shadow wallet is behind
    /// bark's (it only learns about addresses from its own scans)
    case insufficientFunds(neededSat: UInt64?, availableSat: UInt64?, detail: String? = nil)

    var isInsufficientFunds: Bool {
        if case .insufficientFunds = self { return true }
        return false
    }
}
