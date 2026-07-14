//
//  VTXOListView_iOS.swift
//  Arké
//
//  Created by Christoph on 12/17/25.
//

import SwiftUI
import Foundation
import ArkeUI
import Bark

struct VTXOListView_iOS: View {
    var reloadTrigger: Int = 0
    var onSelectItem: ((VTXOModel) -> Void)? = nil
    var onRefreshComplete: (() async -> Void)? = nil
    var minimumRefreshAmountSats: UInt64 = 330
    @Environment(WalletManager.self) private var walletManager
    @State private var vtxos: [VTXOModel] = []
    @State private var isLoadingVTXOs = false
    @State private var error: String?
    @State private var latestBlockHeight: Int?
    @State private var updateTimer: Timer?
    @State private var refreshFeeEstimate: FeeEstimate?
    @State private var arkInfo: ArkInfoModel?
    
    private var spendableVTXOs: [VTXOModel] {
        vtxos.filter { $0.state != .locked && $0.state != .spent && $0.state != .exited }
    }

    /// The complement of what VTXOGraph displays: spent and exited VTXOs.
    private var inactiveVTXOs: [VTXOModel] {
        vtxos.filter { $0.isSpent || $0.state == .exited }
    }
    
    private var totalVTXOAmount: Int {
        vtxos.reduce(into: 0) { $0 += $1.amountSat }
    }
    
    private var totalSpendableVTXOAmount: Int {
        spendableVTXOs.reduce(into: 0) { $0 += $1.amountSat }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("label_vtxos")
                        .font(.system(size: 24, design: .serif))
                    
                    if !vtxos.isEmpty {
                        Text("\(vtxos.count) VTXOs • \(totalVTXOAmount.formatted()) ₿")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if !spendableVTXOs.isEmpty && totalSpendableVTXOAmount >= minimumRefreshAmountSats {
                    Button {
                        Task {
                            await refreshVTXOs()
                        }
                    } label: {
                        if let feeEstimate = refreshFeeEstimate {
                            if feeEstimate.feeSats == 0 {
                                let freeText = String(localized: "fee_free")
                                Text("action_get_new_ones_with_fee \(freeText)")
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.Arke.goldLabel)
                            } else {
                                let formattedFee = BitcoinFormatter.shared.formatAmount(Int(feeEstimate.feeSats))
                                Text("action_get_new_ones_with_fee \(formattedFee)")
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.Arke.goldLabel)
                            }
                        } else {
                            Text("action_get_new_ones")
                                .fontWeight(.medium)
                                .foregroundStyle(Color.Arke.goldLabel)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingVTXOs)
                }
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
                .padding(.horizontal)
            
            if isLoadingVTXOs {
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
            } else if vtxos.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("balance_no_vtxos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                if let latestBlockHeight {
                    VTXOGraph(
                        vtxos: vtxos,
                        currentBlockHeight: latestBlockHeight,
                        horizonBlocks: arkInfo?.vtxoExpiryDelta,
                        freeRefreshBlocks: arkInfo?.feeSchedule?.refresh.freeRefreshBlocks,
                        maxExitDepth: (arkInfo?.maxVtxoExitDepth).map(Int.init),
                        onSelect: { vtxo in
                            onSelectItem?(vtxo)
                        }
                    )
                    .padding(.top, 16)
                    .padding(.horizontal)
                }

                // The graph above covers active VTXOs; the list shows the
                // spent and exited ones the graph filters out.
                if !inactiveVTXOs.isEmpty {
                    Text("label_vtxos_inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                        .padding(.horizontal)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(inactiveVTXOs.enumerated()), id: \.element.id) { index, vtxo in
                            Button {
                                onSelectItem?(vtxo)
                            } label: {
                                VTXORowView(
                                    vtxo: vtxo,
                                    isSelected: false,
                                    latestBlockHeight: latestBlockHeight
                                )
                            }
                            .buttonStyle(.plain)

                            if index < inactiveVTXOs.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .task(id: reloadTrigger) {
            await loadVTXOs()
        }
        .onAppear {
            startBlockHeightUpdater()
        }
        .onDisappear {
            stopBlockHeightUpdater()
        }
    }
    
    private func startBlockHeightUpdater() {
        // Update estimated block height every 30 seconds for real-time expiry updates
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
    
    private func loadVTXOs() async {
        isLoadingVTXOs = true
        error = nil
        
        print("loadVTXOs")
        
        do {
            // Fetch VTXOs and get estimated block height for real-time updates
            vtxos = try await walletManager.getVTXOs()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()

            // The ark info drives VTXOGraph's horizon, free refresh zone,
            // and hop coloring; keep the previous value (or the graph's
            // defaults) if unavailable.
            if let arkInfo = try? await walletManager.getArkInfo() {
                self.arkInfo = arkInfo
            }
            
            print("vtxos: \(vtxos)")
            print("latestBlockHeight: \(latestBlockHeight ?? -1)")
            
            // Calculate refresh fee estimate for spendable VTXOs only (developer option)
            if !vtxos.isEmpty {
                let spendableIds = spendableVTXOs.map { $0.id }
                if !spendableIds.isEmpty {
                    refreshFeeEstimate = try await walletManager.estimateRefreshFee(vtxoIds: spendableIds)
                    print("Refresh fee estimate: \(refreshFeeEstimate?.feeSats ?? 0) sats for \(spendableIds.count) spendable VTXO(s)")
                } else {
                    refreshFeeEstimate = nil
                    print("No spendable VTXOs to refresh")
                }
            } else {
                refreshFeeEstimate = nil
                print("No VTXOs to refresh")
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingVTXOs = false
    }
    
    private func refreshVTXOs() async {
        isLoadingVTXOs = true
        error = nil
        
        print("refreshVTXOs - Force refreshing spendable VTXOs (developer option)...")
        
        do {
            // Step 1: Get spendable VTXOs only (exclude locked and spent)
            let vtxosToRefresh = spendableVTXOs
            
            if vtxosToRefresh.isEmpty {
                print("refreshVTXOs - No spendable VTXOs to refresh")
                isLoadingVTXOs = false
                await loadVTXOs()
                return
            }
            
            print("refreshVTXOs - Force refreshing \(vtxosToRefresh.count) spendable VTXO(s)")
            
            // Step 2: Get VTXO IDs from spendable VTXOs
            let vtxoIds = vtxosToRefresh.map { $0.id }
            
            // Step 3: Estimate refresh fee using the wallet's built-in method
            let feeEstimate = try await walletManager.estimateRefreshFee(vtxoIds: vtxoIds)
            
            print("refreshVTXOs - Fee estimate:")
            print("  VTXOs to refresh: \(vtxosToRefresh.count)")
            print("  Gross amount: \(feeEstimate.grossAmountSats) sats")
            print("  Refresh fee: \(feeEstimate.feeSats) sats")
            print("  Net amount: \(feeEstimate.netAmountSats) sats")
            print("  VTXOs spent: \(feeEstimate.vtxosSpent.count)")
            
            let isFree = feeEstimate.feeSats == 0
            if isFree {
                print("  → Refresh is FREE!")
            }
            
            // Step 4: Perform delegated refresh
            print("refreshVTXOs - Scheduling delegated refresh for \(vtxoIds.count) VTXO(s)...")
            
            let roundState = try await walletManager.refreshVtxosDelegated(vtxoIds: vtxoIds)
            
            if let roundState = roundState {
                print("refreshVTXOs - Delegated refresh scheduled successfully, Round ID: \(roundState.id)")
            } else {
                print("refreshVTXOs - No refresh scheduled (VTXOs may not need refresh yet)")
            }
            
            // Step 5: Trigger full reload in parent view
            await onRefreshComplete?()
        } catch {
            print("refreshVTXOs - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoadingVTXOs = false
        }
    }
}
