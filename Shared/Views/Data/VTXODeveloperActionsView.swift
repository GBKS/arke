//
//  VTXODeveloperActionsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/14/25.
//

import SwiftUI
import ArkeUI

struct VTXODeveloperActionsView: View {
    let vtxo: VTXOModel
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                // Refresh Button
                Button {
                    Task {
                        await handleRefresh()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("button_refresh")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || isExiting || isOffboarding)
                
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
                        }
                        Text("button_exit")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || isExiting || isOffboarding)
                
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
                        }
                        Text("button_offboard")
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
                        Text("status_refresh_successful")
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(refreshResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(String(localized: "balance_vtxo_refresh_note"))
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
                    .help("button_dismiss")
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
                        Text("status_exit_successful")
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(exitResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(String(localized: "balance_vtxo_refresh_note"))
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
                    .help("button_dismiss")
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
                        Text("status_offboard_successful")
                            .font(.headline)
                            .foregroundColor(.Arke.green)
                        
                        Text(offboardResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Text(String(localized: "balance_vtxo_refresh_note"))
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
                    .help("button_dismiss")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.Arke.green.opacity(0.05))
                        .stroke(Color.Arke.green.opacity(0.3), lineWidth: 1)
                )
            }
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
            let result = try await walletManager.refreshVTXO(vtxo_id: vtxo.id)
            print("✅ Successfully refreshed VTXO: \(vtxo.id)")
            print("   Result: \(result)")
            refreshResult = "\(result)"
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
        } catch {
            print("❌ Failed to offboard VTXO: \(error)")
            offboardError = "Failed to offboard VTXO: \(error.localizedDescription)"
        }
    }
}
