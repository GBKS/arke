//
//  BarkWalletProtocol.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation
import ArkeUI
import Bark

// Protocol so both real and mock wallets can be used interchangeably.
// Refines ExitClaimWallet (the narrow surface ExitClaimSequence needs),
// so any wallet can be handed to the tested claim sequence directly.
protocol BarkWalletProtocol: ExitClaimWallet {
    var walletDir: URL { get }
    var networkConfig: NetworkConfig { get }
    var isMainnet: Bool { get }
    var currentNetworkName: String { get }
    
    /// Update the network configuration after wallet creation/import
    func updateNetworkConfig(_ newConfig: NetworkConfig)
    
    // MARK: - Wallet Lifecycle
    
    func createWallet(network: String?, arkServer: String?) async throws -> String
    func importWallet(network: String?, arkServer: String?, mnemonic: String) async throws -> String
    func deleteWallet() async throws -> String
    func getMnemonic() async throws -> String
    func openWalletIfNeeded() async -> Bool
    
    // MARK: - Balance & Address Operations
    
    func getArkBalance() async throws -> ArkBalanceResponse
    func getArkAddress() async throws -> String
    func getOnchainAddress() async throws -> String
    func getOnchainBalance() async throws -> OnchainBalanceResponse
    func getOnchainTransactions() async throws -> [OnchainTransactionModel]
    
    // MARK: - Configuration & Info
    
    func getArkInfo() async throws -> ArkInfoModel
    func getConfig() async throws -> ArkConfigModel
    func getLatestBlockHeight() async throws -> Int
    func getMovements() async throws -> String
    
    // MARK: - VTXO Operations (Basic)
    
    func getVTXOs() async throws -> [VTXOModel] // Returns unspent VTXOs
    //func refreshVTXOs(vtxo_ids: [String]) async throws -> String
    //func refreshVTXO(vtxo_id: String) async throws -> String
    //func exitVTXO(vtxo_id: String) async throws -> String
    func exitVTXO(vtxo_id: String, to address: String) async throws -> String
    
    // MARK: - VTXO Operations (Advanced - New in FFI)
    
    func allVtxos() async throws -> [Vtxo]
    func spendableVtxos() async throws -> [Vtxo]
    func getExpiringVtxos(thresholdBlocks: UInt32) async throws -> [Vtxo]
    func getVtxosToRefresh() async throws -> [Vtxo]
    func getVtxoById(vtxoId: String) async throws -> Vtxo
    func getFirstExpiringVtxoBlockheight() async throws -> UInt32?
    
    /**
     * Get the next block height when a refresh should be performed
     *
     * This is calculated as the first expiring VTXO height minus the refresh threshold.
     * Returns null if there are no VTXOs to refresh.
     */
    func getNextRequiredRefreshBlockheight() async throws -> UInt32?
    
    /**
     * Import a VTXO from its serialized form (hex or base64).
     *
     * Allows recovering VTXOs by importing their serialized form.
     * The parameter keeps its historical `vtxo_base64` name for foreign
     * binding compatibility (uniffi exposes parameter names), but hex as
     * returned by `vtxoEncoded(vtxoId:)` is accepted too.
     */
    func importVtxo(vtxoBase64: String) async throws

    /**
     * Hex-encoded serialization of the full VTXO (genesis chain included),
     * re-importable via `importVtxo(vtxoBase64:)`. Mirrors bark-rest
     * `GET /vtxos/{id}/encoded`.
     */
    func vtxoEncoded(vtxoId: String) async throws -> String
    
    // MARK: - UTXO Operations
    
    func getUTXOs() async throws -> [UTXOModel]
    
    // MARK: - Exit Operations (Basic)
    
    func startExit() async throws -> String
    func startExitForVTXOs(vtxo_ids: [String]) async throws -> String
    
    // MARK: - Exit Operations (Advanced - New in FFI)
    
    func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus]
    func syncExits() async throws
    func syncForceExitedVtxos() async throws
    func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction
    func listClaimableExits() async throws -> [ExitVtxo]
    func getExitVtxos() async throws -> [ExitVtxo]
    func hasPendingExits() async throws -> Bool
    func pendingExitsTotalSats() async throws -> UInt64
    func getExitStatus(vtxoId: String, includeHistory: Bool, includeTransactions: Bool) async throws -> ExitTransactionStatus?
    func allExitsClaimableAtHeight() async throws -> UInt32?
    
    // MARK: - Sync & Maintenance
    
    func sync() async throws
    func maintenanceRefresh() async throws -> String?

    // MARK: - Delegated / Non-interactive Operations

    func maintenanceDelegated() async throws
    func refreshVtxosDelegated(vtxoIds: [String]) async throws -> RoundState?
    
    // MARK: - Server Connection
    
    func refreshServer() async throws
    
    // MARK: - Round Management
    
    func cancelAllPendingRounds() async throws
    func cancelPendingRound(roundId: UInt32) async throws
    func pendingRoundStates() async throws -> [RoundState]
    func progressPendingRounds() async throws
    func syncPendingBoards() async throws
    func nextRoundStartTime() async throws -> UInt64
    
    // MARK: - Send Operations
    
    func send(to address: String, amount: Int) async throws -> String // Ark-to-ark payment
    func sendToOnchain(to address: String, amount: Int) async throws -> String // From Ark balance to onchain balance
    func sendOnchain(to address: String, amount: Int, feeRateSatPerVb: UInt64?) async throws -> String // From onchain balance to onchain balance
    
    // MARK: - Board Operations
    
    func board(amount: Int) async throws
    func boardAll() async throws -> String
    
    // MARK: - Fee Estimation

    func estimateArkoorPaymentFee(amountSats: UInt64) async throws  -> FeeEstimate
    func estimateBoardFee(amountSats: UInt64) async throws -> FeeEstimate
    func estimateLightningReceiveFee(amountSats: UInt64) async throws -> FeeEstimate
    func estimateLightningSendFee(amountSats: UInt64) async throws -> FeeEstimate
    func estimateOffboardFee(address: String, vtxoIds: [String]) async throws -> FeeEstimate
    func estimateRefreshFee(vtxoIds: [String]) async throws -> FeeEstimate
    func estimateSendToOnchainFee(address: String, amountSats: UInt64) async throws -> FeeEstimate // From Ark balance to onchain balance
    
    // MARK: - Lightning Operations (Basic)
    
    func payLightningInvoice(invoice: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus
    func getLightningInvoice(amountSats: UInt64, description: String?) async throws -> String
    func getLightningInvoiceStatus(invoice: String) async throws -> String
    func listLightningInvoices() async throws -> String
    func claimLightningInvoice(invoice: String) async throws -> String
    
    // MARK: - Lightning Operations (Enhanced - New in FFI)
    
    func payLightningOffer(offer: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus
    func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus
    func payLnurl(lnurl: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus
    func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> LightningSendStatus
    func isInvoicePaid(paymentHash: String) async throws -> Bool
    func lightningSendState(paymentHash: String) async throws -> LightningSendStatus
    /// Throws if the payment hash is unknown (v0.12+ replaces the old optional return)
    func lightningReceiveState(paymentHash: String) async throws -> LightningReceive
    @discardableResult
    func tryClaimLightningReceive(paymentHash: String, wait: Bool) async throws -> LightningReceive
    func claimableLightningReceiveBalanceSats() async throws -> UInt64
    func pendingLightningReceives() async throws  -> [LightningReceive]
    func cancelLightningReceive(paymentHash: String) async throws
    func allowLightningSendToExit(paymentHash: String) async throws
    func attemptLightningReceiveExit(paymentHash: String) async throws
    func stuckFailedLightningSends() async throws -> [LightningSend]
    
    // MARK: - Mailbox Operations
    
    func mailboxIdentifier() throws -> String
    func mailboxAuthorization() throws -> String
    
    // MARK: - Network Safety Methods
    
    func requiresMainnetWarning() -> Bool
    func validateMainnetOperation() throws
    func sendWithSafetyCheck(to address: String, amount: Int) async throws -> String
    func sendOnchainWithSafetyCheck(to address: String, amount: Int, feeRateSatPerVb: UInt64?) async throws -> String
    
    // MARK: - Utilities
    
    func extractTxFromPsbt(psbtBase64: String) throws  -> String
    func broadcastTx(txHex: String) async throws  -> String
    
    /**
     * Get a pull-based notification holder for this wallet.
     *
     * Call `next_notification()` in a loop to receive events.
     * Call `cancel_next_notification_wait()` to unblock a pending wait without
     * destroying the stream.
     */
    func notifications() -> NotificationHolder
    
    /**
     * Start a background daemon for the wallet.
     *
     * The daemon performs periodic syncs, exit progression and other
     * background work, using the onchain wallet bound at `Wallet.open()`.
     * It is stopped automatically when the wallet is dropped.
     * Calling this multiple times stops the previous daemon and starts a new one.
     */
    func runDaemon() async throws
    
    /**
     * Stop the wallet daemon.
     *
     * This explicitly stops any running background daemon, releasing all resources
     * and file locks. Call this before deleting a wallet to ensure clean shutdown.
     */
    func stopDaemon() async throws
}
