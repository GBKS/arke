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
            Image(systemName: transaction.transactionType.iconName)
                .font(.title3)
                .foregroundColor(transaction.transactionType.iconColor)
                .frame(width: 32, height: 32)
                .background(transaction.transactionType.iconColor.opacity(0.1))
                .cornerRadius(8)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionType.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(transaction.formattedDate)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {                
                if transaction.transactionStatus != .confirmed {
                    TransactionStatusBadge(status: transaction.transactionStatus)
                }
                
                Text(transaction.formattedAmount)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(transaction.transactionType.amountColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(selectedTransaction?.txid == transaction.txid ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .cornerRadius(15)
        .onTapGesture {
            selectedTransaction = transaction
        }
    }
}

#Preview("Transaction List Item") {
    @Previewable @State var selectedTransaction: TransactionModel? = nil
    
    let sampleTransactions = [
        TransactionModel(
            txid: "movement_1",
            movementId: 1,
            recipientIndex: nil,
            type: .received,
            amount: 50000,
            date: Date().addingTimeInterval(-3600), // 1 hour ago
            status: .confirmed,
            address: nil
        ),
        TransactionModel(
            txid: "movement_2_recipient_0",
            movementId: 2,
            recipientIndex: 0,
            type: .sent,
            amount: 25000,
            date: Date().addingTimeInterval(-86400), // 1 day ago
            status: .pending,
            address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        ),
        TransactionModel(
            txid: "movement_3",
            movementId: 3,
            recipientIndex: nil,
            type: .received,
            amount: 10000,
            date: Date().addingTimeInterval(-300), // 5 minutes ago
            status: .confirmed,
            address: nil
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
