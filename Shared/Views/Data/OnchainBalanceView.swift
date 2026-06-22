//
//  OnchainBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct OnchainBalanceView: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @Query(filter: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" }) 
    private var persistedOnchainBalances: [OnchainBalanceModel]
    @State private var isLoadingOnchainBalance = false
    @State private var error: String?
    
    // Use the persisted balance if available, otherwise fall back to manager
    private var onchainBalance: OnchainBalanceModel? {
        if let persisted = persistedOnchainBalances.first {
            return persisted
        }
        return walletManager.onchainBalance
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("balance_onchain")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
            }
            
            if isLoadingOnchainBalance {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let error = error {
                ErrorBox(errorMessage: error)
            } else if onchainBalance == nil && !isLoadingOnchainBalance {
                VStack {
                    Image(systemName: "bitcoinsign.circle")
                        .foregroundStyle(.secondary)
                    Text("data_no_onchain_balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let balance = onchainBalance {
                VStack(spacing: 8) {
                    // Summary view
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("balance_total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.shared.formatAmount(balance.totalSat))
                                .font(.title2)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("balance_spendable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.shared.formatAmount(balance.spendableSat))
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.Arke.green)
                        }
                    }
                    
                    Divider()
                    
                    // Detailed breakdown
                    VStack(alignment: .leading, spacing: 4) {
                        BalanceRowView(label: "Confirmed", amount: balance.confirmedSat)
                        BalanceRowView(label: "Pending", amount: balance.pendingSat)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .task(id: reloadTrigger) {
            await loadOnchainBalance()
        }
    }
    
    private func loadOnchainBalance() async {
        isLoadingOnchainBalance = true
        error = nil
        
        print("loadOnchainBalance")
        
        // Use throwing version to get specific error for this operation
        do {
            _ = try await walletManager.getOnchainBalance()
            // Success - SwiftData will be updated via the service layer
        } catch {
            // Capture only Onchain balance specific errors
            self.error = "Failed to load onchain balance: \(error.localizedDescription)"
            print("❌ OnchainBalanceView - Failed to refresh: \(error)")
        }
        
        isLoadingOnchainBalance = false
    }
}
