//
//  TransactionList.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

struct TransactionList: View {
    @Query(sort: \TransactionModel.date, order: .reverse)
    private var transactions: [TransactionModel]
    
    @Binding var selectedTransaction: TransactionModel?
    @Environment(TransactionService.self) private var transactionService
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {            
            // Transaction List
            if transactionService.isRefreshing && transactions.isEmpty {
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
                VStack {
                    ContentUnavailableView {
                        VStack(spacing: 15) {
                            Image(systemName: "arrow.down")
                                .imageScale(.medium)
                                .symbolVariant(.none)
                            Text("Start by sending bitcoin to your wallet")
                                .font(.system(size: 19, design: .serif))
                        }
                    }
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        TransactionListItem(transaction: transaction, selectedTransaction: $selectedTransaction)
                        
                        if transaction.txid != transactions.last?.txid {
                            Divider()
                                .padding(.leading, 56) // Align with text content
                        }
                    }
                }
                .background(.background)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
        .overlay(alignment: .top) {
            if transactionService.isRefreshing && !transactions.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Mock Data for Previews
extension TransactionModel {
    @MainActor
    static var mockData: [TransactionModel] {
        [
            TransactionModel(
                txid: "movement_1_recipient_0",
                movementId: 1,
                recipientIndex: 0,
                type: .received,
                amount: 50000,
                date: Date().addingTimeInterval(-3600),
                status: .confirmed,
                address: nil
            ),
            TransactionModel(
                txid: "movement_2_recipient_0",
                movementId: 2,
                recipientIndex: 0,
                type: .sent,
                amount: 25000,
                date: Date().addingTimeInterval(-7200),
                status: .confirmed,
                address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
            ),
            TransactionModel(
                txid: "movement_3",
                movementId: 3,
                recipientIndex: nil,
                type: .received,
                amount: 75000,
                date: Date().addingTimeInterval(-86400),
                status: .confirmed,
                address: nil
            )
        ]
    }
}

#Preview("With Transactions") {
    @Previewable @State var selectedTransaction: TransactionModel? = nil
    @Previewable @State var transactionService = TransactionService(
        wallet: MockBarkWallet(), 
        taskManager: TaskDeduplicationManager()
    )
    
    NavigationView {
        TransactionList(selectedTransaction: $selectedTransaction)
            .environment(transactionService)
    }
    .modelContainer(for: TransactionModel.self, inMemory: true)
}

#Preview("Empty State") {
    @Previewable @State var selectedTransaction: TransactionModel? = nil
    @Previewable @State var transactionService = TransactionService(
        wallet: MockBarkWallet(), 
        taskManager: TaskDeduplicationManager()
    )
    
    NavigationView {
        TransactionList(selectedTransaction: $selectedTransaction)
            .environment(transactionService)
    }
    .modelContainer(for: TransactionModel.self, inMemory: true)
}
