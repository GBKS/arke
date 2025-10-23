//
//  OnchainBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct OnchainBalanceView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var onchainBalance: OnchainBalanceModel?
    @State private var isLoadingOnchainBalance = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Onchain Balance")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadOnchainBalance()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingOnchainBalance)
            }
            
            if isLoadingOnchainBalance {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if onchainBalance == nil && !isLoadingOnchainBalance {
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
            await loadOnchainBalance()
        }
    }
    
    private func loadOnchainBalance() async {
        isLoadingOnchainBalance = true
        error = nil
        
        print("loadOnchainBalance")
        
        do {
            onchainBalance = try await walletManager.getCurrentOnchainBalance()
        } catch {
            self.error = error.localizedDescription
            onchainBalance = nil
            print("Error loading onchain balance: \(error)")
        }
        
        isLoadingOnchainBalance = false
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
