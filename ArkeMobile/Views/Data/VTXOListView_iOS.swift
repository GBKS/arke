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
    
    private var totalVTXOAmount: Int {
        vtxos.reduce(into: 0) { $0 += $1.amountSat }
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
                
                if !vtxos.isEmpty && totalVTXOAmount >= minimumRefreshAmountSats {
                    Button {
                        Task {
                            await refreshVTXOs()
                        }
                    } label: {
                        if let feeEstimate = refreshFeeEstimate {
                            if feeEstimate.feeSats == 0 {
                                let freeText = String(localized: "Free")
                                Text("action_get_new_ones_with_fee \(freeText)")
                            } else {
                                let formattedFee = BitcoinFormatter.shared.formatAmount(Int(feeEstimate.feeSats))
                                Text("action_get_new_ones_with_fee \(formattedFee)")
                            }
                        } else {
                            Text("action_get_new_ones")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingVTXOs)
                }
            }
            .padding(.horizontal, 30)
            
            Divider()
                .padding(.top, 12)
                .padding(.leading, 30)
                .padding(.trailing, 30)
            
            if isLoadingVTXOs {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
                .padding(.horizontal, 30)
            } else if let error = error {
                ErrorBox(errorMessage: error)
                    .padding(.horizontal, 30)
            } else if vtxos.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("balance_no_vtxos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 30)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vtxos.enumerated()), id: \.element.id) { index, vtxo in
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
                        
                        if index < vtxos.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal, 18)
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
            
            print("vtxos: \(vtxos)")
            print("latestBlockHeight: \(latestBlockHeight ?? -1)")
            
            // Calculate refresh fee estimate for ALL VTXOs (developer option)
            if !vtxos.isEmpty {
                let vtxoIds = vtxos.map { $0.id }
                refreshFeeEstimate = try await walletManager.estimateRefreshFee(vtxoIds: vtxoIds)
                print("Refresh fee estimate: \(refreshFeeEstimate?.feeSats ?? 0) sats for ALL \(vtxos.count) VTXO(s)")
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
        
        print("refreshVTXOs - Force refreshing ALL VTXOs (developer option)...")
        
        do {
            // Step 1: Get ALL VTXOs (not just those needing refresh)
            let allVtxos = vtxos
            
            if allVtxos.isEmpty {
                print("refreshVTXOs - No VTXOs to refresh")
                isLoadingVTXOs = false
                await loadVTXOs()
                return
            }
            
            print("refreshVTXOs - Force refreshing \(allVtxos.count) VTXO(s)")
            
            // Step 2: Get VTXO IDs from all VTXOs
            let vtxoIds = allVtxos.map { $0.id }
            
            // Step 3: Estimate refresh fee using the wallet's built-in method
            let feeEstimate = try await walletManager.estimateRefreshFee(vtxoIds: vtxoIds)
            
            print("refreshVTXOs - Fee estimate:")
            print("  VTXOs to refresh: \(allVtxos.count)")
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
