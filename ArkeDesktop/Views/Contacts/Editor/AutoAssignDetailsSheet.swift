//
//  AutoAssignDetailsSheet.swift
//  Arké
//
//  Created by Christoph on 11/11/25.
//

import SwiftUI
import ArkeUI

struct AutoAssignDetailsSheet: View {
    let contactName: String
    let assignedCount: Int
    let transactionId: String
    let walletManager: WalletManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var autoAssignedTransactions: [TransactionModel] = []
    @State private var isLoading = true
    @State private var transactionAddress: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "contacts_autoassigned_transactions", defaultValue: "Auto-Assigned Transactions"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let address = transactionAddress {
                        Text("Address: \(shortAddress(address))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(L10n.buttonDone) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if autoAssignedTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.Arke.green)
                    Text("Contact '\(contactName)' assigned")
                        .font(.headline)
                    Text(String(localized: "contacts_no_other_transactions", defaultValue: "No other transactions with this address"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Also assigned '\(contactName)' to these \(autoAssignedTransactions.count) transactions:")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(autoAssignedTransactions, id: \.txid) { transaction in
                                AutoAssignSummaryRow(transaction: transaction)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .task {
            await loadAutoAssignedTransactions()
        }
    }
    
    private func loadAutoAssignedTransactions() async {
        isLoading = true
        
        // Get the original transaction to find its address
        let allTransactions = walletManager.transactions
        if let originalTransaction = allTransactions.first(where: { $0.txid == transactionId }),
           let address = originalTransaction.address {
            transactionAddress = address
            
            // Find all transactions with the same address (excluding the original)
            let normalizedAddress = address.lowercased()
            autoAssignedTransactions = allTransactions.filter { tx in
                guard let txAddress = tx.address else { return false }
                return txAddress.lowercased() == normalizedAddress && tx.txid != transactionId
            }
            .sorted { $0.date > $1.date } // Most recent first
        }
        
        isLoading = false
    }
    
    private func shortAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }
}
