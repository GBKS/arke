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
    /// The server refused the inputs and nothing is in flight: an honest
    /// failure with its own title, dismissing the sheet rather than
    /// returning to the form (retrying is pointless for 24 h).
    case refused(title: String, message: String)
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

    /// Shared with the balance card's refused state (same title). Never
    /// claims the funds are lost — the app cannot tell an expiry sweep from
    /// a missed round (Refresh_Deduplication.md §9).
    static var refusedTitle: String {
        String(localized: "status_refresh_refused", defaultValue: "Can't refresh from this device")
    }

    static var refusedMessage: String {
        String(localized: "balance_refresh_refused", defaultValue: "The server refused these coins: it considers them unusable, usually because they were already used in a round this wallet didn't see, or they are temporarily blocked. Recovering the wallet from your recovery phrase may restore them — contact support before you do. The app won't retry for 24 hours.")
    }

    var body: some View {
        ZStack {
            switch state {
            case .form:
                RefreshModalFormView(
                    isLoading: isLoading,
                    amountToRefresh: viewModel?.totalAmountToRefresh,
                    vtxoIdsToRefresh: viewModel?.vtxosNeedingRefresh.map { $0.id } ?? [],
                    minimumAmountSats: viewModel?.minimumRefreshAmountSats,
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
            case .refused(let title, let message):
                LargeErrorView(
                    title: title,
                    errorMessage: message,
                    image: nil,
                    systemImage: "exclamationmark.triangle.fill",
                    systemImageColor: .orange,
                    onDismiss: {
                        onRefreshComplete?()
                        shouldDismiss = true
                    }
                )
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
            // Opened from the card's refused state: nothing can be scheduled
            // and the server holds the rest back, so start on the honest
            // screen instead of a form whose Start would do nothing
            // (Refresh_Deduplication.md §10, design 6). Decided by the same
            // resolver as the card so the two cannot contradict each other —
            // a refresh in flight outranks the refusal here as well.
            if state == .form, let viewModel, case .refused = viewModel.cardState {
                state = .refused(title: Self.refusedTitle, message: Self.refusedMessage)
            }
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
                // non-empty list and the modal now exit-filters: a candidate
                // can still start exiting, or join an in-flight refresh,
                // between the modal's load and the service's own check.
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
            case .rejectedByServer:
                // The server considers these inputs spent, exited or banned
                // and nothing is in flight: this wallet's view is out of
                // date. Never claim the funds are lost — the app cannot tell
                // an expiry sweep from a missed round (Refresh_Deduplication.md §9).
                state = .refused(title: Self.refusedTitle, message: Self.refusedMessage)
            case .belowMinimum(let totalSats):
                // bark would refuse to build this refresh before writing
                // anything (§10, D1). Nothing scheduled, nothing failed.
                let total = BitcoinFormatter.shared.formatAmount(Int(totalSats))
                let minimum = BitcoinFormatter.shared.formatAmount(manager.minimumRefreshAmountSats)
                state = .noChange(
                    title: String(localized: "status_refresh_too_small", defaultValue: "Too small to refresh"),
                    message: String(localized: "balance_refresh_too_small %@ %@", defaultValue: "These coins total \(total), below the \(minimum) a refresh needs. Nothing was scheduled.")
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
