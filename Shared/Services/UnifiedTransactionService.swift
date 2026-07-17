//
//  UnifiedTransactionService.swift
//  Arké
//
//  Service that merges transactions from both Ark and onchain sources
//  Provides a unified list for UI consumption with full tag/contact support
//

import Foundation
import SwiftData
import ArkeUI

@MainActor
@Observable
class UnifiedTransactionService {
    // MARK: - Dependencies
    
    private let arkService: TransactionService
    private let onchainService: OnchainTransactionService
    private var modelContext: ModelContext?
    private weak var walletManager: WalletManager?
    
    // MARK: - Published Properties
    
    /// Unified list of all transactions from both sources
    var allTransactions: [TransactionModel] = []
    
    /// Whether any service is currently loading
    var isLoading: Bool = false
    
    /// Combined error from services
    var error: String?
    
    /// Whether transactions have been loaded at least once
    var hasLoadedTransactions: Bool = false
    
    // MARK: - Computed Properties
    
    /// Total number of transactions from both sources
    var transactionCount: Int {
        allTransactions.count
    }
    
    /// Whether there are any transactions
    var hasTransactions: Bool {
        !allTransactions.isEmpty
    }
    
    /// Number of ark-only transactions
    var arkTransactionCount: Int {
        arkService.transactions.count
    }
    
    /// Number of onchain-only transactions
    var onchainTransactionCount: Int {
        onchainService.transactionCount
    }
    
    /// Whether services are currently refreshing
    var isRefreshing: Bool {
        arkService.isRefreshing || onchainService.isLoading
    }
    
    // MARK: - Initialization
    
    init(
        arkService: TransactionService,
        onchainService: OnchainTransactionService,
        walletManager: WalletManager
    ) {
        self.arkService = arkService
        self.onchainService = onchainService
        self.walletManager = walletManager
        
        print("🔗 [UnifiedTxService] Initialized with ark + onchain services")
    }
    
    // MARK: - Public Methods
    
    /// Set the model context for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        print("📦 [UnifiedTxService] ModelContext set")
    }
    
    /// Refresh all transaction sources
    func refreshTransactions() async {
        isLoading = true
        defer { isLoading = false }
        
        print("🔄 [UnifiedTxService] Starting refresh of both sources...")
        
        // Refresh both services in parallel
        async let arkRefresh: () = arkService.refreshTransactions()
        async let onchainRefresh: () = onchainService.refreshTransactions()
        
        await arkRefresh
        await onchainRefresh
        
        // Merge results
        await mergeTransactions()
        
        // Check for errors from services
        if let arkError = arkService.error {
            error = "Ark: \(arkError)"
        } else if let onchainError = onchainService.error {
            error = "Onchain: \(onchainError)"
        } else {
            error = nil
        }
        
        hasLoadedTransactions = true
        
        print("✅ [UnifiedTxService] Refresh complete")
    }
    
    /// Merge transactions from both sources immediately (without refresh)
    func mergeTransactions() async {
        guard let modelContext = modelContext else {
            print("⚠️ [UnifiedTxService] No model context available for merging")
            return
        }
        
        // Get ark transactions (already as TransactionModel)
        let arkTransactions = arkService.transactions
        
        // Convert onchain transactions to TransactionModel
        let onchainTransactions = onchainService.onchainTransactions.compactMap { onchain -> TransactionModel? in
            // Find or create persistent transaction for metadata (tags, contacts, notes)
            let persistent = findOrCreatePersistentOnchainTransaction(
                onchain,
                modelContext: modelContext
            )
            
            // Convert to TransactionModel
            // Properly handles self-transfers by using isSelfTransfer flag
            return convertOnchainToTransactionModel(onchain, persistent: persistent)
        }
        
        // Merge and deduplicate by txid (in case of overlaps)
        var txDict: [String: TransactionModel] = [:]
        
        // Add ark transactions first (they take precedence)
        for tx in arkTransactions {
            txDict[tx.txid] = tx
        }
        
        // Add onchain transactions (only if not already present)
        for tx in onchainTransactions {
            if txDict[tx.txid] == nil {
                txDict[tx.txid] = tx
            } else {
                print("⚠️ [UnifiedTxService] Duplicate txid found: \(String(tx.txid.prefix(16)))...")
                print("   Existing: category=\(txDict[tx.txid]?.category?.rawValue ?? "nil"), type=\(String(describing: txDict[tx.txid]?.type))")
                print("   Skipping: category=\(tx.category?.rawValue ?? "nil"), type=\(tx.type)")
            }
        }
        
        // Sort by date (newest first)
        allTransactions = txDict.values.sorted { $0.date > $1.date }
        
        print("📊 [UnifiedTxService] Merged \(arkTransactions.count) ark + \(onchainTransactions.count) onchain = \(allTransactions.count) total (deduped from \(arkTransactions.count + onchainTransactions.count))")
    }
    
    /// Get transactions for a specific tag (includes both sources)
    func transactionsForTag(_ tag: PersistentTag) -> [TransactionModel] {
        let filtered = allTransactions.filter { tx in
            tx.associatedTags.contains { $0.id == tag.id }
        }
        
        print("🏷️ [UnifiedTxService] Filtered by tag '\(tag.name)': \(filtered.count) transactions")
        
        return filtered
    }
    
    /// Get transactions for a specific contact (includes both sources)
    func transactionsForContact(_ contact: PersistentContact) -> [TransactionModel] {
        let filtered = allTransactions.filter { tx in
            tx.associatedContacts.contains { $0.id == contact.id }
        }
        
        print("👤 [UnifiedTxService] Filtered by contact '\(contact.cachedName)': \(filtered.count) transactions")
        
        return filtered
    }
    
    /// Get transaction by txid (searches both sources)
    func getTransaction(txid: String) -> TransactionModel? {
        return allTransactions.first { $0.txid == txid }
    }
    
    /// Force a re-merge without refreshing from network
    /// Useful after tag/contact assignments change
    func invalidateAndReMerge() async {
        await mergeTransactions()
    }
    
    // MARK: - Statistics
    
    /// Get statistics about transaction sources
    func getSourceStatistics() -> (ark: Int, onchain: Int, total: Int) {
        return (
            ark: arkTransactionCount,
            onchain: onchainTransactionCount,
            total: transactionCount
        )
    }
    
    /// Get a breakdown of transactions by category
    func getCategoryBreakdown() -> [MovementCategory: Int] {
        var breakdown: [MovementCategory: Int] = [:]
        
        for transaction in allTransactions {
            if let category = transaction.category {
                breakdown[category, default: 0] += 1
            }
        }
        
        return breakdown
    }
    
    // MARK: - Private Helpers
    
    /// Convert OnchainTransactionModel to TransactionModel
    /// - Parameters:
    ///   - onchain: The onchain transaction model from BDK
    ///   - persistent: The linked PersistentTransaction for metadata
    /// - Returns: A TransactionModel compatible with the existing UI
    private func convertOnchainToTransactionModel(
        _ onchain: OnchainTransactionModel,
        persistent: PersistentTransaction
    ) -> TransactionModel {
        
        // For sent transactions, the amount should exclude fees
        // For self-transfers, use the received amount (what actually ended up in wallet)
        let amountWithoutFees: Int
        if onchain.isSelfTransfer {
            amountWithoutFees = Int(onchain.received)
        } else if onchain.isIncoming {
            amountWithoutFees = Int(abs(onchain.netAmount))
        } else {
            let fee = Int(onchain.fee ?? 0)
            amountWithoutFees = Int(abs(onchain.netAmount)) - fee
        }
        
        print("DEBUG: txid = \(onchain.txid)")
        print("DEBUG: Received amount = \(onchain.received), amountWithoutFees = \(amountWithoutFees)")
        
        return TransactionModel(
            txid: "onchain_\(onchain.txid)",
            movementId: nil,
            recipientIndex: nil,
            type: onchain.isIncoming ? .received : .sent,
            amount: amountWithoutFees,
            date: onchain.timestamp ?? Date(),
            status: onchain.isConfirmed ? .confirmed : .pending,
            address: nil,
            notes: persistent.notes,
            associatedTags: persistent.associatedTags.map { TagModel(from: $0) },
            associatedContacts: persistent.associatedContacts.map { ContactModel(from: $0) },
            fees: nil,
            onchainFeeSat: onchain.fee.map { Int($0) },
            subsystemCategory: "onchain_transaction",
            subsystemName: "bitcoin.core",
            subsystemKind: onchain.isSelfTransfer ? "self_transfer" : (onchain.isIncoming ? "receive" : "send"),
            paymentMethodType: "bitcoin",
            paymentHash: nil,
            fundingTxid: nil,
            inputVtxoIds: [],
            outputVtxoIds: [],
            exitedVtxoIds: [],
            confirmationHeight: onchain.confirmationTime?.height,
            confirmationCount: onchain.confirmations,
            category: .onchainTransaction
        )
    }
    
    /// Find existing or create new PersistentTransaction for an onchain transaction
    /// - Parameters:
    ///   - onchain: The onchain transaction model from BDK
    ///   - modelContext: SwiftData context for persistence
    /// - Returns: Existing or newly created PersistentTransaction
    private func findOrCreatePersistentOnchainTransaction(
        _ onchain: OnchainTransactionModel,
        modelContext: ModelContext
    ) -> PersistentTransaction {
        
        let txid = "onchain_\(onchain.txid)"
        
        // Try to find existing persistent transaction
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update confirmation data if changed
            updateConfirmationData(existing, from: onchain)
            return existing
        }
        
        // Create new persistent transaction
        // Amount should exclude fees for sent transactions (matching TransactionModel logic)
        // For self-transfers, use the received amount (what actually ended up in wallet)
        let amountWithoutFees: Int
        if onchain.isSelfTransfer {
            amountWithoutFees = Int(onchain.received)
        } else if onchain.isIncoming {
            amountWithoutFees = Int(abs(onchain.netAmount))
        } else {
            let fee = Int(onchain.fee ?? 0)
            amountWithoutFees = Int(abs(onchain.netAmount)) - fee
        }
        
        let persistent = PersistentTransaction(
            txid: txid,
            movementId: nil,
            type: onchain.isIncoming ? .received : .sent,
            amount: amountWithoutFees,
            date: onchain.timestamp ?? Date(),
            status: onchain.isConfirmed ? .confirmed : .pending,
            address: nil,
            subsystemCategory: "onchain_transaction"
        )
        
        // Set onchain-specific fields
        persistent.sourceType = "onchain"
        persistent.confirmationHeight = onchain.confirmationTime?.height
        persistent.confirmationCount = onchain.confirmations
        persistent.onchainReceived = onchain.received
        persistent.onchainSent = onchain.sent
        persistent.onchainFeeSat = onchain.fee.map { Int($0) }
        persistent.subsystemName = "bitcoin.core"
        persistent.subsystemKind = onchain.isSelfTransfer ? "self_transfer" : (onchain.isIncoming ? "receive" : "send")
        persistent.paymentMethodType = "bitcoin"
        
        modelContext.insert(persistent)
        
        // Save immediately to ensure it's available for tag/contact assignment
        try? modelContext.save()
        
        // Establish movement-onchain links for this new onchain transaction
        walletManager?.transactionLinkingService?.establishLinksForOnchain(
            onchainTxid: txid,
            context: modelContext
        )
        
        print("📝 [UnifiedTxService] Created PersistentTransaction for onchain tx: \(onchain.shortTxid)")
        
        return persistent
    }
    
    /// Update confirmation data on existing persistent transaction
    /// - Parameters:
    ///   - persistent: The persistent transaction to update
    ///   - onchain: The current onchain transaction data
    private func updateConfirmationData(
        _ persistent: PersistentTransaction,
        from onchain: OnchainTransactionModel
    ) {
        var hasChanges = false
        
        // Update confirmation count if changed
        if persistent.confirmationCount != onchain.confirmations {
            persistent.confirmationCount = onchain.confirmations
            hasChanges = true
        }
        
        // Update confirmation height if changed
        if persistent.confirmationHeight != onchain.confirmationTime?.height {
            persistent.confirmationHeight = onchain.confirmationTime?.height
            hasChanges = true
        }
        
        // Update status if confirmation status changed
        let newStatus = onchain.isConfirmed ? "confirmed" : "pending"
        if persistent.status != newStatus {
            persistent.status = newStatus
            hasChanges = true
        }
        
        // Update timestamp if transaction now has a confirmation time
        if let timestamp = onchain.timestamp {
            // Only update if the stored date is significantly different (more than 1 second)
            if abs(persistent.date.timeIntervalSince(timestamp)) > 1.0 {
                persistent.date = timestamp
                hasChanges = true
            }
        }
        
        // Update fee data if changed. Never overwrite a known fee with nil:
        // exit claim fees are persisted from bark (recordClaimFee) and BDK
        // reports no fee for them, since the wallet owns none of their inputs
        let newFee = onchain.fee.map { Int($0) }
        if let newFee, persistent.onchainFeeSat != newFee {
            persistent.onchainFeeSat = newFee
            hasChanges = true
        }
        
        if hasChanges {
            print("🔄 [UnifiedTxService] Updated data for \(onchain.shortTxid): \(onchain.confirmations) confirmations, fee: \(newFee.map { "\($0) sats" } ?? "nil")")
        }
    }
}

// MARK: - Convenience Extensions

extension UnifiedTransactionService {
    /// Get a snapshot of current state for logging/debugging
    func getSnapshot() -> String {
        let stats = getSourceStatistics()
        
        return """
        Unified Transaction Service State:
        - Total: \(stats.total) transactions
        - Ark: \(stats.ark) transactions
        - Onchain: \(stats.onchain) transactions
        - Has loaded: \(hasLoadedTransactions)
        - Is refreshing: \(isRefreshing)
        - Error: \(error ?? "none")
        """
    }
}
