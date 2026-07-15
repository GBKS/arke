//
//  ExitOnchainInfoRows.swift
//  Arké
//
//  Created by Christoph on 4/28/26.
//

import SwiftUI
import ArkeUI

/// Onchain wallet details for one exit transaction — confirmations, amount
/// and network fee — shown inside an expanded step of the exit timeline when
/// the transaction is known to the onchain wallet. Trimmed from the former
/// TransactionExitLinkedOnchainCard; the txid is shown by the step row itself.
struct ExitOnchainInfoRows: View {
    let transaction: TransactionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Confirmation status
            HStack {
                Text("activity_confirmations")
                    .foregroundStyle(.secondary)
                Spacer()

                if let confirmations = transaction.liveConfirmations {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(confirmations >= 6 ? Color.Arke.green : Color.Arke.orange)
                        Text("\(confirmations)")
                    }
                } else if transaction.confirmationHeight != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.Arke.green)
                        Text("status_confirmed")
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundStyle(Color.Arke.orange)
                        Text("activity_unconfirmed")
                    }
                }
            }

            // When the wallet recorded it (BDK confirmation time once confirmed)
            HStack {
                Text("label_date")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(transaction.formattedDate)
            }

            // Amount (if applicable)
            if transaction.amount != 0 {
                HStack {
                    Text("label_amount")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(BitcoinFormatter.shared.formatAmount(transaction.amount))
                }
            }

            // Onchain fee
            if let onchainFee = transaction.onchainFeeSat, onchainFee > 0 {
                HStack {
                    Text("activity_network_fee")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(BitcoinFormatter.shared.formatAmount(Int(onchainFee)))
                }
            }
        }
        .font(.subheadline)
    }
}
