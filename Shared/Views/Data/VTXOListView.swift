//
//  VTXOListView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import Foundation
import ArkeUI

struct VTXOListView: View {
    @Binding var selectedDataItem: DataDetailItem?
    var onSelectItem: ((DataDetailItem) -> Void)? = nil
    @Environment(WalletManager.self) private var walletManager
    @State private var vtxos: [VTXOModel] = []
    @State private var isLoadingVTXOs = false
    @State private var error: String?
    @State private var latestBlockHeight: Int?
    @State private var updateTimer: Timer?
    
    private var totalVTXOAmount: Int {
        vtxos.reduce(into: 0) { $0 += $1.amountSat }
    }

    /// VTXOs eligible for a refresh (exclude locked, already-spent, and exited ones)
    private var spendableVTXOs: [VTXOModel] {
        vtxos.filter { $0.state != .locked && $0.state != .spent && $0.state != .exited }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "label_vtxos", defaultValue: "VTXOs"))
                        .font(.system(size: 24, design: .serif))
                    
                    if !vtxos.isEmpty {
                        Text("\(vtxos.count) VTXOs • \(totalVTXOAmount.formatted()) ₿")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        await loadVTXOs()
                    }
                } label: {
                    if isLoadingVTXOs {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingVTXOs)
                
                Button(String(localized: "action_get_new_ones", defaultValue: "Refresh all")) {
                    Task {
                        await refreshVTXOs()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingVTXOs)
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
                VStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "balance_no_vtxos", defaultValue: "No VTXOs found"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vtxos.enumerated()), id: \.element.id) { index, vtxo in
                        Button {
                            let item = DataDetailItem.vtxo(vtxo)
                            selectedDataItem = item
                            onSelectItem?(item)
                        } label: {
                            VTXORowView(
                                vtxo: vtxo,
                                isSelected: selectedDataItem == .vtxo(vtxo),
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
                .padding(.horizontal)
            }
        }
        .task {
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
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingVTXOs = false
    }
    
    private func refreshVTXOs() async {
        isLoadingVTXOs = true
        error = nil

        print("refreshVTXOs")

        do {
            // Refresh spendable VTXOs (extends their expiry via a delegated round).
            let vtxosToRefresh = spendableVTXOs
            guard !vtxosToRefresh.isEmpty else {
                print("refreshVTXOs: no spendable VTXOs to refresh")
                await loadVTXOs()
                return
            }

            let vtxoIds = vtxosToRefresh.map { $0.id }
            print("refreshVTXOs: scheduling delegated refresh for \(vtxoIds.count) VTXO(s)...")

            let roundState = try await walletManager.refreshVtxosDelegated(vtxoIds: vtxoIds)
            if roundState != nil {
                print("refreshVTXOs: refresh round scheduled")
            } else {
                print("refreshVTXOs: no refresh scheduled (VTXOs may not need it yet)")
            }

            // Reload to reflect the new VTXO state.
            await loadVTXOs()
        } catch {
            self.error = error.localizedDescription
            isLoadingVTXOs = false
        }
    }
}
