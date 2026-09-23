//
//  TransactionList_iOS.swift
//  Ark wallet prototype
//
//  Created by Christoph on 12/05/25.
//

import SwiftUI
import SwiftData
import UIKit
import ArkeUI

struct TransactionList_iOS: View {
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
    
    @State private var previousTransactionIds: Set<String> = []

    // Card stack overlay prototype: taps open a swipeable card stack instead
    // of pushing the detail view directly. The overlay handles its own
    // entrance/exit animation, so the cover transition is disabled.
    @State private var cardStackSelection: TransactionModel?
    @State private var stackTransactions: [PersistentTransaction] = []
    @State private var stackInitialIndex = 0
    @State private var showCardStack = false

    let filterTag: PersistentTag?
    let filterContact: PersistentContact?
    let onShowFaucet: (() -> Void)?
    let onNavigateToReceive: (() -> Void)?
    
    init(selectedTransaction: Binding<TransactionModel?>, filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onShowFaucet: (() -> Void)? = nil, onNavigateToReceive: (() -> Void)? = nil) {
        self._selectedTransaction = selectedTransaction
        self.filterTag = filterTag
        self.filterContact = filterContact
        self.onShowFaucet = onShowFaucet
        self.onNavigateToReceive = onNavigateToReceive
    }
    
    // Tags and contacts for every row, resolved in one pass per render instead
    // of per row. Reading dataVersion registers the dependency that tag and
    // contact assignment changes bump, so rows re-resolve with the list.
    private var metadataSnapshot: TransactionMetadataSnapshot {
        _ = walletManager.dataVersion

        return TransactionMetadataSnapshot(modelContext: modelContext)
    }

    // Filtered transactions based on tag/contact. Filtering off the snapshot
    // keeps the relationship arrays out of it — walking those is what trapped
    // when a CloudKit import deleted an assignment row mid-layout.
    private func filteredTransactions(
        with metadata: TransactionMetadataSnapshot
    ) -> [PersistentTransaction] {
        if let contact = filterContact {
            // Filter by contact
            let contactId = contact.id
            return allTransactions.filter {
                metadata.transaction(withTxid: $0.txid, hasContactWithId: contactId)
            }
        } else if let tag = filterTag {
            // Filter by tag
            let tagId = tag.id
            return allTransactions.filter {
                metadata.transaction(withTxid: $0.txid, hasTagWithId: tagId)
            }
        } else {
            // No filter
            return allTransactions
        }
    }

    var body: some View {
        let metadata = metadataSnapshot
        let visibleTransactions = filteredTransactions(with: metadata)

        return Group {
            if walletManager.isInitialLoading && allTransactions.isEmpty {
                // Loading state with skeleton (only for first-time users with no cached data)
                ScrollView {
                    VStack(spacing: 12) {
                        SkeletonLoader(
                            itemCount: 8,
                            itemHeight: 72,
                            spacing: 12,
                            cornerRadius: 12
                        )
                    }
                    .padding()
                }
            } else if visibleTransactions.isEmpty {
                // Empty state (no transactions exist)
                TransactionListEmptyState(
                    filterTag: filterTag,
                    filterContact: filterContact,
                    onShowFaucet: onShowFaucet,
                    onNavigateToReceive: onNavigateToReceive
                )
                .padding(.top, 25)
            } else {
                // Transaction list (with cached or fresh data)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleTransactions, id: \.txid) { persistentTransaction in
                            PersistentTransactionListItem(
                                persistentTransaction: persistentTransaction,
                                tags: metadata.tags(forTxid: persistentTransaction.txid),
                                contacts: metadata.contacts(forTxid: persistentTransaction.txid),
                                selectedTransaction: $cardStackSelection
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .opacity
                            ))
                            
                            if persistentTransaction.txid != visibleTransactions.last?.txid {
                                Divider()
                                    .padding(.leading, 68) // Align with text content
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.15), value: visibleTransactions.map { $0.txid })
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .refreshable {
                    await refreshTransactions()
                }
                .onAppear {
                    previousTransactionIds = Set(visibleTransactions.map { $0.txid })
                }
            }
        }
        .onChange(of: cardStackSelection) { _, newValue in
            guard let transaction = newValue else { return }
            // Snapshot the filtered list so refreshes underneath don't shift the stack
            stackTransactions = visibleTransactions
            stackInitialIndex = stackTransactions.firstIndex { $0.txid == transaction.txid } ?? 0
            // The overlay animates its own entrance. The cover's slide-up is a
            // UIKit presentation that ignores SwiftUI's disablesAnimations, so
            // UIView animations are switched off around the presentation; the
            // overlay re-enables them in onAppear.
            UIView.setAnimationsEnabled(false)
            showCardStack = true
            cardStackSelection = nil
        }
        .fullScreenCover(isPresented: $showCardStack, onDismiss: {
            UIView.setAnimationsEnabled(true)
        }) {
            TransactionCardStackView_iOS(
                transactions: stackTransactions,
                initialIndex: stackInitialIndex
            )
            .environment(walletManager)
            .presentationBackground(.clear)
        }
    }
    
    private func refreshTransactions() async {
        // Trigger wallet refresh
        await walletManager.refresh()
    }
}
