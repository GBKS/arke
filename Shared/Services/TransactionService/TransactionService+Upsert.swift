//
//  TransactionService+Upsert.swift
//  Arke
//
//  Transaction upsert operations (insert or update).
//  Handles syncing server data with local SwiftData store.
//

import Foundation
import SwiftData
import ArkeUI
import os

// MARK: - TransactionService+Upsert

extension TransactionService {
    
    // MARK: Public Methods
    
    /*
     Transaction ID Format:
     - All transactions: "movement_{id}"
     
     Note: Due to API limitation (addresses without amounts), we cannot create separate
     transactions for multi-destination sends. All movements map to a single transaction.
     
     Old format used "movement_{id}_recipient_{index}" for multi-recipient breakdowns,
     but this is no longer possible with the new API structure.
    */
    
    /// Upsert transactions from server data (insert new, update existing)
    func upsertTransactionsFromServerData(_ output: String) async {
        guard let modelContext = modelContext else {
            Self.logger.error("🚨 No model context available for upserting transactions")
            return
        }
        
        // Cleanup old unmatched pending metadata (Phase 0: Send Metadata Enhancement)
        cleanupOldPendingMetadata()
        
        guard let jsonData = output.data(using: .utf8) else {
            Self.logger.error("❌ Failed to convert output to data")
            return
        }
        
        do {
            let movements = try JSONDecoder().decode([MovementData].self, from: jsonData)
            
            // Get existing transactions to check for updates/new ones
            let existingDescriptor = FetchDescriptor<PersistentTransaction>()
            let existingTransactions = try modelContext.fetch(existingDescriptor)
            
            // Build dictionary and remove duplicates
            var existingTransactionDict = try buildExistingTransactionDictionary(
                from: existingTransactions,
                modelContext: modelContext
            )
            
            var upsertedCount = 0
            var updatedCount = 0
            var preservedTagCount = 0
            var autoAssignedCount = 0
            
            for movement in movements {
                let movementTransactions = await parseMovementToTransactions(movement)
                
                // Debug: Check if movement produces multiple transactions
                if movementTransactions.count > 1 {
                    Self.logger.warning("⚠️ Movement \(movement.id) produced \(movementTransactions.count) transactions")
                }
                
                for transactionData in movementTransactions {
                    // Check if this transaction already exists in the database OR was just inserted in this batch
                    if let existingTransaction = existingTransactionDict[transactionData.txid] {
                        // Update existing transaction if data has changed
                        let hasChanges = updateExistingTransaction(
                            existingTransaction,
                            with: transactionData
                        )
                        
                        // Re-apply pending metadata for recently matched transactions
                        // This catches metadata changes made after the initial match
                        applyPendingMetadata(to: existingTransaction)
                        
                        // Preserve existing tag assignments - they survive server updates
                        // No need to explicitly restore them as they're already attached to the existing transaction
                        // The SwiftData relationship will maintain the connections automatically
                        if !(existingTransaction.tagAssignments ?? []).isEmpty {
                            preservedTagCount += (existingTransaction.tagAssignments ?? []).count
                        }
                        
                        if hasChanges {
                            updatedCount += 1
                        }
                    } else {
                        // Insert new transaction
                        let newTransaction = createPersistentTransaction(from: transactionData)
                        modelContext.insert(newTransaction)
                        
                        // Apply pending metadata if available (Phase 0: Send Metadata Enhancement)
                        applyPendingMetadata(to: newTransaction)
                        
                        // Link transaction to address
                        await linkTransactionToAddress(newTransaction)
                        
                        // Add to dictionary to prevent duplicates within this batch
                        existingTransactionDict[transactionData.txid] = newTransaction
                        
                        upsertedCount += 1
                        
                        // Auto-assign contact if transaction has an address
                        // For Lightning payments, prioritize lightningOffer (BOLT12 offer)
                        // over the invoice address for better contact matching
                        // Only for sent transactions - received_on_addresses are our own addresses, not the sender's
                        if transactionData.type == .sent {
                            var wasAutoAssigned = false
                            
                            // Try lightningOffer first (BOLT12 offer)
                            if let lightningOffer = transactionData.lightningOffer {
                                wasAutoAssigned = await autoAssignContactForAddress(lightningOffer, transaction: newTransaction, modelContext: modelContext)
                                if wasAutoAssigned {
                                    autoAssignedCount += 1
                                }
                            }
                            
                            // Fallback to regular address if not already assigned
                            if !wasAutoAssigned, let address = transactionData.address {
                                wasAutoAssigned = await autoAssignContactForAddress(address, transaction: newTransaction, modelContext: modelContext)
                                if wasAutoAssigned {
                                    autoAssignedCount += 1
                                }
                            }
                        }
                    }
                }
                
                // Establish movement-onchain links after processing all transactions in this movement
                let movementTxid = "movement_\(movement.id)"
                linkingService?.establishLinksForMovement(
                    movementTxid: movementTxid,
                    movementId: movement.id,
                    metadataJson: movement.metadataJson,
                    subsystemName: movement.subsystemName,
                    category: movement.category,
                    context: modelContext
                )
            }
            
            // Handle orphaned transactions (exist locally but not in server data)
            let orphanedTagCount = await handleOrphanedTransactions(
                existingTransactions: existingTransactions,
                movements: movements
            )
            
            // Save changes
            try modelContext.save()
            
            Self.logger.info("💾 Successfully saved \(upsertedCount) new, \(updatedCount) updated transactions")
            if autoAssignedCount > 0 {
                Self.logger.info("🔗 Auto-assigned \(autoAssignedCount) transaction(s) to contacts based on address matching")
            }
            Self.logger.info("🏷️ Preserved \(preservedTagCount) tag assignments across updates")
            if orphanedTagCount > 0 {
                Self.logger.info("🏷️ Found \(orphanedTagCount) tag assignments on orphaned transactions")
            }
            
        } catch {
            Self.logger.error("❌ Failed to upsert transactions: \(error)")
            self.error = "Failed to process transactions: \(error)"
        }
    }
    
    // MARK: Private Helpers
    
    /// Build dictionary of existing transactions, removing duplicates
    private func buildExistingTransactionDictionary(
        from existingTransactions: [PersistentTransaction],
        modelContext: ModelContext
    ) throws -> [String: PersistentTransaction] {
        var existingTransactionDict: [String: PersistentTransaction] = [:]
        var duplicateCount = 0
        
        for transaction in existingTransactions {
            if existingTransactionDict[transaction.txid] != nil {
                duplicateCount += 1
                Self.logger.warning("⚠️ Found duplicate txid in database: \(transaction.txid)")
                // Delete the duplicate from the database
                modelContext.delete(transaction)
            } else {
                existingTransactionDict[transaction.txid] = transaction
            }
        }
        
        if duplicateCount > 0 {
            Self.logger.info("🗑️ Removed \(duplicateCount) duplicate transactions from database")
            try modelContext.save()
        }
        
        return existingTransactionDict
    }
    
    /// Update existing transaction with new data
    /// - Returns: True if any changes were made
    private func updateExistingTransaction(
        _ existingTransaction: PersistentTransaction,
        with transactionData: TransactionData
    ) -> Bool {
        var hasChanges = false

        // Bark re-finishes cancelled exit movements on every sync in which the
        // chain tip advanced, bumping their completed_at each time (see
        // Docs/Features/Exit_Completion_Issues.md §2a). Freeze the date once a
        // movement is cancelled and stays cancelled, so it doesn't resurface
        // at the top of the date-sorted list; the initial transition into
        // cancelled still updates the date once. Captured before the status
        // update below overwrites the previous status.
        let dateIsFrozen = existingTransaction.transactionStatus == .cancelled
            && transactionData.status == .cancelled

        if existingTransaction.amount != transactionData.amount {
            existingTransaction.amount = transactionData.amount
            hasChanges = true
        }

        if existingTransaction.transactionStatus != transactionData.status {
            existingTransaction.status = Self.stringValue(for: transactionData.status)
            hasChanges = true
        }

        if existingTransaction.transactionType != transactionData.type {
            existingTransaction.type = Self.stringValue(for: transactionData.type)
            hasChanges = true
        }

        if !dateIsFrozen && existingTransaction.date != transactionData.date {
            existingTransaction.date = transactionData.date
            hasChanges = true
        }
        
        if existingTransaction.address != transactionData.address {
            existingTransaction.address = transactionData.address
            hasChanges = true
        }
        
        if existingTransaction.fees != transactionData.fees {
            existingTransaction.fees = transactionData.fees
            hasChanges = true
        }
        
        // Update rich metadata fields
        let newCategory = transactionData.category.rawValue
        if existingTransaction.subsystemCategory != newCategory {
            existingTransaction.subsystemCategory = newCategory
            hasChanges = true
        }
        
        if existingTransaction.subsystemName != transactionData.subsystemName {
            existingTransaction.subsystemName = transactionData.subsystemName
            hasChanges = true
        }
        
        if existingTransaction.subsystemKind != transactionData.subsystemKind {
            existingTransaction.subsystemKind = transactionData.subsystemKind
            hasChanges = true
        }
        
        let newPaymentMethodType = transactionData.paymentMethod?.displayType
        if existingTransaction.paymentMethodType != newPaymentMethodType {
            existingTransaction.paymentMethodType = newPaymentMethodType
            hasChanges = true
        }
        
        if existingTransaction.paymentHash != transactionData.paymentHash {
            existingTransaction.paymentHash = transactionData.paymentHash
            hasChanges = true
        }
        
        if existingTransaction.paymentPreimage != transactionData.paymentPreimage {
            existingTransaction.paymentPreimage = transactionData.paymentPreimage
            hasChanges = true
        }
        
        if existingTransaction.onchainFeeSat != transactionData.onchainFeeSat {
            existingTransaction.onchainFeeSat = transactionData.onchainFeeSat
            hasChanges = true
        }
        
        if existingTransaction.fundingTxid != transactionData.fundingTxid {
            existingTransaction.fundingTxid = transactionData.fundingTxid
            hasChanges = true
        }
        
        // Update VTXO IDs
        let newInputVtxoIdsJson = PersistentTransaction.encodeVtxoIds(transactionData.inputVtxoIds)
        if existingTransaction.inputVtxoIdsJson != newInputVtxoIdsJson {
            existingTransaction.inputVtxoIdsJson = newInputVtxoIdsJson
            hasChanges = true
        }
        
        let newOutputVtxoIdsJson = PersistentTransaction.encodeVtxoIds(transactionData.outputVtxoIds)
        if existingTransaction.outputVtxoIdsJson != newOutputVtxoIdsJson {
            existingTransaction.outputVtxoIdsJson = newOutputVtxoIdsJson
            hasChanges = true
        }
        
        let newExitedVtxoIdsJson = PersistentTransaction.encodeVtxoIds(transactionData.exitedVtxoIds)
        if existingTransaction.exitedVtxoIdsJson != newExitedVtxoIdsJson {
            existingTransaction.exitedVtxoIdsJson = newExitedVtxoIdsJson
            hasChanges = true
        }
        
        return hasChanges
    }
    
    /// Create a PersistentTransaction from TransactionData
    private func createPersistentTransaction(from transactionData: TransactionData) -> PersistentTransaction {
        return PersistentTransaction(
            txid: transactionData.txid,
            movementId: transactionData.movementId,
            recipientIndex: transactionData.recipientIndex,
            type: transactionData.type,
            amount: transactionData.amount,
            date: transactionData.date,
            status: transactionData.status,
            address: transactionData.address,
            fees: transactionData.fees,
            // Rich metadata
            subsystemCategory: transactionData.category.rawValue,
            subsystemName: transactionData.subsystemName,
            subsystemKind: transactionData.subsystemKind,
            paymentMethodType: transactionData.paymentMethod?.displayType,
            paymentHash: transactionData.paymentHash,
            paymentPreimage: transactionData.paymentPreimage,
            onchainFeeSat: transactionData.onchainFeeSat,
            fundingTxid: transactionData.fundingTxid,
            inputVtxoIds: transactionData.inputVtxoIds,
            outputVtxoIds: transactionData.outputVtxoIds,
            exitedVtxoIds: transactionData.exitedVtxoIds
        )
    }
    
    /// Handle orphaned transactions (exist locally but not in server data)
    /// - Returns: Number of tag assignments on orphaned transactions
    private func handleOrphanedTransactions(
        existingTransactions: [PersistentTransaction],
        movements: [MovementData]
    ) async -> Int {
        // Get all transaction IDs from server data
        let serverTxids = Set(await movements.asyncFlatMap { movement in
            await parseMovementToTransactions(movement).map { $0.txid }
        })
        
        let orphanedTransactions = existingTransactions.filter { !serverTxids.contains($0.txid) }
        var orphanedTagCount = 0
        
        for orphanedTransaction in orphanedTransactions {
            let tagAssignments = orphanedTransaction.tagAssignments ?? []
            if !tagAssignments.isEmpty {
                orphanedTagCount += tagAssignments.count
                Self.logger.warning("⚠️ Transaction \(orphanedTransaction.txid) no longer exists on server but has \(tagAssignments.count) tag(s)")
            }
            // Note: We could choose to preserve orphaned tagged transactions or delete them
            // For now, we'll let them remain to preserve user tags until explicit cleanup
        }
        
        return orphanedTagCount
    }
}
