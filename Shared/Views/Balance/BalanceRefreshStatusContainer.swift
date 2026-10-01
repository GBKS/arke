//
//  BalanceRefreshStatusContainer.swift
//  Arke
//
//  Created by Christoph on 2/23/26.
//

import SwiftUI
import ArkeUI

struct BalanceRefreshStatusContainer: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: BalanceRefreshStatusViewModel?
    @State private var updateTimer: Timer?
    
    var onRefresh: (() async -> Void)?
    var reloadTrigger: Int = 0
    
    var body: some View {
        BalanceRefreshStatus(data: makeData())
            .task { 
                if viewModel == nil {
                    viewModel = BalanceRefreshStatusViewModel(walletManager: walletManager)
                }
                await viewModel?.loadData()
            }
            .onAppear { startBlockHeightUpdater() }
            .onDisappear { stopBlockHeightUpdater() }
            .onChange(of: reloadTrigger) { _, _ in
                Task {
                    await viewModel?.loadData()
                }
            }
            .onChange(of: walletManager.transactionVersion) { _, _ in
                Task {
                    await viewModel?.loadData()
                }
            }
            .onChange(of: walletManager.isInitialized) { _, isInitialized in
                guard isInitialized else { return }
                Task {
                    await viewModel?.loadData()
                }
            }
    }
    
    private func makeData() -> BalanceRefreshData {
        guard let viewModel = viewModel, viewModel.hasCompletedInitialLoad else {
            return BalanceRefreshData(isLoading: true)
        }
        
        // Simple color scheme based on state
        let (foreground, background, icon) = colorScheme(viewModel: viewModel)
        
        return BalanceRefreshData(
            isLoading: false,
            hasActiveRefresh: viewModel.hasActiveRefresh,
            urgencyForegroundColor: foreground,
            urgencyBackgroundColor: background,
            urgencyIconColor: icon,
            statusMessage: viewModel.statusMessage,
            timeUntilExpiry: nil,
            isExpired: false,
            expiredAgoString: nil,
            showActionButton: viewModel.hasVtxosToRefresh,
            nextRoundStartTime: viewModel.nextRoundStartTime,
            totalAmountToRefresh: viewModel.totalAmountToRefresh > 0 ? viewModel.totalAmountToRefresh : nil,
            onRefresh: onRefresh
        )
    }
    
    private func colorScheme(viewModel: BalanceRefreshStatusViewModel) -> (Color, Color, Color) {
        if viewModel.hasActiveRefresh {
            // Blue for refreshing
            return (.white, .blue, .white)
        } else if viewModel.hasVtxosToRefresh {
            // Orange for "Refresh now"
            return (.white, .orange, .white)
        } else {
            // Gray for countdown
            return (.white, .black.opacity(0.15), .black)
        }
    }
    
    private func startBlockHeightUpdater() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                viewModel?.latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            }
        }
    }
    
    private func stopBlockHeightUpdater() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
