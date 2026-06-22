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
                
                Button("action_get_new_ones") {
                    Task {
                        await refreshVTXOs()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingVTXOs)
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
                .padding(.horizontal, 18)
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
            // Call refreshVTXOs on the wallet manager to get new VTXOs
            let refreshResult = try await walletManager.maybeScheduleMaintenanceRefresh()
            
            print("refreshVTXOs: \(String(describing: refreshResult))")
            
            // After refreshing, reload the VTXOs to update the UI
            await loadVTXOs()
        } catch {
            self.error = error.localizedDescription
            isLoadingVTXOs = false
        }
    }
}
