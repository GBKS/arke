//
//  BalanceRefreshStatus.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import ArkeUI
import Combine
import OSLog

struct BalanceRefreshTag: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: BalanceRefreshStatusViewModel?
    @State private var updateTimer: Timer?
    
    /// Logger for balance refresh tag operations
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "BalanceRefreshTag")
    
    // MARK: - Computed Properties
    
    private var hasCompletedInitialLoad: Bool {
        viewModel?.hasCompletedInitialLoad ?? false
    }
    
    private var hasVtxosToRefresh: Bool {
        viewModel?.hasVtxosToRefresh ?? false
    }
    
    // MARK: - Body
    
    var body: some View {
        let shouldShow = hasCompletedInitialLoad && hasVtxosToRefresh

        let _ = Self.logger.debug("Visibility check: hasCompletedInitialLoad=\(self.hasCompletedInitialLoad), hasVtxosToRefresh=\(self.hasVtxosToRefresh), shouldShow=\(shouldShow)")
        
        return contentView
            .opacity(shouldShow ? 1 : 0)
            .task {
                Self.logger.debug(".task modifier triggered")
                if viewModel == nil {
                    viewModel = BalanceRefreshStatusViewModel(walletManager: walletManager)
                }
                await viewModel?.loadData()
            }
            .onAppear {
                Self.logger.debug(".onAppear triggered")
                startBlockHeightUpdater()
            }
            .onDisappear {
                Self.logger.debug(".onDisappear triggered")
                stopBlockHeightUpdater()
            }
            .onChange(of: walletManager.transactionVersion) { _, _ in
                Task {
                    await viewModel?.loadData()
                }
            }
            .onChange(of: walletManager.arkInfo) { _, newArkInfo in
                Self.logger.debug("arkInfo changed, newArkInfo exists: \(newArkInfo != nil)")
                
                // If wallet just became initialized and we haven't loaded data yet, load it now
                if newArkInfo != nil && !hasCompletedInitialLoad {
                    Self.logger.debug("Wallet initialized, loading data")
                    Task {
                        await viewModel?.loadData()
                    }
                }
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        HStack(spacing: 8) {
            Text("balance_refresh_now")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.orange)
        .cornerRadius(5)
    }
    
    // MARK: - Helper Methods
    
    /// Start timer to update block height every 30 seconds
    private func startBlockHeightUpdater() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                viewModel?.latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            }
        }
    }
    
    /// Stop the update timer
    private func stopBlockHeightUpdater() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

// MARK: - Previews

/// Preview wrapper that shows the tag
private struct BalanceRefreshTagPreview: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("balance_refresh_now")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.orange)
        .cornerRadius(5)
        .padding()
        .frame(width: 200)
    }
}
