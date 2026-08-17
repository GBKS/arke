//
//  ArkBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct ArkBalanceView: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @Query(filter: #Predicate<ArkBalanceModel> { $0.id == "ark_balance" })
    private var balances: [ArkBalanceModel]
    @State private var isLoadingArkBalance = false
    @State private var error: String?
    
    private var arkBalance: ArkBalanceModel? {
        balances.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(localized: "balance_ark", defaultValue: "Ark Balance"))
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
            }
            
            if isLoadingArkBalance {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let error = error {
                ErrorBox(errorMessage: error)
            } else if arkBalance == nil && !isLoadingArkBalance {
                VStack {
                    Image(systemName: "bitcoinsign.circle")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_no_ark_balance", defaultValue: "No ark balance data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let balance = arkBalance {
                VStack(spacing: 8) {
                    // Summary view
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "balance_total", defaultValue: "Total Balance"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.shared.formatAmount(balance.totalSat))
                                .font(.title2)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        // Total pending section
                        if balance.totalPendingSat > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.statusPending)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(BitcoinFormatter.shared.formatAmount(balance.totalPendingSat))
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(localized: "balance_spendable", defaultValue: "Spendable"))
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
                        BalanceRowView(label: "Lightning Send", amount: balance.pendingLightningSendSat)
                        BalanceRowView(label: "In Round", amount: balance.pendingInRoundSat)
                        BalanceRowView(label: "Exit", amount: balance.pendingExitSat)
                        BalanceRowView(label: "Board", amount: balance.pendingBoardSat)
                    }
                }
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await loadArkBalance()
        }
    }
    
    private func loadArkBalance() async {
        isLoadingArkBalance = true
        error = nil
        
        print("loadArkBalance")
        
        // Use throwing version to get specific error for this operation
        do {
            _ = try await walletManager.getArkBalance()
            // Success - SwiftData will be updated via the service layer
        } catch {
            // Capture only Ark balance specific errors
            self.error = "Failed to load Ark balance: \(error.localizedDescription)"
            print("❌ ArkBalanceView - Failed to refresh: \(error)")
        }
        
        isLoadingArkBalance = false
    }
}
