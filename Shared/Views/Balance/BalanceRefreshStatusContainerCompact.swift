//
//  BalanceRefreshStatusContainerCompact.swift
//  Arke
//
//  Created by Christoph on 4/16/26.
//

import SwiftUI
import ArkeUI
import Combine

struct BalanceRefreshStatusContainerCompact: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: BalanceRefreshStatusViewModel?
    @State private var updateTimer: Timer?
    @State private var currentTime = Date()

    var onRefresh: (() async -> Void)?
    var reloadTrigger: Int = 0

    var body: some View {
        BalanceRefreshStatusCompact(data: makeData(), currentTime: currentTime)
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
            // The service records a server verdict *after* the refetch that
            // bumps transactionVersion (Refresh_Deduplication.md §10, D5).
            .onChange(of: walletManager.refreshStatusVersion) { _, _ in
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
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                currentTime = Date()
            }
    }

    private func makeData() -> BalanceRefreshData {
        guard let viewModel = viewModel, viewModel.hasCompletedInitialLoad else {
            return BalanceRefreshData(isLoading: true)
        }

        let state = viewModel.cardState
        let (foreground, background, icon) = colorScheme(state: state)
        var isRefused = false
        if case .refused = state { isRefused = true }

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
            showActionButton: state.showsAction,
            nextRoundStartTime: viewModel.nextRoundStartTime,
            totalAmountToRefresh: viewModel.totalAmountToRefresh > 0 ? viewModel.totalAmountToRefresh : nil,
            heldBackAmount: viewModel.heldBackVtxos.isEmpty ? nil : viewModel.totalHeldBackAmount,
            isRefused: isRefused,
            detailMessage: viewModel.detailMessage,
            systemImage: BalanceRefreshStatusContainer.systemImage(for: state),
            onRefresh: onRefresh
        )
    }

    private func colorScheme(state: BalanceRefreshCardState) -> (Color, Color, Color) {
        switch state {
        case .refreshing:
            // Blue for refreshing
            return (.white, .blue, .blue)
        case .refreshNow:
            // Orange for "Refresh now"
            return (.white, .Arke.orange, .Arke.orange)
        case .refused, .tooSmall:
            // Countdown grey with a warning icon: attention, not alarm.
            return (.white, .black.opacity(0.15), .Arke.orange)
        case .countdown, .idle:
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
