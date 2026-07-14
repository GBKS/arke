//
//  TransactionExitDetailsView.swift
//  Arké
//
//  Created by Assistant on 2/5/26.
//

import SwiftUI
import SwiftData
import Bark
import ArkeUI

/// Expandable exit details section for unilateral exit transactions.
/// Shows information about VTXOs currently in the exit process and linked onchain transactions.
struct TransactionExitDetailsView: View {
    let transaction: TransactionModel
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = false
    @State private var exitVtxos: [ExitVtxo] = []
    @State private var linkedTransactions: [TransactionModel] = []
    
    var body: some View {
        // Only show for unilateral exit transactions
        guard transaction.subsystemName == "bark.exit" else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(spacing: 0) {
                // Header button
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("balance_exit_details")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                
                // Expanded content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if exitVtxos.isEmpty {
                            // No matching exit data found
                            VStack(alignment: .leading, spacing: 8) {
                                Text("balance_no_exit_data")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Text(String(localized: "balance_vtxos_claimed"))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // Summary
                            ExitSummaryRow(exitVtxos: exitVtxos)
                            
                            Divider()
                            
                            // Individual VTXO details
                            ForEach(Array(exitVtxos.enumerated()), id: \.element.vtxoId) { index, exitVtxo in
                                if index > 0 {
                                    Divider()
                                }
                                
                                ExitVtxoDetailRow(exitVtxo: exitVtxo)
                            }
                        }
                        
                        // Linked onchain transactions section
                        if !linkedTransactions.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("activity_onchain_transactions")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                VStack {
                                    // Linked transaction cards
                                    ForEach(Array(linkedTransactions.enumerated()), id: \.element.id) { index, linkedTx in
                                        if index > 0 {
                                            Divider()
                                        }
                                        
                                        TransactionExitLinkedOnchainCard(transaction: linkedTx)
                                    }
                                }
                                .padding(.leading)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 30)
            .onAppear {
                loadExitData()
                loadLinkedTransactions()
            }
        )
    }
    
    private func loadExitData() {
        // Match transaction inputVtxoIds with active unilateral exits
        let inputIds = Set(transaction.inputVtxoIds)
        exitVtxos = walletManager.activeUnilateralExits.filter { exit in
            inputIds.contains(exit.vtxoId)
        }
        
        print("📊 [Exit Details] Found \(exitVtxos.count) active exits for transaction \(transaction.txid)")
        for exit in exitVtxos {
            print("   - VTXO: \(exit.vtxoId), Amount: \(exit.amountSats) sats, State: \(exit.state), Claimable: \(exit.isClaimable)")
        }
    }
    
    private func loadLinkedTransactions() {
        guard let childTxids = transaction.childTxids else { return }
        
        var loaded: [TransactionModel] = []
        for txid in childTxids {
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == txid }
            )
            if let persistentTx = try? modelContext.fetch(descriptor).first {
                loaded.append(TransactionModel(from: persistentTx))
            }
        }
        linkedTransactions = loaded.sorted { $0.date < $1.date }
        
        print("🔗 [Exit Details] Found \(linkedTransactions.count) linked onchain transactions")
    }
}

// MARK: - Supporting Views

private struct ExitSummaryRow: View {
    let exitVtxos: [ExitVtxo]
    
    private var totalAmount: UInt64 {
        exitVtxos.reduce(0) { $0 + $1.amountSats }
    }
    
    private var formattedTotal: String {
        BitcoinFormatter.shared.formatAmount(Int(totalAmount))
    }
    
    private var allClaimable: Bool {
        !exitVtxos.isEmpty && exitVtxos.allSatisfy { $0.isClaimable }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("balance_vtxos_exiting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(exitVtxos.count)")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("label_total_amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedTotal)
                        .font(.body)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                if allClaimable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.Arke.green)
                        Text("balance_all_claimable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Arke.green)
                    }
                }
            }
        }
    }
}

private struct ExitVtxoDetailRow: View {
    let exitVtxo: ExitVtxo
    
    private var formattedAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(exitVtxo.amountSats))
    }
    
    private var stateColor: Color {
        exitVtxo.isClaimable ? .Arke.green : .Arke.orange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // VTXO ID
            VStack(alignment: .leading, spacing: 4) {
                Text("label_vtxo_id")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(exitVtxo.vtxoId)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            // Amount
            VStack(alignment: .leading, spacing: 4) {
                Text("label_amount")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formattedAmount)
                    .font(.body)
            }
            
            // State
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("label_state")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 6, height: 6)
                        Text(exitVtxo.state)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                Spacer()
                
                if exitVtxo.isClaimable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.Arke.green)
                        .font(.title3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
