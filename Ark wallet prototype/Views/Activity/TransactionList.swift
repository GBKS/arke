//
//  TransactionList.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct TransactionList: View {
    let transactions: [TransactionModel]
    @Binding var selectedTransaction: TransactionModel?
    let isInitialLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Transaction List
            if isInitialLoading {
                VStack(spacing: 16) {
                    SkeletonLoader(
                        itemCount: 6,
                        itemHeight: 64,
                        spacing: 15,
                        cornerRadius: 15
                    )
                }
                .padding(.vertical, 16)
                .padding(.horizontal)
            } else if transactions.isEmpty {
                VStack(spacing: 12) {
                    Text("Start by sending some bitcoin to your savings balance.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        TransactionListItem(transaction: transaction, selectedTransaction: $selectedTransaction)
                        
                        if transaction.id != transactions.last?.id {
                            Divider()
                                .padding(.leading, 44) // Align with text content
                        }
                    }
                }
                .background(.background)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Preview Data
extension TransactionModel {
    static var mockData: [TransactionModel] {
        [
            TransactionModel(
                type: .received,
                amount: 50000,
                date: Date().addingTimeInterval(-3600), // 1 hour ago
                status: .confirmed,
                txid: "abc123...",
                address: "bc1q..."
            ),
            TransactionModel(
                type: .sent,
                amount: 25000,
                date: Date().addingTimeInterval(-7200), // 2 hours ago
                status: .confirmed,
                txid: "def456...",
                address: "bc1q..."
            ),
            TransactionModel(
                type: .pending,
                amount: 10000,
                date: Date().addingTimeInterval(-1800), // 30 minutes ago
                status: .pending,
                txid: nil,
                address: "bc1q..."
            ),
            TransactionModel(
                type: .received,
                amount: 75000,
                date: Date().addingTimeInterval(-86400), // 1 day ago
                status: .confirmed,
                txid: "ghi789...",
                address: "bc1q..."
            )
        ]
    }
}

#Preview("With Transactions") {
    TransactionList(transactions: TransactionModel.mockData, selectedTransaction: .constant(nil), isInitialLoading: false)
        .padding()
}

#Preview("Empty State") {
    TransactionList(transactions: [], selectedTransaction: .constant(nil), isInitialLoading: false)
        .padding()
}

#Preview("Loading State") {
    TransactionList(transactions: [], selectedTransaction: .constant(nil), isInitialLoading: true)
        .padding()
}
