//
//  TransactionDetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ArkeUI

struct TransactionDetailView: View {
    let transaction: TransactionModel
    let onNavigateToContact: ((ContactModel) -> Void)?
    
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: TransactionDetailViewModel?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = TransactionDetailViewModel(
                            transaction: transaction,
                            walletManager: walletManager
                        )
                    }
            }
        }
        .navigationTitle("nav_title_transaction")
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
    }
    
    @ViewBuilder
    private func contentView(viewModel: TransactionDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    // Transaction Icon and Type
                    HStack(spacing: 15) {
                        Image(systemName: transaction.transactionType.iconName)
                            .font(.system(size: 20))
                            .foregroundColor(transaction.transactionType.iconColor)
                            .frame(width: 40, height: 40)
                            .background(transaction.transactionType.iconColor.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading) {
                            Text(transaction.displayText(includeStatusPrefix: false))
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(transaction.formattedDate)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Amount
                    Text(transaction.formattedAmount)
                        .font(.largeTitle)
                        .fontWeight(.medium)
                        .foregroundColor(transaction.transactionType.amountColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Status Badge (only show if not confirmed)
                    if transaction.transactionStatus != .confirmed {
                        HStack {
                            Text(transaction.transactionStatus.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(transaction.transactionStatus.textColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(transaction.transactionStatus.backgroundColor)
                                .clipShape(Capsule())
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 15)
                
                Divider()
                    .padding(.leading, 15)
                    .padding(.trailing, 15)
                
                // Tags Section
                TransactionTagView(transaction: transaction, onNavigateToTag: { _ in
                    // TODO: Implement tag navigation
                })
                    .padding(.horizontal, 15)
                
                // Contacts Section
                TransactionContactView(
                    transaction: transaction,
                    onNavigateToContact: onNavigateToContact
                )
                    .padding(.horizontal, 15)
                
                // Notes Section
                TransactionNotesSection(transaction: transaction)
                    .padding(.horizontal, 5)
                
                Divider()
                    .padding(.leading, 15)
                    .padding(.trailing, 15)
                
                // Linked onchain transactions (for movements with onchain components)
                TransactionLinkedOnchainView_macOS(transaction: transaction)
                    .padding(.horizontal, 15)
                
                // Details Section
                DisclosureGroup {
                    VStack(spacing: 12) {
                        // Transaction ID
                        DetailRow(
                            title: "activity_transaction_id",
                            value: transaction.txid,
                            isCopyable: true,
                            onCopy: { viewModel.copyToClipboard($0) }
                        )
                        
                        // Address
                        if let address = transaction.address {
                            DetailRow(
                                title: transaction.transactionType == .received ? LocalizedStringKey("activity_from_address") : LocalizedStringKey("activity_to_address"),
                                value: address,
                                isCopyable: true,
                                onCopy: { viewModel.copyToClipboard($0) }
                            )
                        }
                        
                        // Fee (show for sent and transfer transactions)
                        if transaction.hasFees && (transaction.transactionType == .sent || transaction.transactionType == .transfer) {
                            // If both fee types exist, show them separately
                            if transaction.hasBothFeeTypes {
                                if let offchainFee = transaction.formattedFee {
                                    DetailRow(
                                        title: "activity_offchain_fee",
                                        value: offchainFee
                                    )
                                }
                                if let onchainFee = transaction.formattedOnchainFee {
                                    DetailRow(
                                        title: "activity_onchain_fee",
                                        value: onchainFee
                                    )
                                }
                                // Show total
                                if let totalFee = transaction.formattedTotalFees {
                                    DetailRow(
                                        title: "activity_total_fee",
                                        value: totalFee
                                    )
                                }
                            } else {
                                // Show single fee line
                                DetailRow(
                                    title: "label_fee",
                                    value: transaction.formattedTotalFees ?? BitcoinFormatter.shared.formatAmount(0)
                                )
                            }
                        }
                        
                        // Date
                        DetailRow(
                            title: "label_date",
                            value: transaction.date.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Text("label_details")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 15)
                
                Spacer()
            }
            .padding(.vertical, 15)
        }
        .overlay(alignment: .bottom) {
            if viewModel.showCopySuccess {
                Text("status_copied_clipboard")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
