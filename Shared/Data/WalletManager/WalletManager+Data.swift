//
//  WalletManager+Data.swift
//  Arké
//
//  Data retrieval operations
//  Provides access to wallet data including balances, transactions, VTXOs, UTXOs, and blockchain info
//

import Foundation
import OSLog

extension WalletManager {
    
    // MARK: - Blockchain Data
    
    /// Get the latest Bitcoin block height
    /// - Returns: Current block height from the blockchain
    func getLatestBlockHeight() async throws -> Int {
        return try await getBlockHeightWithDeduplication()
    }
    
    private func getBlockHeightWithDeduplication() async throws -> Int {
        // Check cache first
        if let cached = cacheManager.blockHeight.value {
            Self.logger.debug("Using cached block height: \(cached)")
            return cached
        }
        
        return try await taskManager.execute(key: "blockHeight") {
            guard let wallet = self.wallet else {
                throw BarkErrorArke.commandFailed("Wallet not initialized")
            }
            let result = try await wallet.getLatestBlockHeight()
            
            // Update cache
            self.cacheManager.blockHeight.setValue(result)
            Self.logger.info("Fetched latest block height: \(result)")
            
            return result
        }
    }


    // MARK: - Balance Data
    
    /// Get the current Ark balance response
    /// Delegates to BalanceService for fresh balance information
    func getArkBalance() async throws -> ArkBalanceResponse {
        guard let balanceService = balanceService else {
            throw BarkErrorArke.commandFailed("Balance service not initialized")
        }
        
        return try await balanceService.getArkBalance()
    }
    
    /// Get the current onchain balance response
    /// Delegates to BalanceService for fresh balance information
    func getOnchainBalance() async throws -> OnchainBalanceResponse {
        guard let balanceService = balanceService else {
            throw BarkErrorArke.commandFailed("Balance service not initialized")
        }
        return try await balanceService.getOnchainBalance()
    }
    
    // MARK: - Onchain Transaction Data
    
    /// Get onchain transactions from the BDK wallet
    /// Delegates to OnchainTransactionService
    func getOnchainTransactions() async throws -> [OnchainTransactionModel] {
        guard let service = onchainTransactionService else {
            throw BarkErrorArke.commandFailed("Onchain transaction service not initialized")
        }
        return try await service.getTransactions()
    }
    
    /// Refresh onchain transactions from the blockchain
    func refreshOnchainTransactions() async {
        await onchainTransactionService?.refreshTransactions()
    }
}
