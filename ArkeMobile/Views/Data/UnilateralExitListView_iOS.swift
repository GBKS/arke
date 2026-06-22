//
//  UnilateralExitListView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI
import ArkeUI
import Bark

struct UnilateralExitListView_iOS: View {
    var reloadTrigger: Int = 0
    var onSelectItem: ((ExitVtxo) -> Void)? = nil
    @Environment(WalletManager.self) private var walletManager
    @State private var exits: [ExitVtxo] = []
    @State private var isLoadingExits = false
    @State private var error: String?
    @State private var latestBlockHeight: Int?
    @State private var updateTimer: Timer?
    
    // State
    @State private var isProcessing = false
    @State private var claimableHeight: UInt32?
    @State private var hasPendingExits: Bool?
    @State private var pendingExitsTotal: UInt64?
    @State private var progressResults: [ExitProgressStatus] = []
    
    private var totalExitAmount: UInt64 {
        exits.reduce(into: 0) { $0 += $1.amountSats }
    }
    
    private var formattedTotalAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(totalExitAmount))
    }
    
    private var activeExits: [ExitVtxo] {
        // All exits from getExitVtxos are considered "active" (in progress)
        exits
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("balance_exiting_vtxos")
                        .font(.system(size: 24, design: .serif))
                    
                    if !exits.isEmpty {
                        Text("\(activeExits.count) exit\(activeExits.count == 1 ? "" : "s") • \(formattedTotalAmount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
                .padding(.horizontal)
            
            // Status Indicators Section
            if claimableHeight != nil || pendingExitsTotal != nil || !progressResults.isEmpty {
                statusIndicatorsSection
            }
            
            // Exit List
            if isLoadingExits {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
                .padding(.horizontal)
            } else if let error = error {
                ErrorBox(errorMessage: error)
                    .padding(.horizontal)
            } else if exits.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("balance_no_exits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(exits.enumerated()), id: \.element.vtxoId) { index, exit in
                        Button {
                            onSelectItem?(exit)
                        } label: {
                            ExitVtxoRowView_iOS(
                                exit: exit,
                                isSelected: false,
                                latestBlockHeight: latestBlockHeight
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if index < exits.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: reloadTrigger) {
            await loadExits()
            await syncAndProgressExits()
        }
        .onAppear {
            startBlockHeightUpdater()
        }
        .onDisappear {
            stopBlockHeightUpdater()
        }
    }
    
    // MARK: - Status Indicators Section
    
    @ViewBuilder
    private var statusIndicatorsSection: some View {
        // Only show section if there's actual content to display
        if claimableHeight != nil || !progressResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let height = claimableHeight {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(Color.Arke.green)
                        Text(String(localized: "balance_claimable_at_block", defaultValue: "All claimable at block \(height)"))
                        if let current = latestBlockHeight {
                            let remaining = Int(height) - current
                            Text("(\(remaining) block\(remaining == 1 ? "" : "s"))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                
                if !progressResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("data_last_progress")
                            .font(.body)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(progressResults.enumerated()), id: \.offset) { _, result in
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: result.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(result.error == nil ? Color.Arke.green : Color.Arke.red)
                                    Text("\(result.vtxoId.prefix(8))... → \(result.state)")
                                        .font(.system(.body, design: .monospaced))
                                }
                                if let error = result.error {
                                    Text("(\(error))")
                                        .font(.body)
                                        .foregroundStyle(Color.Arke.red)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 15)
                    .background(Color(.systemGray5))
                    .cornerRadius(15)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Action Methods
    
    private func syncAndProgressExits() async {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔄 Syncing and progressing all exits...")
        
        do {
            // First, sync with server
            try await walletManager.syncExits()
            print("✅ Exit state fetched from server")
            
            // Then progress all exits
            let statuses = try await walletManager.progressExits(feeRateSatPerVb: nil)
            progressResults = statuses
            
            print("✅ Progressed \(statuses.count) exit(s)")
            for status in statuses {
                print("  - VTXO \(status.vtxoId): \(status.state)")
                if let error = status.error {
                    print("    ❌ Error: \(error)")
                }
            }
            
            // Load debug info
            await loadDebugInfo()
            
            // Refresh UI
            await loadExits()
        } catch {
            self.error = "Failed to sync and progress exits: \(error.localizedDescription)"
            print("❌ Failed to sync and progress exits: \(error)")
        }
    }
    
    private func loadDebugInfo() async {
        print("🔍 Loading debug info...")
        
        do {
            // Load all debug info
            claimableHeight = try await walletManager.allExitsClaimableAtHeight()
            hasPendingExits = try await walletManager.hasPendingExits()
            pendingExitsTotal = try await walletManager.pendingExitsTotalSats()
            
            print("✅ Debug info loaded:")
            print("   Claimable height: \(claimableHeight ?? 0)")
            print("   Has pending: \(hasPendingExits ?? false)")
            print("   Pending total: \(pendingExitsTotal ?? 0) sats")
        } catch {
            print("❌ Failed to load debug info: \(error)")
            // Don't set error state here, as this is supplementary info
        }
    }
    
    private func startBlockHeightUpdater() {
        // Update estimated block height every 30 seconds for real-time status updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            }
        }
    }
    
    private func stopBlockHeightUpdater() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func loadExits() async {
        isLoadingExits = true
        error = nil
        
        print("loadUnilateralExits")
        
        do {
            // Get all VTXOs currently in exit process
            exits = try await walletManager.getExitVtxos()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            
            print("exits: \(exits)")
            print("latestBlockHeight: \(latestBlockHeight ?? -1)")
            
            // Load debug info
            await loadDebugInfo()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingExits = false
    }
}

// MARK: - Previews

#Preview("Exit List") {
    NavigationStack {
        UnilateralExitListView_iOS()
            .environment(WalletManager(useMock: true))
            .padding()
    }
    .frame(width: 400, height: 600)
}
