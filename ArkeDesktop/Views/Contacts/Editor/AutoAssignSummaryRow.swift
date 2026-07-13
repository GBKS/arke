//
//  AutoAssignSummaryRow.swift
//  Arké
//
//  Created by Christoph on 11/11/25.
//

import SwiftUI
import ArkeUI

struct AutoAssignSummaryRow: View {
    let transaction: TransactionModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Transaction type icon
            Image(systemName: transaction.transactionType == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundColor(transaction.transactionType == .received ? .Arke.green : .Arke.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.formattedAmount)
                    .font(.headline)
                
                Text(transaction.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status badge
            Text(transaction.status.displayName.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var statusColor: Color {
        switch transaction.transactionStatus {
        case .confirmed:
            return .Arke.green
        case .pending:
            return .Arke.orange
        case .failed:
            return .Arke.red
        case .cancelled:
            return .gray
        }
    }
}
