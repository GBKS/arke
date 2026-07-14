//
//  ExitLinkedOnchainCard.swift
//  Arke
//
//  Created by Christoph on 4/28/26.
//

import SwiftUI
import SwiftData
import Bark
import ArkeUI

/// Card displaying a single linked onchain transaction
struct TransactionExitLinkedOnchainCard: View {
    let transaction: TransactionModel
    
    @Environment(WalletManager.self) private var walletManager
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Transaction ID
            HStack(spacing: 6) {
                Text("activity_transaction_id")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(transaction.txid.prefix(16) + "..." + transaction.txid.suffix(8))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                
                /*
                Button {
                    copyToClipboard(transaction.txid)
                } label: {
                    Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(showCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                */
            }
            
            // Confirmation status
            HStack(spacing: 6) {
                Text("activity_confirmations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                
                if let confirmations = transaction.liveConfirmations {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(confirmations >= 6 ? Color.Arke.green : Color.Arke.orange)
                        
                        Text("\(confirmations)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if transaction.confirmationHeight != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(Color.Arke.green)
                        Text("status_confirmed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundColor(Color.Arke.orange)
                        Text("activity_unconfirmed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Amount (if applicable)
            if transaction.amount != 0 {
                HStack {
                    Text("label_amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(BitcoinFormatter.shared.formatAmount(transaction.amount))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
            
            // Onchain fee
            if let onchainFee = transaction.onchainFeeSat, onchainFee > 0 {
                HStack {
                    Text("activity_network_fee")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(BitcoinFormatter.shared.formatAmount(Int(onchainFee)))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var confirmationBadge: some View {
        if let confirmations = transaction.liveConfirmations {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(confirmations >= 6 ? Color.Arke.green : Color.Arke.orange)
                Text(confirmations >= 6 ? LocalizedStringKey("status_confirmed") : LocalizedStringKey("activity_confirming"))
                    .font(.caption)
                    .foregroundColor(confirmations >= 6 ? Color.Arke.green : Color.Arke.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((confirmations >= 6 ? Color.Arke.green : Color.Arke.orange).opacity(0.1))
            .cornerRadius(12)
        } else if transaction.confirmationHeight != nil {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Color.Arke.green)
                Text("status_confirmed")
                    .font(.caption)
                    .foregroundColor(Color.Arke.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.Arke.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
