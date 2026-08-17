//
//  BalanceView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct BalanceView_iOS: View {
    @Environment(WalletManager.self) private var manager
    @State private var showingBoardingModal = false
    @State private var showingOffboardingModal = false
    @State private var showingRefreshModal = false
    @State private var showingBalanceInfo = false
    @State private var refreshStatusReloadTrigger = 0
    
    private var canBoard: Bool {
        guard let onchainBalance = manager.onchainBalance else { return false }
        return onchainBalance.spendableSat > 0
    }
    
    private var canOffboard: Bool {
        guard let arkBalance = manager.arkBalance else { return false }
        return arkBalance.spendableSat > 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack {
                    // Ark Balance
                    BalanceDetailCard(
                        title: "Payments\nBalance",
                        description: "Fast, low-fee payments.\nMaintenance fees.",
                        spendable: manager.arkBalance?.spendableSat,
                        pending: manager.arkBalance?.totalPendingSat,
                        total: manager.arkBalance?.totalSat,
                        color: .Arke.blue,
                        imageName: "wallet",
                        pendingItems: manager.arkBalance.map { arkBalance in
                            [
                                (label: "Pending Lightning send", amount: arkBalance.pendingLightningSendSat),
                                (label: "Pending in round", amount: arkBalance.pendingInRoundSat),
                                (label: "Pending board", amount: arkBalance.pendingBoardSat),
                                (label: "Pending exit", amount: arkBalance.pendingExitSat)
                            ]
                        }
                    )
                    .padding(20)
                    
                    if !manager.isReadOnlyMode {
                        BalanceRefreshStatusContainerCompact(
                            onRefresh: {
                                showingRefreshModal = true
                            },
                            reloadTrigger: refreshStatusReloadTrigger
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                //.background(.ultraThinMaterial)
                //.background(Color.black.opacity(0.35))
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.65) // This is your "tint"
                    }
                )
                .cornerRadius(25)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(radius: 10, x: 0, y: 5)
                
                // Board/Offboard buttons (only show in primary mode)
                if !manager.isReadOnlyMode {
                    HStack {
                        Button(action: {
                            showingBoardingModal = true
                        }) {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(ArkeIconButtonStyle())
                        .disabled(!canBoard)
                        .help(canBoard ? String(localized: "balance_move_to_payments", defaultValue: "Move funds to payments") : String(localized: "balance_no_funds_savings", defaultValue: "No funds available in savings to move to payments"))
                        
                        Button(action: {
                            showingOffboardingModal = true
                        }) {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(ArkeIconButtonStyle())
                        .disabled(!canOffboard)
                        .help(canOffboard ? String(localized: "balance_move_to_savings", defaultValue: "Move funds to savings") : String(localized: "balance_no_funds_payments", defaultValue: "No funds available in payments to move to savings"))
                    }
                    .frame(maxWidth: 100)
                }
                
                // Onchain Balance
                BalanceDetailCard(
                    title: "Savings\nBalance",
                    description: "Slow, high-fee payments.\nNo maintenance fees.",
                    spendable: manager.onchainBalance?.spendableSat,
                    pending: manager.onchainBalance?.pendingSat,
                    total: manager.onchainBalance?.totalSat,
                    color: .orange,
                    imageName: "safe",
                    pendingItems: nil
                )
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.65) // This is your "tint"
                    }
                )
                .cornerRadius(25)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(radius: 10, x: 0, y: 5)
                
                /*
                BalanceRefreshStatusContainer(
                    onRefresh: {
                        showingRefreshModal = true
                    },
                    reloadTrigger: refreshStatusReloadTrigger
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 15)
                */
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(
            Image("card-big")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .refreshable {
            // Only allow refresh in primary mode
            if !manager.isReadOnlyMode {
                await manager.refresh()
            }
        }
        .sheet(isPresented: $showingBoardingModal) {
            BoardingModalView(manager: manager)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingOffboardingModal) {
            OffboardingModalView(manager: manager)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingRefreshModal) {
            RefreshModalView(manager: manager) {
                Task {
                    await manager.refresh()
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: showingRefreshModal) { _, isShowing in
            if !isShowing {
                // Sheet was dismissed, reload status
                refreshStatusReloadTrigger += 1
            }
        }
        .sheet(isPresented: $showingBalanceInfo) {
            BalanceInfoSheet()
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingBalanceInfo = true
                }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        //.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            // Only sync and fetch balance in primary mode (requires ASP connection)
            if !manager.isReadOnlyMode {
                do {
                    try await manager.sync()
                    _ = try await manager.getArkBalance()
                } catch {
                    print("Failed to sync or get balance: \(error)")
                }
            }
        }
    }
}
