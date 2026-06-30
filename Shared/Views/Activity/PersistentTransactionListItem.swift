//
//  PersistentTransactionListItem.swift
//  Arké
//
//  Wrapper around TransactionListItem that works with PersistentTransaction
//  This enables automatic SwiftData updates
//

import SwiftUI
import ArkeUI
import SwiftData

struct PersistentTransactionListItem: View {
    let persistentTransaction: PersistentTransaction
    @Binding var selectedTransaction: TransactionModel?
    
    var body: some View {
        // Convert to TransactionModel and use existing TransactionListItem
        // The conversion happens on every render, so we always have fresh data
        TransactionListItem(
            transaction: TransactionModel(from: persistentTransaction),
            selectedTransaction: $selectedTransaction
        )
    }
}
