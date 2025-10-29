//
//  BalanceService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
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
    func getArkBalanceWithDeduplication() async throws -> ArkBalanceModel {
        return try await taskManager.execute(key: "arkBalance") {
            let result = try await self.wallet.getArkBalance()
            print("📊 Ark balance: \(result.spendableSat) sats spendable, \(result.totalPendingSat) sats pending")
            return result
        }
    }
    
    /// Get onchain balance with task deduplication
    func getOnchainBalanceWithDeduplication() async throws -> OnchainBalanceModel {
        return try await taskManager.execute(key: "onchainBalance") {
            let result = try await self.wallet.getOnchainBalance()
            print("📊 Onchain balance: \(result.totalSat) sats total, \(result.trustedSpendableSat) sats spendable")
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
            let (arkBal, onchainBal) = try await (arkBalanceResult, onchainBalanceResult)
            
            // Update UI state
            self.arkBalance = arkBal
            self.onchainBalance = onchainBal
            updateTotalBalance()
            
            // Save both balances to persistence
            await saveArkBalanceToSwiftData(arkBal)
            await saveOnchainBalanceToSwiftData(onchainBal)
            
            error = nil
            print("✅ All balances refreshed successfully")
            
        } catch {
            self.error = "Failed to refresh balances: \(error)"
            print("❌ Failed to refresh balances: \(error)")
        }
    }
    
    /// Refresh just Ark balance
    func refreshArkBalance() async {
        do {
            arkBalance = try await getArkBalanceWithDeduplication()
            updateTotalBalance()
            
            // Save to persistence
            if let balance = arkBalance {
                await saveArkBalanceToSwiftData(balance)
            }
            
            error = nil
        } catch {
            self.error = "Failed to get Ark balance: \(error)"
            print("❌ Failed to get Ark balance: \(error)")
        }
    }
    
    /// Refresh just onchain balance
    func refreshOnchainBalance() async {
        do {
            onchainBalance = try await getOnchainBalanceWithDeduplication()
            updateTotalBalance()
            
            // Save to persistence
            if let balance = onchainBalance {
                await saveOnchainBalanceToSwiftData(balance)
            }
            
            error = nil
        } catch {
            self.error = "Failed to get onchain balance: \(error)"
            print("❌ Failed to get onchain balance: \(error)")
        }
    }
    
    // MARK: - Direct Balance Access Methods
    
    /// Get the current Ark balance model
    func getArkBalance() async throws -> ArkBalanceModel {
        return try await getArkBalanceWithDeduplication()
    }
    
    /// Get the current onchain balance model
    func getCurrentOnchainBalance() async throws -> OnchainBalanceModel {
        return try await getOnchainBalanceWithDeduplication()
    }
    
    // MARK: - Balance Calculation
    
    /// Update the total balance based on current ark and onchain balances
    func updateTotalBalance() {
        guard let arkBalance = arkBalance, let onchainBalance = onchainBalance else {
            print("⚠️ Cannot calculate total balance - missing ark or onchain balance")
            return
        }
        
        totalBalance = TotalBalanceModel(arkBalance: arkBalance, onchainBalance: onchainBalance)
        print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (\(totalBalance?.totalSpendableSat ?? 0) spendable)")
    }
    
    // MARK: - State Reset
    
    /// Reset all balance state (useful when wallet changes or errors occur)
    func resetBalances() {
        arkBalance = nil
        onchainBalance = nil
        totalBalance = nil
        error = nil
        
        // Clear persisted balance data
        Task {
            await clearPersistedArkBalance()
            await clearPersistedOnchainBalance()
        }
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
    
    /// Get a snapshot of current balance state for logging or debugging
    func getBalanceSnapshot() -> String {
        let arkSats = arkBalance?.spendableSat ?? 0
        let onchainSats = onchainBalance?.trustedSpendableSat ?? 0
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
        
        // Load persisted balances on startup
        Task {
            await loadPersistedArkBalance()
            await loadPersistedOnchainBalance()
        }
    }
    
    /// Load persisted Ark balance from SwiftData
    private func loadPersistedArkBalance() async {
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
                if persistedBalance.isValid {
                    // Use cached balance if still valid
                    self.arkBalance = persistedBalance
                    updateTotalBalance()
                    print("📱 Loaded valid persisted Ark balance (spendable: \(persistedBalance.spendableSat) sats)")
                } else {
                    print("⏰ Persisted Ark balance is stale, will fetch fresh data")
                }
            } else {
                print("📱 No persisted Ark balance found")
            }
        } catch {
            print("❌ Failed to load persisted Ark balance: \(error)")
        }
    }
    
    /// Save Ark balance to SwiftData
    private func saveArkBalanceToSwiftData(_ apiBalance: ArkBalanceModel) async {
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
                existingBalance.update(from: apiBalance)
                print("💾 Updated persisted Ark balance")
            } else {
                // Create new record with the API data
                let newBalance = ArkBalanceModel(
                    spendableSat: apiBalance.spendableSat,
                    pendingLightningSendSat: apiBalance.pendingLightningSendSat,
                    pendingInRoundSat: apiBalance.pendingInRoundSat,
                    pendingExitSat: apiBalance.pendingExitSat,
                    pendingBoardSat: apiBalance.pendingBoardSat
                )
                modelContext.insert(newBalance)
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
    
    /// Load persisted Onchain balance from SwiftData
    private func loadPersistedOnchainBalance() async {
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
                if persistedBalance.isValid {
                    // Use cached balance if still valid
                    self.onchainBalance = persistedBalance
                    updateTotalBalance()
                    print("📱 Loaded valid persisted Onchain balance (spendable: \(persistedBalance.trustedSpendableSat) sats)")
                } else {
                    print("⏰ Persisted Onchain balance is stale, will fetch fresh data")
                }
            } else {
                print("📱 No persisted Onchain balance found")
            }
        } catch {
            print("❌ Failed to load persisted Onchain balance: \(error)")
        }
    }
    
    /// Save Onchain balance to SwiftData
    private func saveOnchainBalanceToSwiftData(_ onchainBalance: OnchainBalanceModel) async {
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
                // Update existing record with new data
                existingBalance.update(from: onchainBalance)
                print("💾 Updated persisted Onchain balance")
            } else {
                // Insert the decoded balance directly (it's already a @Model)
                modelContext.insert(onchainBalance)
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
