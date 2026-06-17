//
//  WalletManager+Refresh.swift
//  Arké
//
//  Selective refresh operations
//  Convenience methods for refreshing individual wallet components
//  For full refresh, use refresh() from the main WalletManager file
//

import Foundation
import Bark
import OSLog

extension WalletManager {
    
    // MARK: - Server Connection
    
    /// Refresh connection to the ASP server
    func refreshServer() async {
        guard let wallet = wallet else {
            Self.logger.warning("Cannot refresh server: wallet not initialized")
            return
        }
        
        do {
            try await wallet.refreshServer()
        } catch {
            Self.logger.error("Failed to refresh server: \(error)")
            self.error = "Failed to refresh server connection: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Balance Refresh
    
    /// Refresh only Ark balance without updating other wallet data
    func refreshArkBalance() async {
        await balanceService?.refreshArkBalance()
        // Update local error state if balance service encountered an error
        if let balanceError = balanceService?.error {
            self.error = balanceError
        }
    }
    
    /// Refresh only onchain balance without updating other wallet data
    func refreshOnchainBalance() async {
        await balanceService?.refreshOnchainBalance()
        // Update local error state if balance service encountered an error
        if let balanceError = balanceService?.error {
            self.error = balanceError
        }
    }
    
    // MARK: - Address Management
    
    /// Load wallet addresses from the wallet
    func loadAddresses() async {
        await addressService?.loadAddresses()
        // Update local error state if address service encountered an error
        if let addressError = addressService?.error {
            self.error = addressError
        }
    }
    
    /// Generate a new address
    func generateNewAddress(type: AddressType, strategy: AddressGenerationStrategy = .userRequested) async throws -> PersistentAddress {
        guard let addressService = addressService else {
            throw BarkErrorArke.commandFailed("Address service not available")
        }
        return try await addressService.generateNewAddress(type: type, strategy: strategy)
    }
    
    // MARK: - Block Height Estimation
    
    /// Get estimated block height using cached data and ark info
    /// Automatically fetches missing data if needed
    func getEstimatedBlockHeight() async -> Int? {
        // Ensure we have both cached block height and ark info
        if cacheManager.blockHeight.value == nil {
            do {
                _ = try await getLatestBlockHeight()
            } catch {
                Self.logger.warning("Failed to fetch block height for estimation: \(error)")
            }
        }
        
        // Cache ArkInfo if needed using balance service
        if cacheManager.arkInfo.value == nil {
            await balanceService?.cacheArkInfoIfNeeded()
        }
        
        return cacheManager.getEstimatedBlockHeight()
    }
    
    // MARK: - Event-Driven Refresh
    
    /// Refresh balances and transactions after a round completes
    /// Called by RoundProgressionService and VTXORefreshService
    func refreshAfterRoundCompletion() async {
        await balanceService?.refreshAfterTransaction()
        await transactionService?.refreshTransactions()
        transactionVersion += 1
        
        // Notify refresh service that VTXOs changed (for notification scheduling)
        await vtxosDidChange()
    }
    
    /// Called whenever the VTXO set changes (send/receive/refresh/exit/claim)
    /// Triggers notification rescheduling in VTXORefreshService
    private func vtxosDidChange() async {
        await vtxoRefreshService?.scheduleNextRefreshNotification()
    }
    
    /// Refresh all balances when notification channel is lagging
    /// Called by WalletNotificationService
    func refreshBalances() async {
        await balanceService?.refreshBalances()
    }
}
