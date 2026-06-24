//
//  TransactionService+PendingMetadata.swift
//  Arke
//
//  Phase 0: Send Metadata Enhancement
//  Handles matching and applying pending payment metadata to transactions.
//

import Foundation
import SwiftData
import os

// MARK: - TransactionService+PendingMetadata

extension TransactionService {
    
    // MARK: - Configuration
    
    /// Time window for timestamp-based matching (in seconds)
    /// Configurable for testing and iteration
    private static let matchingTimeWindow: TimeInterval = 300 // 5 minutes
    
    // MARK: - Public Methods
    
    /// Apply pending metadata to a transaction if a match is found
    /// Called during transaction upsert to transfer metadata from pending payments
    /// - Parameter transaction: The transaction to apply metadata to
    func applyPendingMetadata(to transaction: PersistentTransaction) {
        guard let modelContext = modelContext else {
            Self.logger.error("🚨 No model context available for pending metadata matching")
            return
        }
        
        // Find matching pending metadata
        guard let pendingMetadata = findPendingMetadata(for: transaction, context: modelContext) else {
            return
        }
        
        // Check if metadata has already been applied
        // Skip re-application if nothing has changed since last application
        if pendingMetadata.hasBeenApplied {
            Self.logger.debug("⏭️ Skipping re-application - metadata already applied for txid: \(transaction.txid)")
            return
        }
        
        // Check if this is a re-application (already matched previously)
        let isReapplication = pendingMetadata.isMatched
        
        if isReapplication {
            Self.logger.debug("🔄 Re-applying pending metadata for txid: \(transaction.txid)")
        } else {
            Self.logger.info("✅ Found pending metadata match for transaction: \(transaction.txid)")
        }
        
        // Apply metadata to transaction
        applyMetadata(from: pendingMetadata, to: transaction, context: modelContext)
        
        // Mark as matched and applied
        // Note: We don't delete immediately because the user might still be editing
        // metadata in the SendModal UI. Cleanup will happen later.
        if !isReapplication {
            pendingMetadata.isMatched = true
            pendingMetadata.matchedTxid = transaction.txid
            Self.logger.info("✅ Marked pending metadata as matched for txid: \(transaction.txid)")
        }
        
        // Mark as applied to prevent redundant re-applications
        // If user modifies metadata later, they should call markAsModified()
        pendingMetadata.hasBeenApplied = true
        Self.logger.debug("✅ Metadata marked as applied for txid: \(transaction.txid)")
    }
    
    /// Cleanup old pending metadata
    /// - Matched metadata: older than 1 hour (safe window for UI editing)
    /// - Unmatched metadata: older than 24 hours (payment likely failed or issue)
    /// Should be called periodically (e.g., on app launch or transaction refresh)
    func cleanupOldPendingMetadata() {
        guard let modelContext = modelContext else {
            Self.logger.error("🚨 No model context available for cleanup")
            return
        }
        
        let matchedCutoff = Date().addingTimeInterval(-3600) // 1 hour ago (matched)
        let unmatchedCutoff = Date().addingTimeInterval(-86400) // 24 hours ago (unmatched)
        
        do {
            // Cleanup matched metadata older than 1 hour
            let matchedDescriptor = FetchDescriptor<PendingPaymentMetadata>(
                predicate: #Predicate { metadata in
                    metadata.isMatched && metadata.createdAt < matchedCutoff
                }
            )
            
            let oldMatchedMetadata = try modelContext.fetch(matchedDescriptor)
            
            if !oldMatchedMetadata.isEmpty {
                Self.logger.info("🧹 Cleaning up \(oldMatchedMetadata.count) old matched pending metadata entries")
                
                for metadata in oldMatchedMetadata {
                    Self.logger.debug("🗑️ Deleting matched metadata for txid: \(metadata.matchedTxid ?? "unknown")")
                    modelContext.delete(metadata)
                }
            }
            
            // Cleanup unmatched metadata older than 24 hours
            let unmatchedDescriptor = FetchDescriptor<PendingPaymentMetadata>(
                predicate: #Predicate { metadata in
                    !metadata.isMatched && metadata.createdAt < unmatchedCutoff
                }
            )
            
            let oldUnmatchedMetadata = try modelContext.fetch(unmatchedDescriptor)
            
            if !oldUnmatchedMetadata.isEmpty {
                Self.logger.info("🧹 Cleaning up \(oldUnmatchedMetadata.count) old unmatched pending metadata entries")
                
                for metadata in oldUnmatchedMetadata {
                    // Log details for debugging and improvement
                    logUnmatchedMetadata(metadata)
                    modelContext.delete(metadata)
                }
            }
            
            // Save all deletions
            if !oldMatchedMetadata.isEmpty || !oldUnmatchedMetadata.isEmpty {
                try modelContext.save()
            }
        } catch {
            Self.logger.error("❌ Failed to cleanup old pending metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Matching Logic
    
    /// Find pending metadata that matches a transaction
    /// Uses priority-based matching strategy:
    /// Priority 0: Already matched to this transaction (for re-application)
    /// Priority 1: Payment hash (Lightning only - most reliable)
    /// Priority 2: Timestamp + amount + address (all payment types - best effort)
    private func findPendingMetadata(
        for transaction: PersistentTransaction,
        context: ModelContext
    ) -> PendingPaymentMetadata? {
        do {
            // First check if there's already matched metadata for this transaction
            // This handles re-application when user adds metadata after initial match
            let txid = transaction.txid
            let matchedDescriptor = FetchDescriptor<PendingPaymentMetadata>(
                predicate: #Predicate { metadata in
                    metadata.isMatched == true && metadata.matchedTxid == txid
                }
            )
            
            if let alreadyMatched = try context.fetch(matchedDescriptor).first {
                Self.logger.debug("🔄 Re-applying matched metadata for txid: \(transaction.txid)")
                return alreadyMatched
            }
            
            // Fetch all unmatched pending metadata, sorted by timestamp (newest first)
            let descriptor = FetchDescriptor<PendingPaymentMetadata>(
                predicate: #Predicate { !$0.isMatched },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            
            let allPending = try context.fetch(descriptor)
            
            guard !allPending.isEmpty else {
                return nil
            }
            
            // Priority 1: Match by payment hash (Lightning payments only)
            if let paymentHash = transaction.paymentHash, !paymentHash.isEmpty {
                if let match = allPending.first(where: { $0.paymentHash == paymentHash }) {
                    Self.logger.info("🎯 Payment hash match found for txid: \(transaction.txid)")
                    return match
                }
            }
            
            // Priority 2: Match by timestamp + amount + address
            // This is a best-effort approach for Ark and Onchain payments
            return findTimestampBasedMatch(
                transaction: transaction,
                candidates: allPending
            )
            
        } catch {
            Self.logger.error("❌ Failed to fetch pending metadata: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Find a match using timestamp + amount + address
    /// Returns the most recent match within the time window
    private func findTimestampBasedMatch(
        transaction: PersistentTransaction,
        candidates: [PendingPaymentMetadata]
    ) -> PendingPaymentMetadata? {
        // Calculate time window boundaries
        let transactionDate = transaction.date
        let windowStart = transactionDate.addingTimeInterval(-Self.matchingTimeWindow)
        let windowEnd = transactionDate.addingTimeInterval(Self.matchingTimeWindow)
        
        // Filter candidates within time window
        let timeMatches = candidates.filter { metadata in
            metadata.timestamp >= windowStart && metadata.timestamp <= windowEnd
        }
        
        guard !timeMatches.isEmpty else {
            return nil
        }
        
        // Further filter by amount (must match exactly)
        let amountMatches = timeMatches.filter { metadata in
            metadata.amountSats == transaction.amount
        }
        
        guard !amountMatches.isEmpty else {
            Self.logger.debug("⏱️ Found time matches but no amount match for txid: \(transaction.txid)")
            return nil
        }
        
        // Further filter by address (case-insensitive comparison)
        let addressMatches = amountMatches.filter { metadata in
            guard let metadataAddress = metadata.destinationAddress,
                  let transactionAddress = transaction.address else {
                return false
            }
            return metadataAddress.lowercased() == transactionAddress.lowercased()
        }
        
        guard !addressMatches.isEmpty else {
            Self.logger.debug("💰 Found amount matches but no address match for txid: \(transaction.txid)")
            return nil
        }
        
        // If multiple matches, use the most recent one (closest timestamp)
        let match = addressMatches.min(by: { metadata1, metadata2 in
            abs(metadata1.timestamp.timeIntervalSince(transactionDate)) <
            abs(metadata2.timestamp.timeIntervalSince(transactionDate))
        })
        
        if let match = match {
            let timeDiff = abs(match.timestamp.timeIntervalSince(transactionDate))
            Self.logger.info("🎯 Timestamp match found for txid: \(transaction.txid) (time diff: \(Int(timeDiff))s)")
            
            if addressMatches.count > 1 {
                Self.logger.warning("⚠️ Multiple timestamp matches found, using closest: \(transaction.txid)")
            }
        }
        
        return match
    }
    
    // MARK: - Metadata Transfer
    
    /// Transfer metadata from pending to transaction
    private func applyMetadata(
        from pendingMetadata: PendingPaymentMetadata,
        to transaction: PersistentTransaction,
        context: ModelContext
    ) {
        var appliedCount = 0
        
        // Apply notes
        if let notes = pendingMetadata.notes, !notes.isEmpty {
            // Only apply if transaction doesn't already have notes
            if transaction.notes == nil || transaction.notes?.isEmpty == true {
                transaction.notes = notes
                appliedCount += 1
                Self.logger.debug("📝 Applied notes to transaction: \(transaction.txid)")
            }
        }
        
        // Transfer contact assignment
        if let contact = pendingMetadata.contact {
            // Check if transaction already has this contact
            let hasContact = transaction.contactAssignments?.contains(where: { 
                $0.contact?.id == contact.id 
            }) ?? false
            
            if !hasContact {
                let assignment = TransactionContactAssignment(
                    contact: contact,
                    transaction: transaction
                )
                context.insert(assignment)
                appliedCount += 1
                Self.logger.debug("👤 Applied contact to transaction: \(transaction.txid)")
            }
        }
        
        // Transfer tag assignments
        if let pendingTags = pendingMetadata.tagAssignments {
            for pendingTagAssignment in pendingTags {
                guard let tag = pendingTagAssignment.tag else { continue }
                
                // Check if transaction already has this tag
                let hasTag = transaction.tagAssignments?.contains(where: { 
                    $0.tag?.id == tag.id 
                }) ?? false
                
                if !hasTag {
                    let assignment = TransactionTagAssignment(
                        tag: tag,
                        transaction: transaction
                    )
                    context.insert(assignment)
                    appliedCount += 1
                    Self.logger.debug("🏷️ Applied tag '\(tag.name)' to transaction: \(transaction.txid)")
                }
            }
        }
        
        if appliedCount > 0 {
            Self.logger.info("✨ Applied \(appliedCount) metadata items to transaction: \(transaction.txid)")
        }
    }
    
    // MARK: - Logging
    
    /// Log details about unmatched metadata for debugging and improvement
    private func logUnmatchedMetadata(_ metadata: PendingPaymentMetadata) {
        let age = Date().timeIntervalSince(metadata.createdAt)
        let hasMetadata = metadata.hasMetadata
        
        var details: [String] = []
        if metadata.hasNotes { details.append("notes") }
        if metadata.hasContact { details.append("contact") }
        if metadata.hasTags { details.append("\(metadata.associatedTags.count) tags") }
        
        let metadataDescription = hasMetadata ? details.joined(separator: ", ") : "no metadata"
        
        Self.logger.info("""
            🔍 Unmatched pending metadata:
               - Payment type: \(metadata.paymentType ?? "unknown")
               - Amount: \(metadata.amountSats ?? 0) sats
               - Age: \(Int(age / 3600))h \(Int((age.truncatingRemainder(dividingBy: 3600)) / 60))m
               - Metadata: \(metadataDescription)
               - Payment hash: \(metadata.paymentHash != nil ? "present" : "none")
            """)
    }
}
