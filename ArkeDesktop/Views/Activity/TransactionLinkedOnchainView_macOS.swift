//
//  TransactionLinkedOnchainView_macOS.swift
//  Arké
//
//  Created by Assistant on 4/27/26.
//

import SwiftUI
import SwiftData
import ArkeUI

/// Displays linked onchain transaction information for movements (macOS version)
struct TransactionLinkedOnchainView_macOS: View {
    let transaction: TransactionModel
    
    @Environment(\.modelContext) private var modelContext
    @State private var linkedTransactions: [TransactionModel] = []
    @State private var isExpanded = true
    
    var body: some View {
        if transaction.hasLinkedOnchainTransactions {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 12) {
                    ForEach(linkedTransactions) { linkedTx in
                        LinkedOnchainCard_macOS(transaction: linkedTx)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "link")
                        .font(.headline)
                    Text(String(localized: "activity_onchain_transactions", defaultValue: "Onchain Transactions"))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .task {
                loadLinkedTransactions()
            }
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
        linkedTransactions = loaded
    }
}

/// Card displaying a single linked onchain transaction (macOS version)
struct LinkedOnchainCard_macOS: View {
    let transaction: TransactionModel
    
    @Environment(WalletManager.self) private var walletManager
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Transaction ID row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.activityTransactionId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text(transaction.txid.prefix(16) + "..." + transaction.txid.suffix(8))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Button {
                            copyToClipboard(transaction.txid)
                        } label: {
                            Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(showCopied ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                confirmationBadge
            }
            
            // Details grid
            VStack(spacing: 6) {
                // Confirmation status
                if let confirmations = transaction.liveConfirmations {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(confirmations >= 6 ? .green : .orange)
                            
                            if confirmations >= 6 {
                                Text("\(confirmations)+ confirmations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(confirmations) confirmation\(confirmations != 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                } else if let height = transaction.confirmationHeight {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Confirmed at block \(height)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(L10n.activityUnconfirmed)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                
                // Onchain fee
                if let onchainFee = transaction.onchainFeeSat, onchainFee > 0 {
                    HStack {
                        Text(L10n.activityNetworkFee)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(BitcoinFormatter.shared.formatAmount(Int(onchainFee)))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
                
                // Amount (if applicable)
                if transaction.amount != 0 {
                    HStack {
                        Text(L10n.labelAmount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(BitcoinFormatter.shared.formatAmount(transaction.amount))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var confirmationBadge: some View {
        if let confirmations = transaction.liveConfirmations {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(confirmations >= 6 ? .green : .orange)
                Text(confirmations >= 6 ? L10n.statusConfirmed : String(localized: "activity_confirming", defaultValue: "Confirming"))
                    .font(.caption2)
                    .foregroundColor(confirmations >= 6 ? .green : .orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((confirmations >= 6 ? Color.green : Color.orange).opacity(0.15))
            .cornerRadius(8)
        } else if transaction.confirmationHeight != nil {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text(L10n.statusConfirmed)
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .cornerRadius(8)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        
        withAnimation {
            showCopied = true
        }
        
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showCopied = false
            }
        }
    }
}
