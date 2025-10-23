//
//  BalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct BalanceView: View {
    @Environment(WalletManager.self) private var manager
    @State private var showingBoardingModal = false
    @State private var showingOffboardingModal = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Detailed Breakdowns
                VStack(spacing: 16) {
                    // Ark Balance
                    if let arkBalance = manager.arkBalance {
                        BalanceDetailCard(
                            title: "Payments balance",
                            description: "Fast & low fees · Ark network",
                            spendable: arkBalance.spendableSat,
                            pending: arkBalance.totalPendingSat,
                            total: arkBalance.totalSat,
                            color: .blue,
                            imageName: "wallet"
                        )
                    }
                    
                    // Board Button
                    HStack {
                        Button(action: {
                            showingBoardingModal = true
                        }) {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(ArkeIconButtonStyle())
                        
                        Button(action: {
                            showingOffboardingModal = true
                        }) {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(ArkeIconButtonStyle())
                    }
                    
                    // Onchain Balance
                    if let onchainBalance = manager.onchainBalance {
                        BalanceDetailCard(
                            title: "Savings balance",
                            description: "Best security · Bitcoin network",
                            spendable: onchainBalance.trustedSpendableSat,
                            pending: onchainBalance.trustedPendingSat + onchainBalance.untrustedPendingSat,
                            total: onchainBalance.totalSat,
                            color: .orange,
                            imageName: "safe"
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Your balance details")
        .refreshable {
            await manager.refresh()
        }
        .sheet(isPresented: $showingBoardingModal) {
            BoardingModalView(manager: manager)
        }
        .sheet(isPresented: $showingOffboardingModal) {
            OffboardingModalView(manager: manager)
        }
    }
}

#Preview {
    BalanceView()
        .environment(WalletManager(useMock: true))
}
