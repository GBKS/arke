//
//  RefreshModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import Bark
import ArkeUI

private enum RefreshModalState: Hashable {
    case form
    case success
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
                    print("DEBUG: RefreshModalSuccessView onDone called")
                    onRefreshComplete?()
                    print("DEBUG: About to call dismiss")
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
            // Get VTXO IDs from view model (already filtered for urgency and excluding those being refreshed)
            guard let viewModel = viewModel else {
                throw NSError(domain: "RefreshModal", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "View model not initialized"
                ])
            }
            
            let vtxoIds = viewModel.vtxosNeedingRefresh.map { $0.id }
            let totalVTXOs = viewModel.vtxos.count
            print("🔄 [RefreshModal] Found \(vtxoIds.count) VTXOs (out of \(totalVTXOs) total) that need refreshing")
            
            // Refresh VTXOs using delegated mode (non-blocking)
            let roundState = try await manager.refreshVtxosDelegated(vtxoIds: vtxoIds)
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            if let roundState = roundState {
                // Refresh was scheduled
                let ongoingText = roundState.ongoing ? " (ongoing)" : ""
                print("✅ [RefreshModal] Refresh completed in \(String(format: "%.2f", duration))s, scheduled in round #\(roundState.id)\(ongoingText)")
            } else {
                // No refresh was needed
                print("✅ [RefreshModal] Refresh completed in \(String(format: "%.2f", duration))s, VTXOs are already fresh")
            }
            
            isLoading = false
            state = .success
        } catch {
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            print("❌ [RefreshModal] Refresh failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            isLoading = false
            state = .error("Failed to schedule maintenance refresh: \(error.localizedDescription)")
        }
    }
}
