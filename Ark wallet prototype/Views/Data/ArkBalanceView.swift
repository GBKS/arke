//
//  ArkBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct ArkBalanceView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var arkBalance: ArkBalanceModel?
    @State private var isLoadingArkBalance = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Ark Balance")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadArkBalance()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingArkBalance)
            }
            
            if isLoadingArkBalance {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let error = error {
                ErrorView(errorMessage: error)
            } else if arkBalance == nil && !isLoadingArkBalance {
                VStack {
                    Image(systemName: "bitcoinsign.circle")
                        .foregroundStyle(.secondary)
                    Text("No ark balance data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let balance = arkBalance {
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
                        
                        // Total pending section
                        if balance.totalPendingSat > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pending")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(BitcoinFormatter.formatAmount(balance.totalPendingSat))
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Spendable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(BitcoinFormatter.formatAmount(balance.spendableSat))
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
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
        .task {
            await loadArkBalance()
        }
    }
    
    private func loadArkBalance() async {
        isLoadingArkBalance = true
        error = nil
        
        print("loadArkBalance")
        
        do {
            arkBalance = try await walletManager.getArkBalance()
        } catch {
            self.error = error.localizedDescription
            arkBalance = nil
            print("Error loading ark balance: \(error)")
        }
        
        isLoadingArkBalance = false
    }
}

#Preview {
    NavigationStack {
        ArkBalanceView()
            .environment(WalletManager(useMock: true))
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
    }
}
