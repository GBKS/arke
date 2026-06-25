//
//  TransactionList.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct TransactionList: View {
    @Binding var selectedTransaction: TransactionModel?
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    
    // SwiftData @Query for automatic updates
    // Filter out linked onchain transactions (those with a parentTxid)
    @Query(
        filter: #Predicate<PersistentTransaction> { transaction in
            transaction.parentTxid == nil
        },
        sort: \PersistentTransaction.date,
        order: .reverse
    )
    private var allTransactions: [PersistentTransaction]
    
    let filterTag: PersistentTag?
    let filterContact: PersistentContact?
    let onShowFaucet: (() -> Void)?
    
    init(selectedTransaction: Binding<TransactionModel?>, filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onShowFaucet: (() -> Void)? = nil) {
        self._selectedTransaction = selectedTransaction
        self.filterTag = filterTag
        self.filterContact = filterContact
        self.onShowFaucet = onShowFaucet
    }
    
    // Filtered transactions based on tag/contact
    private var filteredTransactions: [PersistentTransaction] {
        if let contact = filterContact {
            // Filter by contact
            let contactId = contact.id
            return allTransactions.filter { transaction in
                (transaction.contactAssignments ?? []).contains { assignment in
                    assignment.contact?.id == contactId
                }
            }
        } else if let tag = filterTag {
            // Filter by tag
            let tagId = tag.id
            return allTransactions.filter { transaction in
                (transaction.tagAssignments ?? []).contains { assignment in
                    assignment.tag?.id == tagId
                }
            }
        } else {
            // No filter
            return allTransactions
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {            
            // Transaction List
            if walletManager.isInitialLoading && allTransactions.isEmpty {
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
            } else if filteredTransactions.isEmpty {
                VStack {
                    TransactionListEmptyState(
                        filterTag: filterTag,
                        filterContact: filterContact,
                        onShowFaucet: onShowFaucet
                    )
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTransactions, id: \.txid) { persistentTransaction in
                        PersistentTransactionListItem(
                            persistentTransaction: persistentTransaction,
                            selectedTransaction: $selectedTransaction
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .opacity
                        ))
                        
                        if persistentTransaction.txid != filteredTransactions.last?.txid {
                            Divider()
                                .padding(.leading, 68) // Align with text content
                                .padding(.trailing, 12)
                        }
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.15), value: filteredTransactions.map { $0.txid })
                .background(.background)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
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
