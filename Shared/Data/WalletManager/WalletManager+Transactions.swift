//
//  WalletManager+Transactions.swift
//  Arké
//
//  Transaction management
//  Provides access to unified transactions (Ark + onchain) and transaction metadata
//

import Foundation
import ArkeUI
import OSLog

extension WalletManager {
    
    // MARK: - Transaction Properties
    
    /// Get all transactions (Ark + onchain combined)
    /// Uses UnifiedTransactionService to merge both sources
    var transactions: [TransactionModel] {
        unifiedTransactionService?.allTransactions ?? []
    }
    
    /// Get Ark-only transactions (for debugging/admin views)
    var arkTransactionsOnly: [TransactionModel] {
        transactionService?.transactions ?? []
    }
    
    /// Get onchain-only transactions (for debugging/admin views)
    var onchainTransactionsOnly: [OnchainTransactionModel] {
        onchainTransactionService?.onchainTransactions ?? []
    }
    
    /// Get all onchain transactions
    var onchainTransactions: [OnchainTransactionModel] {
        onchainTransactionService?.onchainTransactions ?? []
    }
    
    /// Check if there are any onchain transactions
    var hasOnchainTransactions: Bool {
        onchainTransactionService?.hasTransactions ?? false
    }
    
    /// Get count of onchain transactions
    var onchainTransactionCount: Int {
        onchainTransactionService?.transactionCount ?? 0
    }
    
    /// Access to TransactionService for advanced operations
    var transactionServiceInstance: TransactionService? {
        transactionService
    }
    
    /// Access to UnifiedTransactionService for advanced operations
    var unifiedTransactionServiceInstance: UnifiedTransactionService? {
        unifiedTransactionService
    }
    
    // MARK: - Transaction Operations
    
    /// Update notes for a transaction
    /// - Parameters:
    ///   - txid: The transaction ID to update
    ///   - notes: The notes text to set (nil to clear notes, empty strings are converted to nil)
    /// - Throws: TransactionServiceError if validation fails or transaction not found
    func updateTransactionNotes(for txid: String, notes: String?) async throws {
        guard let transactionService = transactionService else {
            throw BarkErrorArke.commandFailed("Transaction service not initialized")
        }
        try await transactionService.updateNotes(for: txid, notes: notes)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after notes update")
    }
}
