//
//  ReadOnlyBalanceService.swift
//  Arke
//
//  Created by Christoph on 5/7/26.
//

import Foundation
import SwiftData

/// Lightweight balance service for read-only mode (secondary devices)
/// Only loads balances from SwiftData/CloudKit - no wallet operations
@MainActor
@Observable
class ReadOnlyBalanceService {
    
    // MARK: - Published Properties
    
    /// Current Ark balance (loaded from SwiftData)
    var arkBalance: ArkBalanceModel?
    
    /// Current onchain balance (loaded from SwiftData)
    var onchainBalance: OnchainBalanceModel?
    
    /// Combined total balance across all wallets
    var totalBalance: TotalBalanceModel?
    
    /// Error message for balance operations
    var error: String?
    
    // MARK: - Dependencies

    private var modelContext: ModelContext?

    /// Token for the CloudKit change observer, so it is only installed once
    @ObservationIgnored private var cloudKitChangeObserver: NSObjectProtocol?

    // MARK: - Computed Properties for UI
    
    /// True if there are any pending balances
    var hasPendingBalance: Bool {
        totalBalance?.hasPendingBalance ?? false
    }
    
    /// True if user has any spendable funds
    var hasSpendableBalance: Bool {
        totalBalance?.hasSpendableBalance ?? false
    }

    /// True while neither balance row has arrived from CloudKit yet — a freshly
    /// installed secondary device, where the first import can take well over a
    /// minute. `updateTotalBalance()` substitutes zero-balance models so the UI
    /// always has something to render, which means "synced, and you have 0
    /// sats" and "nothing has synced yet" look identical without this flag.
    /// Surfaced so the UI can say "syncing from iCloud" instead of presenting
    /// an empty wallet as fact.
    var isWaitingForInitialSync: Bool {
        arkBalance == nil && onchainBalance == nil
    }
    
    // MARK: - Initialization
    
    init() {
        // No dependencies needed for read-only mode
    }

    // MARK: - Model Context Setup

    /// Set the model context and load persisted balances
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        // Load persisted balances synchronously for instant UI display
        loadPersistedArkBalanceSync()
        loadPersistedOnchainBalanceSync()
        updateTotalBalance()

        observeCloudKitChanges()
    }

    // MARK: - CloudKit Change Observation

    /// Re-reads the balance rows whenever CloudKit imports records mid-session.
    /// Without this, a secondary device shows whatever was in the store at
    /// launch for the rest of the session: the load above runs once, and on a
    /// fresh install it runs *before* the first import lands, so the balance
    /// stays 0 until the next launch (2026-09-23, second iPhone). Nothing else
    /// refreshes it — pull-to-refresh is wallet/server work, which a read-only
    /// device doesn't do. CloudKitObserver already debounces the underlying
    /// remote-change notifications.
    private func observeCloudKitChanges() {
        guard cloudKitChangeObserver == nil else { return }

        cloudKitChangeObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshBalances()
            }
        }
    }


    // MARK: - Balance Loading
    
    /// Load persisted Ark balance from SwiftData (synchronous)
    private func loadPersistedArkBalanceSync() {
        guard let modelContext = modelContext else {
            print("⚠️ [ReadOnlyBalanceService] No model context available for loading Ark balance")
            return
        }
        
        do {
            // Newest first: the row is a singleton by convention, but CloudKit
            // forbids unique constraints, so two devices can each create an
            // "ark_balance" row and an unsorted `.first` would pick arbitrarily.
            let descriptor = FetchDescriptor<ArkBalanceModel>(
                predicate: #Predicate<ArkBalanceModel> { $0.id == "ark_balance" },
                sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
            )
            let persistedBalances = try modelContext.fetch(descriptor)

            if let persistedBalance = persistedBalances.first {
                self.arkBalance = persistedBalance
                print("📱 [ReadOnlyBalanceService] Loaded Ark balance from CloudKit (spendable: \(persistedBalance.spendableSat) sats)")
            } else {
                print("📱 [ReadOnlyBalanceService] No Ark balance found in CloudKit yet")
            }
        } catch {
            print("❌ [ReadOnlyBalanceService] Failed to load Ark balance: \(error)")
        }
    }
    
    /// Load persisted Onchain balance from SwiftData (synchronous)
    private func loadPersistedOnchainBalanceSync() {
        guard let modelContext = modelContext else {
            print("⚠️ [ReadOnlyBalanceService] No model context available for loading Onchain balance")
            return
        }
        
        do {
            // Newest first — see loadPersistedArkBalanceSync
            let descriptor = FetchDescriptor<OnchainBalanceModel>(
                predicate: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" },
                sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
            )
            let persistedBalances = try modelContext.fetch(descriptor)

            if let persistedBalance = persistedBalances.first {
                self.onchainBalance = persistedBalance
                print("📱 [ReadOnlyBalanceService] Loaded Onchain balance from CloudKit (spendable: \(persistedBalance.spendableSat) sats)")
            } else {
                print("📱 [ReadOnlyBalanceService] No Onchain balance found in CloudKit yet")
            }
        } catch {
            print("❌ [ReadOnlyBalanceService] Failed to load Onchain balance: \(error)")
        }
    }
    
    /// Update the total balance based on current ark and onchain balances
    func updateTotalBalance() {
        // Create zero-balance models for any missing balances
        // This ensures the UI always shows something, even during partial loads or CloudKit sync delays
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
            print("📊 [ReadOnlyBalanceService] Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (waiting for CloudKit sync)")
        } else if arkBalance == nil {
            print("📊 [ReadOnlyBalanceService] Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (ark balance not synced yet, using onchain only)")
        } else if onchainBalance == nil {
            print("📊 [ReadOnlyBalanceService] Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (onchain balance not synced yet, using ark only)")
        } else {
            print("📊 [ReadOnlyBalanceService] Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (\(totalBalance?.totalSpendableSat ?? 0) spendable)")
        }
    }
    
    /// Refresh balances by reloading from SwiftData
    /// (In read-only mode, this just reloads from local cache - data is synced via CloudKit push)
    func refreshBalances() {
        loadPersistedArkBalanceSync()
        loadPersistedOnchainBalanceSync()
        updateTotalBalance()
    }
}
