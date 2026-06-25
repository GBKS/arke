//
//  BalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI

struct BalanceView: View {
    @Environment(WalletManager.self) private var manager
    @State private var showingBoardingModal = false
    @State private var showingOffboardingModal = false
    @State private var showingRefreshModal = false
    @State private var refreshStatusReloadTrigger = 0
    
    private var canBoard: Bool {
        guard let onchainBalance = manager.onchainBalance else { return false }
        return onchainBalance.confirmedSat > 0
    }
    
    private var canOffboard: Bool {
        guard let arkBalance = manager.arkBalance else { return false }
        return arkBalance.spendableSat > 0
    }
    
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
                            color: .Arke.blue,
                            imageName: "wallet",
                            pendingItems: nil
                        )
                    }
                    
                    // Board/Offboard buttons (only in primary mode)
                    if !manager.isReadOnlyMode {
                        HStack {
                            Button(action: {
                                showingBoardingModal = true
                            }) {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(ArkeIconButtonStyle())
                            .disabled(!canBoard)
                            .help(canBoard ? String(localized: "balance_move_to_payments") : String(localized: "balance_no_funds_savings"))
                            
                            Button(action: {
                                showingOffboardingModal = true
                            }) {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(ArkeIconButtonStyle())
                            .disabled(!canOffboard)
                            .help(canOffboard ? String(localized: "balance_move_to_savings") : String(localized: "balance_no_funds_payments"))
                        }
                        .frame(maxWidth: 150)
                    }
                    
                    // Onchain Balance
                    if let onchainBalance = manager.onchainBalance {
                        BalanceDetailCard(
                            title: "Savings balance",
                            description: "Best security · Bitcoin network",
                            spendable: onchainBalance.spendableSat,
                            pending: onchainBalance.pendingSat,
                            total: onchainBalance.totalSat,
                            color: .orange,
                            imageName: "safe",
                            pendingItems: nil
                        )
                    }
                    
                    Divider()
                        .padding(.top, 15)
                    
                    if !manager.isReadOnlyMode {
                        BalanceRefreshStatusContainer(
                            onRefresh: {
                                showingRefreshModal = true
                            },
                            reloadTrigger: refreshStatusReloadTrigger
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 15)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal)
            }
            .padding(20)
        }
        .navigationTitle("nav_title_balance_details")
        .refreshable {
            // Only allow refresh in primary mode
            if !manager.isReadOnlyMode {
                await manager.refresh()
            }
        }
        .sheet(isPresented: $showingBoardingModal) {
            BoardingModalView(manager: manager)
        }
        .sheet(isPresented: $showingOffboardingModal) {
            OffboardingModalView(manager: manager)
        }
        .sheet(isPresented: $showingRefreshModal) {
            RefreshModalView(manager: manager) {
                Task {
                    await manager.refresh()
                }
            }
        }
        .onChange(of: showingRefreshModal) { _, isShowing in
            if !isShowing {
                // Sheet was dismissed, reload status
                refreshStatusReloadTrigger += 1
            }
        }
    }
}
