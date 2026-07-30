//
//  TransactionTechnicalDetailsView.swift
//  Arké
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI
import UIKit
import ArkeUI

/// Expandable technical details section for transactions.
/// Useful during testing and development. Can be easily removed later.
struct TransactionTechnicalDetailsView: View {
    let transaction: TransactionModel

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Text("data_technical_details")
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
                TransactionTechnicalDetailRows(transaction: transaction)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 30)
    }
}

/// The technical record rows themselves, shared by the expandable section
/// above and the receipt sheet presented from the transaction swipe card.
struct TransactionTechnicalDetailRows: View {
    let transaction: TransactionModel

    @State private var showAbsoluteDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Payment Preimage (only show if present - Lightning receives)
            if let paymentPreimage = transaction.paymentPreimage {
                HStack(spacing: 12) {
                    AddressHallmark(address: paymentPreimage)
                        .frame(width: 40)
                        .padding(2)
                        .background(Color.systemBackground)
                        .cornerRadius(8)

                    TechnicalDetailRow(
                        label: "Proof of Payment (Preimage)",
                        value: paymentPreimage,
                        showCopyButton: false
                    )
                }

                Divider()
            }

            // Payment Hash (only show if present - Lightning transactions)
            if let paymentHash = transaction.paymentHash {
                TechnicalDetailRow(
                    label: "Payment Hash",
                    value: paymentHash,
                    showCopyButton: false
                )

                Divider()
            }

            // Category
            TechnicalDetailRow(
                label: "Category",
                value: transaction.category?.rawValue ?? "nil"
            )

            Divider()

            // Type
            TechnicalDetailRow(
                label: "Type",
                value: transaction.type.displayName
            )

            Divider()

            // Status
            TechnicalDetailRow(
                label: "Status",
                value: transaction.status.displayName
            )

            // Confirmation Count (only show if present - onchain transactions only)
            if let confirmations = transaction.confirmationCount {
                Divider()

                TechnicalDetailRow(
                    label: "Confirmations",
                    value: "\(confirmations)"
                )
            }

            // Subsystem Name (only show if present)
            if let subsystemName = transaction.subsystemName {
                Divider()

                TechnicalDetailRow(
                    label: "Subsystem Name",
                    value: subsystemName
                )
            }

            // Subsystem Kind (only show if present)
            if let subsystemKind = transaction.subsystemKind {
                Divider()

                TechnicalDetailRow(
                    label: "Subsystem Kind",
                    value: subsystemKind
                )
            }

            Divider()

            // Raw Amount
            TechnicalDetailRow(
                label: "Raw Amount (sats)",
                value: "\(transaction.amount)"
            )

            // Fees (only show if present)
            if let fees = transaction.fees {
                Divider()

                TechnicalDetailRow(
                    label: "Offchain Fee (sats)",
                    value: "\(fees)"
                )
            }

            // Onchain Fee (only show if present)
            if let onchainFee = transaction.onchainFeeSat {
                Divider()

                TechnicalDetailRow(
                    label: "Onchain Fee (sats)",
                    value: "\(onchainFee)"
                )
            }

            // Transaction ID (only show for onchain transactions)
            if let category = transaction.category, category.isOnchain {
                Divider()

                TechnicalDetailRow(
                    label: "Onchain Transaction ID",
                    value: {
                        // For pure onchain transactions, strip the "onchain_" prefix
                        if category == .onchainTransaction, transaction.txid.hasPrefix("onchain_") {
                            return String(transaction.txid.dropFirst("onchain_".count))
                        } else if let fundingTxid = transaction.fundingTxid {
                            // For Ark round transactions, use fundingTxid
                            return fundingTxid
                        } else {
                            return transaction.txid
                        }
                    }(),
                    showCopyButton: true
                )
            }

            // Address (only show if present)
            if let address = transaction.address {
                Divider()

                TechnicalDetailRow(
                    label: "Raw Address",
                    value: address
                )
            }

            // Input VTXO IDs (only show if present)
            if !transaction.inputVtxoIds.isEmpty {
                Divider()

                TechnicalDetailRow(
                    label: "Input VTXO IDs",
                    value: transaction.inputVtxoIds.joined(separator: "\n")
                )
            }

            // Output VTXO IDs (only show if present)
            if !transaction.outputVtxoIds.isEmpty {
                Divider()

                TechnicalDetailRow(
                    label: "Output VTXO IDs",
                    value: transaction.outputVtxoIds.joined(separator: "\n")
                )
            }

            // Exited VTXO IDs (only show if present)
            if !transaction.exitedVtxoIds.isEmpty {
                Divider()

                TechnicalDetailRow(
                    label: "Exited VTXO IDs",
                    value: transaction.exitedVtxoIds.joined(separator: "\n")
                )
            }

            // Child Transaction IDs (only show if present)
            if let childTxids = transaction.childTxids, !childTxids.isEmpty {
                Divider()

                TechnicalDetailRow(
                    label: "Child Transaction IDs",
                    value: childTxids.joined(separator: "\n")
                )
            }

            // Exit blocked error (only for exits currently blocked on fees/funding)
            if let blockedInfo = transaction.exitBlockedInfo {
                Divider()

                TechnicalDetailRow(
                    label: "Exit Blocked (\(blockedInfo.reason.rawValue), \(blockedInfo.attemptCount) attempts)",
                    value: blockedInfo.rawErrorMessage,
                    showCopyButton: true
                )
            }

            /*
            Divider()

            // Timestamp
            Button(action: {
                showAbsoluteDate.toggle()
            }) {
                TechnicalDetailRow(
                    label: "Timestamp",
                    value: showAbsoluteDate
                        ? ISO8601DateFormatter().string(from: transaction.date)
                        : transaction.formattedDate
                )
            }
            .buttonStyle(.plain)
            */
        }
    }
}

// MARK: - Supporting Views

private struct TechnicalDetailRow: View {
    let label: String
    let value: String
    var showCopyButton: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showCopyButton {
                Button(action: {
                    UIPasteboard.general.string = value
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
