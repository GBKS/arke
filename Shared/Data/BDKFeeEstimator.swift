//
//  BDKFeeEstimator.swift
//  Arké
//
//  Shadow BDK wallet used solely for send-flow onchain fee estimation.
//
//  Formerly BDKTransactionReader, which also served transaction history;
//  history now comes from bark's OnchainWallet.transactions() and this
//  wallet is created lazily on the first fee estimate (see
//  Shared/Docs/Features/BDK_Transaction_Reader_Removal.md). It exists only
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

    /// True when init created a brand-new database — the caller must run
    /// one `sync(fullScan: true)` before estimates mean anything.
    let createdFreshDatabase: Bool

    // MARK: - Initialization

    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - network: Bark Network type
    ///   - esploraURL: Esplora server URL
    ///   - dataDir: Directory holding the wallet database
    init(mnemonic: String, network: Bark.Network, esploraURL: String, dataDir: URL) throws {
        let bdkNetwork = try Self.convertToBDKNetwork(network)

        // Must match bark's onchain wallet configuration: BIP86, empty
        // passphrase, single descriptor, external path m/86'/coin'/0'/0/*
        let mnemonicObj = try Mnemonic.fromString(mnemonic: mnemonic)
        let secretKey = DescriptorSecretKey(
            network: bdkNetwork,
            mnemonic: mnemonicObj,
            password: nil  // Empty passphrase to match bark's mnemonic.to_seed("")
        )

        let descriptor = Descriptor.newBip86(
            secretKey: secretKey,
            keychainKind: .external,
            network: bdkNetwork
        )

        let dbPath = dataDir.appendingPathComponent("bdk_transactions.db")
        let persister = try Persister.newSqlite(path: dbPath.path)

        if FileManager.default.fileExists(atPath: dbPath.path) {
            do {
                self.wallet = try BitcoinDevKit.Wallet.loadSingle(
                    descriptor: descriptor,
                    persister: persister
                )
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
                self.createdFreshDatabase = true
            }
        } else {
            self.wallet = try BitcoinDevKit.Wallet.createSingle(
                descriptor: descriptor,
                network: bdkNetwork,
                persister: persister
            )
            self.createdFreshDatabase = true
        }

        self.esploraClient = EsploraClient(url: esploraURL)
    }

    // MARK: - Sync

    /// Sync the wallet so estimates reflect the current UTXO set.
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

        let psbt = try txBuilder.finish(wallet: wallet)
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
}
