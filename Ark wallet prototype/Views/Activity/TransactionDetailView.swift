//
//  TransactionDetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import AppKit

struct TransactionDetailView: View {
    let transaction: TransactionModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    // Transaction Icon and Type
                    HStack {
                        Image(systemName: transaction.type.iconName)
                            .font(.system(size: 40))
                            .foregroundColor(transaction.type.iconColor)
                        
                        VStack(alignment: .leading) {
                            Text(transaction.type.displayName)
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
                        .fontWeight(.bold)
                        .foregroundColor(transaction.type.amountColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Status Badge
                    HStack {
                        Text(transaction.status.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(transaction.status.textColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(transaction.status.backgroundColor)
                            .clipShape(Capsule())
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transaction Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // Transaction ID
                        if let txid = transaction.txid {
                            DetailRow(
                                title: "Transaction ID",
                                value: txid,
                                isCopyable: true
                            )
                        }
                        
                        // Address
                        if let address = transaction.address {
                            DetailRow(
                                title: transaction.type == .received ? "From Address" : "To Address",
                                value: address,
                                isCopyable: true
                            )
                        }
                        
                        // Date
                        DetailRow(
                            title: "Date",
                            value: transaction.date.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Transaction")
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    let isCopyable: Bool
    
    init(title: String, value: String, isCopyable: Bool = false) {
        self.title = title
        self.value = value
        self.isCopyable = isCopyable
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isCopyable {
                Button {
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(
            transaction: TransactionModel(
                type: .received,
                amount: 50000,
                date: Date().addingTimeInterval(-3600),
                status: .confirmed,
                txid: "1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z",
                address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
            )
        )
    }
}
