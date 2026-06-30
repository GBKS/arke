//
//  BalanceService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import ArkeUI
import SwiftUI
import SwiftData

/// Service responsible for managing all balance-related operations
@MainActor
@Observable
class BalanceService {
    
    // MARK: - Published Properties
    
    /// Current Ark balance
    var arkBalance: ArkBalanceModel?
    
    /// Current onchain balance
    var onchainBalance: OnchainBalanceModel?
    
    /// Combined total balance across all wallets
    var totalBalance: TotalBalanceModel?
    
    /// Error message for balance operations
    var error: String?
    
    // MARK: - Dependencies
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private let cacheManager: WalletCacheManager
    private var modelContext: ModelContext?
    
    // MARK: - Computed Properties for UI
    
    /// True if there are any pending balances
    var hasPendingBalance: Bool {
        totalBalance?.hasPendingBalance ?? false
    }
    
    /// True if user has any spendable funds
    var hasSpendableBalance: Bool {
        totalBalance?.hasSpendableBalance ?? false
    }
    
    /// Current Ark info (cached) - exposed as computed property
    var arkInfo: ArkInfoModel? {
        cacheManager.arkInfo.value
    }
    
    /// Estimated current block height based on cached data - exposed as computed property
    var estimatedBlockHeight: Int? {
        cacheManager.getEstimatedBlockHeight()
    }
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager, cacheManager: WalletCacheManager) {
        self.wallet = wallet
        self.taskManager = taskManager
        self.cacheManager = cacheManager
    }
    
    // MARK: - Balance Fetching (with Deduplication)
    
    /// Get Ark balance with task deduplication
    func getArkBalanceWithDeduplication() async throws -> ArkBalanceResponse {
        return try await taskManager.execute(key: "arkBalance") {
            let result = try await self.wallet.getArkBalance()
            print("📊 Ark balance: \(result.spendableSat) sats spendable, \(result.totalPendingSat) sats pending")
            return result
        }
    }
    
    /// Get onchain balance with task deduplication
    func getOnchainBalanceWithDeduplication() async throws -> OnchainBalanceResponse {
        return try await taskManager.execute(key: "onchainBalance") {
            let result = try await self.wallet.getOnchainBalance()
            print("📊 Onchain balance: \(result.totalSat) sats total, \(result.spendableSat) sats spendable")
            return result
        }
    }
    
    // MARK: - Balance Refresh Methods
    
    /// Refresh all balances in parallel
    func refreshAllBalances() async {
        do {
            // Fetch balances in parallel (with deduplication)
            async let arkBalanceResult = getArkBalanceWithDeduplication()
            async let onchainBalanceResult = getOnchainBalanceWithDeduplication()
            
            // Wait for both balances to complete
            let (arkResponse, onchainResponse) = try await (arkBalanceResult, onchainBalanceResult)
            
            // Update Ark balance (both UI state and persistence)
            await updateArkBalanceFromResponse(arkResponse)
            
            // Update onchain balance (both UI state and persistence)
            await updateOnchainBalanceFromResponse(onchainResponse)
            
            updateTotalBalance()
            
            error = nil
            print("✅ All balances refreshed successfully \(Date())")
            
        } catch {
            self.error = "Failed to refresh balances: \(error)"
            print("❌ Failed to refresh balances: \(error)")
        }
    }
    
    /// Refresh just Ark balance
    func refreshArkBalance() async {
        do {
            let apiResponse = try await getArkBalanceWithDeduplication()
            
            // Update or load the SwiftData model for UI
            await updateArkBalanceFromResponse(apiResponse)
            updateTotalBalance()
            
            error = nil
        } catch {
            self.error = "Failed to get Ark balance: \(error)"
            print("❌ Failed to get Ark balance: \(error)")
        }
    }
    
    /// Refresh just onchain balance
    func refreshOnchainBalance() async {
        do {
            let apiResponse = try await getOnchainBalanceWithDeduplication()
            
            // Update or load the SwiftData model for UI
            await updateOnchainBalanceFromResponse(apiResponse)
            updateTotalBalance()
            
            error = nil
        } catch {
            self.error = "Failed to get onchain balance: \(error)"
            print("❌ Failed to get onchain balance: \(error)")
        }
    }
    
    // MARK: - Direct Balance Access Methods
    
    /// Get the current Ark balance response
    func getArkBalance() async throws -> ArkBalanceResponse {
        return try await getArkBalanceWithDeduplication()
    }
    
    /// Get the current onchain balance response  
    func getOnchainBalance() async throws -> OnchainBalanceResponse {
        return try await getOnchainBalanceWithDeduplication()
    }
    
    // MARK: - Balance Calculation
    
    /// Update the total balance based on current ark and onchain balances
    func updateTotalBalance() {
        // Create zero-balance models for any missing balances
        // This ensures the UI always shows something, even during partial loads
        let ark = arkBalance ?? ArkBalanceModel(
            spendableSat: 0,
            pendingLightningSendSat: 0,
            pendingInRoundSat: 0,
            pendingExitSat: 0,
            pendingBoardSat: 0
        )
        
        let onchain = onchainBalance ?? OnchainBalanceModel(
            totalSat: 0,
            confirmedSat: 0,
            pendingSat: 0
        )
        
        totalBalance = TotalBalanceModel(arkBalance: ark, onchainBalance: onchain)
        
        if arkBalance == nil && onchainBalance == nil {
            print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (both balances missing, showing zeros)")
        } else if arkBalance == nil {
            print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (ark balance missing, using onchain only)")
        } else if onchainBalance == nil {
            print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (onchain balance missing, using ark only)")
        } else {
            print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (\(totalBalance?.totalSpendableSat ?? 0) spendable)")
        }
    }
    
    // MARK: - State Reset
    
    /// Reset only in-memory balance state without deleting persisted data
    /// Use this for temporary resets (e.g., device migration, service restarts)
    /// The persisted balances will be reloaded on next startup or sync from CloudKit
    func resetBalancesInMemory() {
        arkBalance = nil
        onchainBalance = nil
        totalBalance = nil
        error = nil
        print("🔄 Balance state reset (in-memory only, persisted data preserved)")
    }
    
    /// Reset all balance state AND delete persisted data
    /// Only use this for complete wallet deletion scenarios
    func resetBalancesAndDeletePersisted() {
        arkBalance = nil
        onchainBalance = nil
        totalBalance = nil
        error = nil
        
        // Clear persisted balance data
        Task {
            await clearPersistedArkBalance()
            await clearPersistedOnchainBalance()
        }
        print("🔄 Balance state reset (including persisted data deletion)")
    }
    
    /// Check if any balance data is available
    var hasBalanceData: Bool {
        arkBalance != nil && onchainBalance != nil
    }
}

// MARK: - Convenience Extensions

extension BalanceService {
    
    /// Refresh balances after a transaction operation
    func refreshAfterTransaction() async {
        print("🔄 Refreshing balances after transaction...")
        await refreshAllBalances()
    }
    
    /// Refresh all balances (public interface for notification service)
    func refreshBalances() async {
        await refreshAllBalances()
    }
    
    /// Get a snapshot of current balance state for logging or debugging
    func getBalanceSnapshot() -> String {
        let arkSats = arkBalance?.spendableSat ?? 0
        let onchainSats = onchainBalance?.spendableSat ?? 0
        let totalSats = totalBalance?.totalSpendableSat ?? 0
        
        return "Balance snapshot: Ark: \(arkSats) sats, Onchain: \(onchainSats) sats, Total: \(totalSats) sats"
    }
    
    /// Cache ArkInfo if needed for block height estimation
    func cacheArkInfoIfNeeded() async {
        // Check if we need to refresh ArkInfo cache
        if cacheManager.arkInfo.isValid {
            print("📦 Using cached ArkInfo")
            return
        }
        
        do {
            let arkInfo = try await wallet.getArkInfo()
            cacheManager.arkInfo.setValue(arkInfo)
            print("✅ ArkInfo cached - round interval: \(arkInfo.roundInterval)")
        } catch {
            print("⚠️ Failed to cache ArkInfo: \(error)")
            // Don't update error state since this is just for caching
        }
    }
    
    // MARK: - SwiftData Persistence
    
    /// Set the model context for persistence operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Load persisted balances on startup SYNCHRONOUSLY
        // This is intentionally synchronous to ensure cached data is available
        // immediately when the view first renders, preventing a blank balance card.
        // These are simple primary key lookups in local SQLite and should be < 1ms.
        loadPersistedArkBalanceSync()
        loadPersistedOnchainBalanceSync()
        // Update total balance after both balances are loaded
        updateTotalBalance()
    }
    
    /// Load persisted Ark balance from SwiftData (synchronous version for instant UI display)
    private func loadPersistedArkBalanceSync() {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading persisted Ark balance")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<ArkBalanceModel>(
                predicate: #Predicate<ArkBalanceModel> { $0.id == "ark_balance" }
            )
            let persistedBalances = try modelContext.fetch(descriptor)
            
            if let persistedBalance = persistedBalances.first {
                // Always load persisted balance, regardless of staleness
                // This ensures users always see their balance immediately
                // Fresh data will be fetched in the background and update the UI when ready
                self.arkBalance = persistedBalance
                if persistedBalance.isValid {
                    print("📱 Loaded valid persisted Ark balance (spendable: \(persistedBalance.spendableSat) sats)")
                } else {
                    let age = Date().timeIntervalSince(persistedBalance.lastUpdated)
                    print("📱 Loaded stale persisted Ark balance (spendable: \(persistedBalance.spendableSat) sats, age: \(Int(age))s) - will refresh in background")
                }
            } else {
                print("📱 No persisted Ark balance found")
            }
        } catch {
            print("❌ Failed to load persisted Ark balance: \(error)")
        }
    }
    
    /// Load persisted Ark balance from SwiftData (async version for compatibility)
    private func loadPersistedArkBalance() async {
        loadPersistedArkBalanceSync()
    }
    
    /// Update Ark balance from API response (handles both UI state and persistence)
    private func updateArkBalanceFromResponse(_ apiResponse: ArkBalanceResponse) async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for saving Ark balance")
            return
        }
        
        do {
            // Try to find existing balance record
            let descriptor = FetchDescriptor<ArkBalanceModel>(
                predicate: #Predicate<ArkBalanceModel> { $0.id == "ark_balance" }
            )
            let existingBalances = try modelContext.fetch(descriptor)
            
            if let existingBalance = existingBalances.first {
                // Update existing record with new data from API
                existingBalance.update(from: apiResponse)
                self.arkBalance = existingBalance
                print("💾 Updated persisted Ark balance")
            } else {
                // Create new record with the API data
                let newBalance = ArkBalanceModel(from: apiResponse)
                modelContext.insert(newBalance)
                self.arkBalance = newBalance
                print("💾 Created new persisted Ark balance")
            }
            
            // Save changes
            try modelContext.save()
            
        } catch {
            print("❌ Failed to save Ark balance to SwiftData: \(error)")
        }
    }
    
    /// Clear persisted Ark balance from SwiftData
    private func clearPersistedArkBalance() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for clearing persisted Ark balance")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<ArkBalanceModel>(
                predicate: #Predicate<ArkBalanceModel> { $0.id == "ark_balance" }
            )
            let existingBalances = try modelContext.fetch(descriptor)
            
            for balance in existingBalances {
                modelContext.delete(balance)
            }
            
            try modelContext.save()
            print("🗑️ Cleared persisted Ark balance")
            
        } catch {
            print("❌ Failed to clear persisted Ark balance: \(error)")
        }
    }
    
    /// Load persisted Onchain balance from SwiftData (synchronous version for instant UI display)
    private func loadPersistedOnchainBalanceSync() {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading persisted Onchain balance")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<OnchainBalanceModel>(
                predicate: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" }
            )
            let persistedBalances = try modelContext.fetch(descriptor)
            
            if let persistedBalance = persistedBalances.first {
                // Always load persisted balance, regardless of staleness
                // This ensures users always see their balance immediately
                // Fresh data will be fetched in the background and update the UI when ready
                self.onchainBalance = persistedBalance
                if persistedBalance.isValid {
                    print("📱 Loaded valid persisted Onchain balance (spendable: \(persistedBalance.spendableSat) sats)")
                } else {
                    let age = Date().timeIntervalSince(persistedBalance.lastUpdated)
                    print("📱 Loaded stale persisted Onchain balance (spendable: \(persistedBalance.spendableSat) sats, age: \(Int(age))s) - will refresh in background")
                }
            } else {
                print("📱 No persisted Onchain balance found")
            }
        } catch {
            print("❌ Failed to load persisted Onchain balance: \(error)")
        }
    }
    
    /// Load persisted Onchain balance from SwiftData (async version for compatibility)
    private func loadPersistedOnchainBalance() async {
        loadPersistedOnchainBalanceSync()
    }
    
    /// Update Onchain balance from API response (handles both UI state and persistence)
    private func updateOnchainBalanceFromResponse(_ apiResponse: OnchainBalanceResponse) async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for saving Onchain balance")
            return
        }
        
        do {
            // Try to find existing balance record
            let descriptor = FetchDescriptor<OnchainBalanceModel>(
                predicate: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" }
            )
            let existingBalances = try modelContext.fetch(descriptor)
            
            if let existingBalance = existingBalances.first {
                // Update existing record with new data from API
                existingBalance.update(from: apiResponse)
                self.onchainBalance = existingBalance
                print("💾 Updated persisted Onchain balance")
            } else {
                // Create new record with the API data
                let newBalance = OnchainBalanceModel(from: apiResponse)
                modelContext.insert(newBalance)
                self.onchainBalance = newBalance
                print("💾 Created new persisted Onchain balance")
            }
            
            // Save changes
            try modelContext.save()
            
        } catch {
            print("❌ Failed to save Onchain balance to SwiftData: \(error)")
        }
    }
    
    /// Clear persisted Onchain balance from SwiftData
    private func clearPersistedOnchainBalance() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for clearing persisted Onchain balance")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<OnchainBalanceModel>(
                predicate: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" }
            )
            let existingBalances = try modelContext.fetch(descriptor)
            
            for balance in existingBalances {
                modelContext.delete(balance)
            }
            
            try modelContext.save()
            print("🗑️ Cleared persisted Onchain balance")
            
        } catch {
            print("❌ Failed to clear persisted Onchain balance: \(error)")
        }
    }
}
