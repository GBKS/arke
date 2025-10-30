//
//  OnchainBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import SwiftData

struct OnchainBalanceView: View {
    @Environment(WalletManager.self) private var walletManager
    @Query(filter: #Predicate<OnchainBalanceModel> { $0.id == "onchain_balance" }) 
    private var persistedOnchainBalances: [OnchainBalanceModel]
    
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
                Text("Onchain Balance")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await walletManager.refreshOnchainBalance()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(walletManager.isRefreshing)
            }
            
            if walletManager.isRefreshing && onchainBalance == nil {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let error = walletManager.error {
                ErrorView(errorMessage: error)
            } else if onchainBalance == nil {
                VStack {
                    Image(systemName: "bitcoinsign.circle")
                        .foregroundStyle(.secondary)
                    Text("No onchain balance data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let balance = onchainBalance {
                VStack(spacing: 8) {
                    // Summary view
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.formatAmount(balance.totalSat))
                                .font(.title2)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Spendable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.formatAmount(balance.trustedSpendableSat))
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Divider()
                    
                    // Detailed breakdown
                    VStack(alignment: .leading, spacing: 4) {
                        BalanceRowView(label: "Confirmed", amount: balance.confirmedSat)
                        BalanceRowView(label: "Trusted Pending", amount: balance.trustedPendingSat)
                        BalanceRowView(label: "Untrusted Pending", amount: balance.untrustedPendingSat)
                        BalanceRowView(label: "Immature", amount: balance.immatureSat)
                    }
                }
            }
        }
        .task {
            // Trigger initial refresh if no data is available
            if onchainBalance == nil && !walletManager.isRefreshing {
                await walletManager.refreshOnchainBalance()
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnchainBalanceView()
            .environment(WalletManager(useMock: true))
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
    }
}
