//
//  VTXODeveloperActionsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/14/25.
//

import SwiftUI
import ArkeUI
import Bark

struct VTXODeveloperActionsView: View {
    let vtxo: VTXOModel
    let minimumRefreshAmountSats: UInt64
    var onActionComplete: (() async -> Void)? = nil
    
    @Environment(WalletManager.self) private var walletManager
    
    @State private var isRefreshing = false
    @State private var isExiting = false
    @State private var isOffboarding = false
    @State private var refreshResult: String?
    @State private var refreshError: String?
    @State private var exitResult: String?
    @State private var exitError: String?
    @State private var offboardResult: String?
    @State private var offboardError: String?
    @State private var refreshFeeEstimate: FeeEstimate?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                // Refresh Button - only show if VTXO amount is large enough
                if vtxo.amountSat > minimumRefreshAmountSats {
                    Button {
                        Task {
                            await handleRefresh()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                                    .foregroundStyle(Color.Arke.goldLabel)
                            }
                            if let feeEstimate = refreshFeeEstimate {
                                if feeEstimate.feeSats == 0 {
                                    let freeText = L10n.feeFree
                                    Text(String(localized: "action_refresh_with_fee %@", defaultValue: "Refresh (\(freeText))"))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.Arke.goldLabel)
                                } else {
                                    let formattedFee = BitcoinFormatter.shared.formatAmount(Int(feeEstimate.feeSats))
                                    Text(String(localized: "action_refresh_with_fee %@", defaultValue: "Refresh (\(formattedFee))"))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.Arke.goldLabel)
                                }
                            } else {
                                Text(String(localized: "button_refresh", defaultValue: "Refresh"))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.Arke.goldLabel)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing || isExiting || isOffboarding || vtxo.state == .locked)
                }
                
                // Offboard Button
                Button {
                    Task {
                        await handleOffboard()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isOffboarding {
                            ProgressView()
                                .controlSize(.small)
                                .foregroundStyle(Color.Arke.goldLabel)
                        }
                        Text(String(localized: "button_offboard", defaultValue: "Offboard"))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Arke.goldLabel)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || isExiting || isOffboarding || vtxo.state == .locked)
                
                // Exit Button
                Button {
                    Task {
                        await handleExit()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isExiting {
                            ProgressView()
                                .controlSize(.small)
                                .foregroundStyle(Color.Arke.goldLabel)
                        }
                        Text(String(localized: "button_exit", defaultValue: "Exit"))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Arke.goldLabel)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || isExiting || isOffboarding)
            }
            
            // Refresh Error
            if let refreshError = refreshError {
                ErrorBox(
                    errorMessage: refreshError,
                    onRetry: {
                        Task {
                            await handleRefresh()
                        }
                    },
                    onDismiss: {
                        self.refreshError = nil
                    }
                )
            }
            
            // Refresh Result
            if let refreshResult = refreshResult {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.Arke.green)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "status_refresh_successful", defaultValue: "Refresh Successful"))
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(refreshResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(L10n.balanceVtxoRefreshNote)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        self.refreshResult = nil
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.buttonDismiss)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.Arke.green.opacity(0.05))
                        .stroke(Color.Arke.green.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Exit Error
            if let exitError = exitError {
                ErrorBox(
                    errorMessage: exitError,
                    onRetry: {
                        Task {
                            await handleExit()
                        }
                    },
                    onDismiss: {
                        self.exitError = nil
                    }
                )
            }
            
            // Exit Result
            if let exitResult = exitResult {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.Arke.green)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "status_exit_successful", defaultValue: "Exit Successful"))
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(exitResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(L10n.balanceVtxoRefreshNote)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        self.exitResult = nil
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.buttonDismiss)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.Arke.green.opacity(0.05))
                        .stroke(Color.Arke.green.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Offboard Error
            if let offboardError = offboardError {
                ErrorBox(
                    errorMessage: offboardError,
                    onRetry: {
                        Task {
                            await handleOffboard()
                        }
                    },
                    onDismiss: {
                        self.offboardError = nil
                    }
                )
            }
            
            // Offboard Result
            if let offboardResult = offboardResult {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.Arke.green)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "status_offboard_successful", defaultValue: "Offboard Successful"))
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(offboardResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(L10n.balanceVtxoRefreshNote)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        self.offboardResult = nil
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.buttonDismiss)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.Arke.green.opacity(0.05))
                        .stroke(Color.Arke.green.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .task {
            await loadFeeEstimate()
        }
    }
    
    // MARK: - Fee Estimation
    
    private func loadFeeEstimate() async {
        do {
            refreshFeeEstimate = try await walletManager.estimateRefreshFee(vtxoIds: [vtxo.id])
            print("Refresh fee estimate for VTXO \(vtxo.id): \(refreshFeeEstimate?.feeSats ?? 0) sats")
        } catch {
            print("Failed to estimate refresh fee: \(error.localizedDescription)")
            refreshFeeEstimate = nil
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleRefresh() async {
        isRefreshing = true
        // Clear previous results
        refreshResult = nil
        refreshError = nil
        
        defer { isRefreshing = false }
        
        do {
            let result = try await walletManager.refreshVtxoDelegated(vtxo_id: vtxo.id)
            print("✅ Successfully refreshed VTXO: \(vtxo.id)")
            print("   Result: \(result)")
            refreshResult = "\(result)"
            
            // Trigger parent refresh
            await onActionComplete?()
        } catch {
            print("❌ Failed to refresh VTXO: \(error)")
            refreshError = "Failed to refresh VTXO: \(error.localizedDescription)"
        }
    }
    
    private func handleExit() async {
        isExiting = true
        // Clear previous results
        exitResult = nil
        exitError = nil
        
        defer { isExiting = false }
        
        do {
            //let result = try await walletManager.exitVTXO(vtxoId: vtxo.id, to: walletManager.onchainAddress)
            let result = try await walletManager.startExitForVTXOs(vtxo_ids: [vtxo.id])
            print("✅ Successfully exited VTXO: \(vtxo.id)")
            print("   Result: \(result)")
            exitResult = "\(result)"
            
            // Trigger parent refresh
            await onActionComplete?()
        } catch {
            print("❌ Failed to exit VTXO: \(error)")
            exitError = "Failed to exit VTXO: \(error.localizedDescription)"
        }
    }
    
    private func handleOffboard() async {
        isOffboarding = true
        // Clear previous results
        offboardResult = nil
        offboardError = nil
        
        defer { isOffboarding = false }
        
        do {
            let result = try await walletManager.exitVTXO(vtxoId: vtxo.id, to: walletManager.onchainAddress)
            print("✅ Successfully offboarded VTXO: \(vtxo.id)")
            print("   Result: \(result)")
            offboardResult = "\(result)"
            
            // Trigger parent refresh
            await onActionComplete?()
        } catch {
            print("❌ Failed to offboard VTXO: \(error)")
            offboardError = "Failed to offboard VTXO: \(error.localizedDescription)"
        }
    }
}
