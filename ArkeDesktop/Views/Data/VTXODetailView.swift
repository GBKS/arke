//
//  VTXODetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import ArkeUI

struct VTXODetailView: View {
    let vtxo: VTXOModel
    
    @Environment(WalletManager.self) private var walletManager
    @State private var currentVtxo: VTXOModel
    @State private var reloadTrigger = 0
    
    // Minimum amount of sats required for a refresh operation
    private let minimumRefreshAmountSats: UInt64 = 330
    
    init(vtxo: VTXOModel) {
        self.vtxo = vtxo
        self._currentVtxo = State(initialValue: vtxo)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: currentVtxo.state.iconName)
                            .font(.system(size: 50))
                            .foregroundColor(currentVtxo.state.iconColor)
                        
                        VStack(alignment: .leading) {
                            Text(currentVtxo.formattedAmount)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(currentVtxo.state.displayName)
                                .font(.subheadline)
                                .foregroundColor(currentVtxo.state.iconColor)
                        }
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Developer Actions Section
                VTXODeveloperActionsView(
                    vtxo: currentVtxo,
                    minimumRefreshAmountSats: minimumRefreshAmountSats
                ) {
                    await refreshVTXO()
                }
                
                // Show message if refresh is disabled due to amount being too small
                if currentVtxo.amountSat <= minimumRefreshAmountSats {
                    Text("Refresh is disabled because the amount (\(currentVtxo.formattedAmount)) is smaller than the minimum required (\(BitcoinFormatter.shared.formatAmount(Int(minimumRefreshAmountSats)))).")
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Details Section
                VStack(alignment: .leading, spacing: 16) {
                    /*
                    Text("balance_vtxo_details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    */
                    
                    VStack(spacing: 12) {
                        // Outpoint (ID)
                        DetailRow(
                            title: "Outpoint",
                            value: currentVtxo.outpoint,
                            isCopyable: true
                        )
                        
                        // Transaction ID
                        DetailRow(
                            title: "Transaction ID",
                            value: currentVtxo.txid,
                            isCopyable: true
                        )
                        
                        // Output Index
                        DetailRow(
                            title: "Output Index",
                            value: String(currentVtxo.vout)
                        )
                        
                        // VTXO Kind
                        DetailRow(
                            title: "VTXO Kind",
                            value: currentVtxo.kind.displayName
                        )
                        
                        // State
                        DetailRow(
                            title: "State",
                            value: currentVtxo.state.displayName
                        )
                        
                        // Expiry Height
                        if currentVtxo.expiryHeight > 0 {
                            DetailRow(
                                title: "Expiry Height",
                                value: currentVtxo.expiryHeight.formatted()
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("balance_vtxo_details")
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .task(id: reloadTrigger) {
            await loadVTXO()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadVTXO() async {
        do {
            let vtxos = try await walletManager.getVTXOs()
            if let updatedVtxo = vtxos.first(where: { $0.id == vtxo.id }) {
                currentVtxo = updatedVtxo
                print("✅ Refreshed VTXO data: \(updatedVtxo.id)")
            } else {
                print("⚠️ VTXO no longer exists: \(vtxo.id)")
            }
        } catch {
            print("❌ Failed to load VTXO: \(error)")
        }
    }
    
    private func refreshVTXO() async {
        reloadTrigger += 1
    }
}
