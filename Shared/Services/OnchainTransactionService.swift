//
//  OnchainTransactionService.swift
//  Arké
//
//  Service responsible for managing onchain Bitcoin transactions from BDK wallet
//

import Foundation
import SwiftUI
import SwiftData

/// Service responsible for managing all onchain transaction operations
@MainActor
@Observable
class OnchainTransactionService {
    
    // MARK: - Published Properties
    
    /// Current list of onchain transactions
    var onchainTransactions: [OnchainTransactionModel] = []
    
    /// Whether transactions are currently being fetched
    var isLoading: Bool = false
    
    /// Error message for transaction operations
    var error: String?
    
    /// Whether transactions have been loaded at least once
    var hasLoadedTransactions: Bool = false
    
    // MARK: - Dependencies
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private let cacheManager: CacheManager<[OnchainTransactionModel]>
    private var modelContext: ModelContext?
    
    // MARK: - Computed Properties
    
    /// Number of onchain transactions
    var transactionCount: Int {
        onchainTransactions.count
    }
    
    /// Whether there are any onchain transactions
    var hasTransactions: Bool {
        !onchainTransactions.isEmpty
    }
    
    /// Confirmed transactions only
    var confirmedTransactions: [OnchainTransactionModel] {
        onchainTransactions.filter { $0.isConfirmed }
    }
    
    /// Pending (unconfirmed) transactions only
    var pendingTransactions: [OnchainTransactionModel] {
        onchainTransactions.filter { !$0.isConfirmed }
    }
    
    /// Incoming transactions
    var incomingTransactions: [OnchainTransactionModel] {
        onchainTransactions.filter { $0.isIncoming }
    }
    
    /// Outgoing transactions
    var outgoingTransactions: [OnchainTransactionModel] {
        onchainTransactions.filter { !$0.isIncoming }
    }
    
    /// Whether there are any pending transactions
    var hasPendingTransactions: Bool {
        !pendingTransactions.isEmpty
    }
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
        // Cache timeout: 30 seconds (balance between freshness and performance)
        self.cacheManager = CacheManager<[OnchainTransactionModel]>(timeout: 30)
    }
    
    // MARK: - Public Methods
    
    /// Get onchain transactions with task deduplication
    func getTransactions() async throws -> [OnchainTransactionModel] {
        return try await taskManager.execute(key: "onchainTransactions") {
            let transactions = try await self.wallet.getOnchainTransactions()
            print("📊 [OnchainTxService] Fetched \(transactions.count) onchain transactions")
            return transactions
        }
    }
    
    /// Refresh onchain transactions with caching
    func refreshTransactions() async {
        do {
            isLoading = true
            
            // Check cache first - if valid, use cached data and optionally refresh in background
            if let cached = cacheManager.value {
                onchainTransactions = cached
                print("📦 [OnchainTxService] Using cached transactions (\(cached.count))")
                isLoading = false
                
                // Still refresh in background if needed
                Task {
                    await refreshInBackground()
                }
                return
            }
            
            // Fetch fresh data
            let transactions = try await getTransactions()
            
            // Update cache and state
            cacheManager.setValue(transactions)
            onchainTransactions = transactions
            
            // Persist to SwiftData
            await persistTransactions(transactions)
            
            hasLoadedTransactions = true
            error = nil
            
            print("✅ [OnchainTxService] Refreshed \(transactions.count) transactions")
            
        } catch {
            self.error = "Failed to refresh onchain transactions: \(error)"
            print("❌ [OnchainTxService] Failed to refresh: \(error)")
        }
        
        isLoading = false
    }
    
    /// Background refresh (doesn't update loading state)
    private func refreshInBackground() async {
        do {
            let transactions = try await getTransactions()
            
            // Only update if data actually changed
            if transactions != onchainTransactions {
                cacheManager.setValue(transactions)
                onchainTransactions = transactions
                await persistTransactions(transactions)
                print("🔄 [OnchainTxService] Background refresh updated \(transactions.count) transactions")
            }
        } catch {
            print("⚠️ [OnchainTxService] Background refresh failed: \(error)")
            // Don't update error state for background refreshes
        }
    }
    
    /// Set the model context for persistence operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Load persisted transactions on startup
        Task {
            await loadPersistedTransactions()
        }
    }
    
    /// Reset all in-memory transaction state. Called from
    /// `WalletManager.resetManagerState()` on deletion and close: the list
    /// and the 30 s cache otherwise outlive the wallet, and the next
    /// `UnifiedTransactionService.mergeTransactions()` (Step 2b runs before
    /// Step 3 has fetched the new wallet's list) re-persists the deleted
    /// wallet's onchain rows into the new one (2026-10-14 field case).
    /// Nothing persisted is touched here: `OnchainTransactionEntity` is not
    /// in the schema (`SwiftDataHelper`), and the `PersistentTransaction`
    /// rows are the cleanup service's to delete.
    func resetTransactions() {
        onchainTransactions = []
        error = nil
        hasLoadedTransactions = false
        isLoading = false
        cacheManager.clear()
    }
    
    /// Force cache invalidation and refresh
    func invalidateCache() {
        cacheManager.clear()
        Task {
            await refreshTransactions()
        }
    }
    
    // MARK: - SwiftData Persistence
    
    /// Persist transactions to SwiftData
    private func persistTransactions(_ transactions: [OnchainTransactionModel]) async {
        guard let context = modelContext else {
            print("⚠️ [OnchainTxService] No model context available for persistence")
            return
        }
        
        do {
            for transaction in transactions {
                // Upsert logic: update if exists, insert if new
                let descriptor = FetchDescriptor<OnchainTransactionEntity>(
                    predicate: #Predicate { $0.txid == transaction.txid }
                )
                
                if let existing = try? context.fetch(descriptor).first {
                    // Update existing transaction
                    existing.update(from: transaction)
                } else {
                    // Insert new transaction
                    let entity = OnchainTransactionEntity(from: transaction)
                    context.insert(entity)
                }
            }
            
            try context.save()
            print("💾 [OnchainTxService] Persisted \(transactions.count) transactions")
            
        } catch {
            print("❌ [OnchainTxService] Failed to persist transactions: \(error)")
        }
    }
    
    /// Load persisted transactions from SwiftData
    private func loadPersistedTransactions() async {
        guard let context = modelContext else {
            print("⚠️ [OnchainTxService] No model context available for loading")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<OnchainTransactionEntity>(
                sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
            )
            
            let entities = try context.fetch(descriptor)
            
            if !entities.isEmpty {
                onchainTransactions = entities.map { $0.asModel }
                hasLoadedTransactions = true
                print("📦 [OnchainTxService] Loaded \(entities.count) persisted transactions")
            }
            
        } catch {
            print("❌ [OnchainTxService] Failed to load persisted transactions: \(error)")
        }
    }
    
    /// Clear all persisted transactions
    private func clearPersistedTransactions() async {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<OnchainTransactionEntity>()
            let entities = try context.fetch(descriptor)
            
            for entity in entities {
                context.delete(entity)
            }
            
            try context.save()
            print("🗑️ [OnchainTxService] Cleared \(entities.count) persisted transactions")
            
        } catch {
            print("❌ [OnchainTxService] Failed to clear persisted transactions: \(error)")
        }
    }
}

// MARK: - Convenience Extensions

extension OnchainTransactionService {
    
    /// Get a snapshot of current transaction state for logging or debugging
    func getTransactionSnapshot() -> String {
        let confirmed = confirmedTransactions.count
        let pending = pendingTransactions.count
        let incoming = incomingTransactions.count
        let outgoing = outgoingTransactions.count
        
        return """
        Onchain Transactions: \(transactionCount) total
        - Confirmed: \(confirmed), Pending: \(pending)
        - Incoming: \(incoming), Outgoing: \(outgoing)
        """
    }
}
