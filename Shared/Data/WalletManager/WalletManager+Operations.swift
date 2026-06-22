//
//  WalletManager+Operations.swift
//  Arké
//
//  Core wallet operations
//  Send, receive, board, exit, VTXO management, and round operations
//  Most operations delegate to WalletOperationsService or directly to the wallet
//

import Foundation
import Bark

extension WalletManager {
    
    // MARK: - Send/Receive/Board Operations
    
    func send(to address: String, amount: Int) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.send(to: address, amount: amount)
    }
    
    func sendOnchain(to address: String, amount: Int, feeRateSatPerVb: UInt64? = nil) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.sendOnchain(to: address, amount: amount, feeRateSatPerVb: feeRateSatPerVb)
    }
    
    func sendToOnchain(to address: String, amount: Int) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.sendToOnchain(to: address, amount: amount)
    }
    
    func board(amount: Int) async throws {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        try await walletOperationsService.board(amount: amount)
    }
    
    func boardAll() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.boardAll()
    }
    
    /// Synchronize wallet state with the ASP server
    /// Should be called after wallet creation/import and periodically to stay in sync
    func sync() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.sync()
    }
    
    // MARK: - Exit Operations
    
    /// Start the cooperative exit process for pending VTXOs
    /// Waits for the next round to complete the exit
    func startExit() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.startExit()
    }
    
    /// Exit a specific VTXO by its ID to a destination address
    func exitVTXO(vtxoId: String, to address: String) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.exitVTXO(vtxoId: vtxoId, to: address)
    }
    
    /// Progress unilateral exits through their state machine
    /// Broadcasts transactions, performs fee bumps, and advances exit states
    func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.progressExits(feeRateSatPerVb: feeRateSatPerVb)
    }
    
    /// Sync exit state with blockchain without progressing exits
    /// Updates exit status but doesn't broadcast or modify anything
    func syncExits() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.syncExits()
    }
    
    /// Get all VTXOs currently in exit process
    func getExitVtxos() async throws -> [ExitVtxo] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.getExitVtxos()
    }
    
    /// Start exit process for specific VTXOs
    func startExitForVTXOs(vtxo_ids: [String]) async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.startExitForVTXOs(vtxo_ids: vtxo_ids)
    }
    
    /// List all exits that are currently claimable
    func listClaimableExits() async throws -> [ExitVtxo] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.listClaimableExits()
    }
    
    /// Check if there are any pending exits
    func hasPendingExits() async throws -> Bool {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.hasPendingExits()
    }
    
    /// Get total amount in satoshis of all pending exits
    func pendingExitsTotalSats() async throws -> UInt64 {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.pendingExitsTotalSats()
    }
    
    /// Get detailed status for a specific exit
    func getExitStatus(vtxoId: String, includeHistory: Bool, includeTransactions: Bool) async throws -> ExitTransactionStatus? {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.getExitStatus(vtxoId: vtxoId, includeHistory: includeHistory, includeTransactions: includeTransactions)
    }
    
    /// Get the block height at which all exits will be claimable
    func allExitsClaimableAtHeight() async throws -> UInt32? {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.allExitsClaimableAtHeight()
    }
    
    /// Drain claimable exits to an onchain address
    func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.drainExits(vtxoIds: vtxoIds, address: address, feeRateSatPerVb: feeRateSatPerVb)
    }
    
    // MARK: - Round Operations
    
    /// Get all pending round states
    /// Returns information about rounds that are in progress or waiting
    func pendingRoundStates() async throws -> [RoundState] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.pendingRoundStates()
    }
    
    /// Progress pending rounds manually
    /// Normally handled automatically by RoundProgressionService
    func progressPendingRounds() async throws {
        guard let service = roundProgressionService else {
            throw BarkErrorArke.commandFailed("Round progression service not initialized")
        }
        try await service.progressRoundsManually()
    }
    
    /// Cancel a specific pending round
    /// - Parameter roundId: The ID of the round to cancel
    func cancelPendingRound(roundId: UInt32) async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.cancelPendingRound(roundId: roundId)
    }
    
    /// Get the next round start time
    /// - Returns: Unix timestamp (seconds since epoch) of when the next round is scheduled to start
    func nextRoundStartTime() async throws -> UInt64 {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.nextRoundStartTime()
    }
    
    // MARK: - VTXO Operations
    
    func getVTXOs() async throws -> [VTXOModel] {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getVTXOs()
    }
    
    func allVtxos() async throws -> [Vtxo] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.allVtxos()
    }
    
    /// Get VTXOs that need refreshing according to SDK logic
    /// Uses the SDK's sophisticated multi-factor analysis including:
    /// - Expiry urgency (must-refresh if expired or near hard threshold)
    /// - Exit depth thresholds (must-refresh if at/above max depth)
    /// - Economic viability (should-refresh if uneconomical to exit)
    /// - Dust detection (should-refresh if dust amount)
    /// - Returns empty if no urgent VTXOs exist (even if opportunistic candidates present)
    func getVTXOsNeedingRefresh() async throws -> [VTXOModel] {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        let vtxos = try await wallet.getVtxosToRefresh()
        return vtxos.map { VTXOModel(from: $0) }
    }
    
    // MARK: - UTXO & Config
    
    func getUTXOs() async throws -> [UTXOModel] {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getUTXOs()
    }
    
    func getConfig() async throws -> ArkConfigModel {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getConfig()
    }
    
    func getArkInfo() async throws -> ArkInfoModel {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getArkInfo()
    }
    
    // MARK: - Transaction Utilities
    
    /// Extract a raw transaction from a PSBT (Partially Signed Bitcoin Transaction)
    /// - Parameter psbtBase64: The PSBT encoded as base64
    /// - Returns: The extracted transaction as hex string
    func extractTxFromPsbt(psbtBase64: String) throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try wallet.extractTxFromPsbt(psbtBase64: psbtBase64)
    }
    
    /// Broadcast a raw transaction to the Bitcoin network
    /// - Parameter txHex: The raw transaction encoded as hex string
    /// - Returns: The transaction ID (txid) of the broadcast transaction
    func broadcastTx(txHex: String) async throws -> String {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.broadcastTx(txHex: txHex)
    }
    
    // MARK: - Wallet Notifications Stream
    
    /// Get a pull-based notification holder for real-time wallet events
    /// Call `next_notification()` in a loop to receive events
    /// Call `cancel_next_notification_wait()` to unblock a pending wait
    func notifications() -> NotificationHolder {
        guard let wallet = wallet else {
            fatalError("Wallet not initialized")
        }
        return wallet.notifications()
    }
    
    // MARK: - VTXO Refresh Operations
    
    /// Refresh multiple VTXOs to extend their expiry
    /// VTXOs must be refreshed periodically to remain valid
    func refreshVtxosDelegated(vtxo_ids: [String]) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.refreshVtxosDelegated(vtxo_ids: vtxo_ids)
    }
    
    /// Check if maintenance refresh is needed and schedule it
    /// Returns the block height when next refresh is needed, or nil if not needed
    func maybeScheduleMaintenanceRefresh() async throws -> UInt32? {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.maybeScheduleMaintenanceRefresh()
    }
    
    /// Perform maintenance refresh in delegated mode (non-interactive, automatic)
    func maintenanceDelegated() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.maintenanceDelegated()
    }
    
    /// Perform maintenance refresh including onchain wallet in delegated mode
    func maintenanceWithOnchainDelegated() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.maintenanceWithOnchainDelegated()
    }
    
    /// Refresh specific VTXOs (delegated/non-interactive)
    /// - Parameter vtxoIds: Array of VTXO IDs to refresh
    /// - Returns: The round state if a refresh round was created, nil otherwise
    func refreshVtxosDelegated(vtxoIds: [String]) async throws -> RoundState? {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
    }
    
    func refreshVtxoDelegated(vtxo_id: String) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.refreshVtxoDelegated(vtxo_id: vtxo_id)
    }
    
    /// Import a serialized VTXO into the wallet
    /// - Parameter vtxoBase64: Base64-encoded serialized VTXO
    func importVtxo(vtxoBase64: String) async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        try await wallet.importVtxo(vtxoBase64: vtxoBase64)
    }
    
    // MARK: - VTXO Refresh Service
    
    /// Manually trigger VTXO auto-refresh check (in addition to automatic checks)
    func triggerVTXORefreshCheck() {
        vtxoRefreshService?.triggerImmediateCheck()
    }
    
    /// Check if VTXO auto-refresh service is running
    var isVTXORefreshServiceRunning: Bool {
        vtxoRefreshService?.isRunning ?? false
    }
    
    /// Number of VTXOs auto-refreshed in current session
    var vtxoAutoRefreshCount: Int {
        vtxoRefreshService?.autoRefreshCount ?? 0
    }
    
    /// Manually refresh VTXOs (for UI triggers)
    func refreshVTXOsManually() async throws {
        try await vtxoRefreshService?.refreshManually()
    }
}
