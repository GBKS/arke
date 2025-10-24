//
//  TransactionListItem.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct TransactionListItem: View {
    let transaction: TransactionModel
    @Binding var selectedTransaction: TransactionModel?
    
    var body: some View {
        HStack(spacing: 12) {
            // Transaction Icon
            Image(systemName: transaction.type.iconName)
                .font(.title3)
                .foregroundColor(transaction.type.iconColor)
                .frame(width: 32, height: 32)
                .background(transaction.type.iconColor.opacity(0.1))
                .cornerRadius(8)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.type.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(transaction.formattedDate)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {                
                if transaction.status != .confirmed {
                    TransactionStatusBadge(status: transaction.status)
                }
                
                Text(transaction.formattedAmount)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(transaction.type.amountColor)
            }
        }
        .padding(.vertical, 16)
        .background(selectedTransaction?.id == transaction.id ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTransaction = transaction
        }
    }
}

#Preview("Transaction List Item") {
    @Previewable @State var selectedTransaction: TransactionModel? = nil
    
    let sampleTransactions = [
        TransactionModel(
            type: .received,
            amount: 50000,
            date: Date().addingTimeInterval(-3600), // 1 hour ago
            status: .confirmed,
            txid: "abc123def456",
            address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        ),
        TransactionModel(
            type: .sent,
            amount: 25000,
            date: Date().addingTimeInterval(-86400), // 1 day ago
            status: .pending,
            txid: "def456ghi789",
            address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        ),
        TransactionModel(
            type: .pending,
            amount: 10000,
            date: Date().addingTimeInterval(-300), // 5 minutes ago
            status: .failed,
            txid: nil,
            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        )
    ]
    
    return VStack(spacing: 0) {
        ForEach(sampleTransactions) { transaction in
            TransactionListItem(
                transaction: transaction,
                selectedTransaction: $selectedTransaction
            )
            Divider()
        }
    }
    .padding()
}
