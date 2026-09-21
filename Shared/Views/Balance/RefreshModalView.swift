//
//  RefreshModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import ArkeUI

private enum RefreshModalState: Hashable {
    case form
    /// A refresh was scheduled by this tap.
    case success
    /// Nothing was scheduled, but nothing failed either. Carries its own copy
    /// because the two reasons need different wording — nothing to do vs. a
    /// check already holding the gate — and neither may claim a refresh this
    /// tap didn't start (Refresh_Deduplication.md).
    case noChange(title: String, message: String)
    case error(String)
}

struct RefreshModalView: View {
    let manager: WalletManager
    var onRefreshComplete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var state: RefreshModalState = .form
    @State private var isLoading = false
    @State private var shouldDismiss = false
    @State private var viewModel: BalanceRefreshStatusViewModel?
    
    var body: some View {
        ZStack {
            switch state {
            case .form:
                RefreshModalFormView(
                    isLoading: isLoading,
                    amountToRefresh: viewModel?.totalAmountToRefresh,
                    vtxoIdsToRefresh: viewModel?.vtxosNeedingRefresh.map { $0.id } ?? [],
                    onConfirm: {
                        Task {
                            await performRefresh()
                        }
                    },
                    onCancel: {
                        dismiss()
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .success:
                RefreshModalSuccessView {
                    onRefreshComplete?()
                    shouldDismiss = true
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .noChange(let title, let message):
                RefreshModalSuccessView(title: title, message: message) {
                    onRefreshComplete?()
                    shouldDismiss = true
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .error(let errorMessage):
                LargeErrorView(
                    title: String(localized: "error_refresh_failed", defaultValue: "Refresh Failed"),
                    errorMessage: errorMessage,
                    image: nil,
                    systemImage: "exclamationmark.triangle.fill",
                    systemImageColor: .orange,
                    onDismiss: {
                        state = .form
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: shouldDismiss) { _, newValue in
            if newValue {
                dismiss()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = BalanceRefreshStatusViewModel(walletManager: manager)
            }
            await viewModel?.loadData()
        }
    }
    
    @MainActor
    private func performRefresh() async {
        let startTime = Date()
        print("🔄 [RefreshModal] Starting refresh at \(startTime)")
        
        isLoading = true
        
        do {
            // Route through VTXORefreshService so selection and the exit /
            // in-flight-refresh exclusions live in one place, and the
            // post-schedule refetch flips the balance card to "Refreshing"
            // without waiting for sheet dismissal (Refresh_Deduplication.md).
            let outcome = try await manager.refreshVTXOsManually()

            let duration = Date().timeIntervalSince(startTime)
            print("✅ [RefreshModal] Refresh request completed in \(String(format: "%.2f", duration))s: \(outcome)")

            isLoading = false
            switch outcome {
            case .scheduled:
                state = .success
            case .nothingToDo:
                // Reachable even though the confirm button requires a
                // non-empty list: the modal's list isn't exit-filtered, so
                // every candidate can still drop out in the service.
                state = .noChange(
                    title: String(localized: "status_refresh_not_needed", defaultValue: "Nothing to refresh"),
                    message: String(localized: "balance_refresh_not_needed", defaultValue: "These VTXOs are either still fresh or already part of a refresh. Nothing new was scheduled.")
                )
            case .alreadyInProgress:
                state = .noChange(
                    title: String(localized: "status_refresh_already_underway", defaultValue: "Already refreshing"),
                    message: String(localized: "balance_refresh_already_underway", defaultValue: "A refresh check is already running and covers these VTXOs. Nothing new was scheduled.")
                )
            case .alreadyIssuedByServer:
                // The server rejected the request because the refresh is
                // already committed to a round. That's the user's goal, so
                // it reads as success, not "Refresh Failed".
                state = .noChange(
                    title: String(localized: "status_refresh_already_underway", defaultValue: "Already refreshing"),
                    message: String(localized: "balance_refresh_already_scheduled", defaultValue: "These VTXOs are already part of a refresh the server has scheduled. It will complete on its own.")
                )
            }
        } catch {
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            print("❌ [RefreshModal] Refresh failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            isLoading = false
            state = .error("Failed to schedule maintenance refresh: \(error.localizedDescription)")
        }
    }
}
