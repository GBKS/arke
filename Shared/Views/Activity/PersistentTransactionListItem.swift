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
    /// Tags and contacts resolved by the list in one pass — see
    /// `TransactionMetadataSnapshot`. Passed in rather than read off the
    /// transaction's relationships, which would run a fetch pair per row on
    /// every layout pass.
    let tags: [TagModel]
    let contacts: [ContactModel]
    @Binding var selectedTransaction: TransactionModel?

    var body: some View {
        // Convert to TransactionModel and use existing TransactionListItem
        // The conversion happens on every render, so we always have fresh data
        TransactionListItem(
            transaction: TransactionModel(from: persistentTransaction, tags: tags, contacts: contacts),
            selectedTransaction: $selectedTransaction
        )
    }
}
