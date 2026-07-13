//
//  TransactionService+Utilities.swift
//  Arke
//
//  Utility methods for transaction management.
//  Includes cleanup, lookup, and helper conversion functions.
//

import Foundation
import SwiftData
import ArkeUI
import OSLog

// MARK: - TransactionService+Utilities

extension TransactionService {
    
    // MARK: Transaction Management
    
    /// Clear all persisted transactions from SwiftData
    func clearTransactionModels() async {
        guard let modelContext = modelContext else {
            Self.logger.warning("No model context available for clearing transactions")
            return
        }
        
        do {
            // Fetch all persisted transactions
            let descriptor = FetchDescriptor<PersistentTransaction>()
            let persistentTransactions = try modelContext.fetch(descriptor)
            
            // Count tagged transactions before deletion
            let taggedTransactionsCount = persistentTransactions.filter { !(($0.tagAssignments ?? []).isEmpty) }.count
            let totalTagAssignments = persistentTransactions.flatMap { $0.tagAssignments ?? [] }.count
            
            // Delete all transactions (cascade will handle tag assignments)
            for transaction in persistentTransactions {
                modelContext.delete(transaction)
            }
            
            // Save changes
            try modelContext.save()
            
            // Reset loaded state
            hasLoadedTransactions = false
            
            Self.logger.info("Cleared \(persistentTransactions.count) persisted transactions")
            if totalTagAssignments > 0 {
                Self.logger.info("Also cleared \(totalTagAssignments) tag assignments from \(taggedTransactionsCount) tagged transactions")
            }
            
        } catch {
            Self.logger.error("Failed to clear persisted transactions: \(error)")
        }
    }
    
    /// Clean up orphaned transactions that no longer exist on the server but have been locally tagged
    /// This is a manual cleanup method that can be called when needed
    func cleanupOrphanedTaggedTransactions() async {
        guard let modelContext = modelContext else {
            Self.logger.warning("No model context available for cleaning orphaned transactions")
            return
        }
        
        do {
            // Get all transactions with tags
            let taggedDescriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { transaction in
                    transaction.tagAssignments != nil
                }
            )
            let taggedTransactions = try modelContext.fetch(taggedDescriptor)
            
            // Filter for those that actually have tags (since relationship is optional)
            let actuallyTaggedTransactions = taggedTransactions.filter { !(($0.tagAssignments ?? []).isEmpty) }
            
            if !actuallyTaggedTransactions.isEmpty {
                Self.logger.info("Found \(actuallyTaggedTransactions.count) tagged transactions")
                
                // Refresh from server to identify which ones still exist
                let serverOutput = try await wallet.getMovements()
                let serverTxids = await getServerTransactionIds(from: serverOutput)
                
                let orphanedTaggedTransactions = actuallyTaggedTransactions.filter { !serverTxids.contains($0.txid) }
                
                if !orphanedTaggedTransactions.isEmpty {
                    let totalOrphanedTags = orphanedTaggedTransactions.flatMap { $0.tagAssignments ?? [] }.count
                    
                    Self.logger.warning("Found \(orphanedTaggedTransactions.count) orphaned tagged transactions with \(totalOrphanedTags) total tag assignments")
                    Self.logger.warning("These transactions no longer exist on the server but have local tags")
                    
                    // Log details for manual review
                    for transaction in orphanedTaggedTransactions {
                        let tagNames = transaction.associatedTags.map { $0.displayName }.joined(separator: ", ")
                        let transactionModel = TransactionModel(from: transaction)
                        Self.logger.warning("  \(transaction.txid): \(transactionModel.formattedAmount) [\(tagNames)]")
                    }
                    
                    // Note: We don't automatically delete these - that's a policy decision for the app
                    // The user might want to keep them for historical tracking
                }
            }
            
        } catch {
            Self.logger.error("Failed to cleanup orphaned tagged transactions: \(error)")
        }
    }
    
    /// Extract transaction IDs from server data for comparison
    private func getServerTransactionIds(from output: String) async -> Set<String> {
        guard let jsonData = output.data(using: .utf8) else {
            return Set()
        }
        
        do {
            let movements = try JSONDecoder().decode([MovementData].self, from: jsonData)
            let transactionDataList = await movements.asyncFlatMap { movement in
                await parseMovementToTransactions(movement)
            }
            return Set(transactionDataList.map { $0.txid })
        } catch {
            Self.logger.error("Failed to parse server transaction IDs: \(error)")
            return Set()
        }
    }
    
    /// Get raw transactions data from wallet
    func getTransactions() async throws -> String {
        return try await wallet.getMovements()
    }
    
    // MARK: Persistence Lookup
    
    /// Get PersistentTransaction by txid (used by UnifiedTransactionService)
    /// - Parameter txid: The transaction ID to look up
    /// - Returns: The PersistentTransaction if found, nil otherwise
    func getPersistentTransaction(txid: String) -> PersistentTransaction? {
        guard let modelContext = modelContext else {
            Self.logger.warning("No model context available for persistence lookup")
            return nil
        }
        
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    // MARK: Type Conversion Helpers
    
    /// Convert TransactionStatusEnum to String representation
    static func stringValue(for status: TransactionStatusEnum) -> String {
        switch status {
        case .confirmed: return "confirmed"
        case .pending: return "pending"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }
    
    /// Convert TransactionTypeEnum to String representation
    static func stringValue(for type: TransactionTypeEnum) -> String {
        switch type {
        case .sent: return "sent"
        case .received: return "received"
        case .transfer: return "transfer"
        case .pending: return "pending"
        }
    }
    
}
