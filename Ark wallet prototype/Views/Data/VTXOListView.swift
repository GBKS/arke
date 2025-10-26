//
//  VTXOListView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import Foundation

struct VTXOListView: View {
    @Binding var selectedDataItem: DataDetailItem?
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VTXOs")
                        .font(.system(size: 24, design: .serif))
                    
                    if !vtxos.isEmpty {
                        Text("\(vtxos.count) VTXOs • \(totalVTXOAmount.formatted()) ₿")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadVTXOs()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingVTXOs)
                
                Button("Get new ones") {
                    Task {
                        await refreshVTXOs()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingVTXOs)
            }
            
            Divider()
                .padding(.top, 12)
            
            if isLoadingVTXOs {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
            } else if let error = error {
                ErrorView(errorMessage: error)
            } else if vtxos.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("No VTXOs found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vtxos.enumerated()), id: \.element.id) { index, vtxo in
                        VStack(spacing: 0) {
                            Button {
                                selectedDataItem = .vtxo(vtxo)
                            } label: {
                                VTXORowView(vtxo: vtxo, showDivider: index < vtxos.count - 1, latestBlockHeight: latestBlockHeight)
                            }
                            .buttonStyle(.plain)
                            .background(selectedDataItem == .vtxo(vtxo) ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                    }
                }
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
            _ = try await walletManager.refreshVTXOs()
            
            // After refreshing, reload the VTXOs to update the UI
            await loadVTXOs()
        } catch {
            self.error = error.localizedDescription
            isLoadingVTXOs = false
        }
    }
}

#Preview {
    NavigationStack {
        VTXOListView(selectedDataItem: .constant(nil))
            .environment(WalletManager(useMock: true))
            .padding()
    }
    .frame(width: 400, height: 600)
}
