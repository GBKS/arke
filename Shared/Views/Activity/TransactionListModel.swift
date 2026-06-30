//
//  TransactionListModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 12/05/25.
//

import SwiftUI
import ArkeUI
import SwiftData

@Observable
final class TransactionListModel {
    private(set) var transactions: [TransactionModel] = []
    private(set) var isLoading: Bool = false
    
    private var modelContext: ModelContext
    private var walletManager: WalletManager
    
    let filterTag: PersistentTag?
    let filterContact: PersistentContact?
    
    init(
        modelContext: ModelContext,
        walletManager: WalletManager,
        filterTag: PersistentTag? = nil,
        filterContact: PersistentContact? = nil
    ) {
        self.modelContext = modelContext
        self.walletManager = walletManager
        self.filterTag = filterTag
        self.filterContact = filterContact
        
        // Immediately load cached transactions from SwiftData
        // This provides instant UI feedback while wallet syncs fresh data
        loadCachedTransactions()
    }
    
    /// Load cached transactions from SwiftData immediately (no async operations)
    private func loadCachedTransactions() {
        // Direct SwiftData query for cached transactions
        if let contact = filterContact {
            transactions = transactionsForContact(contact, context: modelContext)
        } else if let tag = filterTag {
            transactions = transactionsForTag(tag, context: modelContext)
        } else {
            transactions = allTransactions(context: modelContext)
        }
    }
    
    /// Fetch transactions based on the current filter
    func fetchTransactions() {
        // Access dataVersion to create observation dependency
        // This ensures the view updates when relationships change
        _ = walletManager.dataVersion
        
        // Fetch new transactions
        let newTransactions: [TransactionModel]
        
        // Use unified transaction service if available (includes both ark + onchain)
        if let unifiedService = walletManager.unifiedTransactionServiceInstance {
            if let contact = filterContact {
                newTransactions = unifiedService.transactionsForContact(contact)
            } else if let tag = filterTag {
                newTransactions = unifiedService.transactionsForTag(tag)
            } else {
                newTransactions = unifiedService.allTransactions
            }
        } else {
            // Fallback to direct SwiftData queries (backwards compatibility)
            if let contact = filterContact {
                newTransactions = transactionsForContact(contact, context: modelContext)
            } else if let tag = filterTag {
                newTransactions = transactionsForTag(tag, context: modelContext)
            } else {
                newTransactions = allTransactions(context: modelContext)
            }
        }
        
        // Update with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            transactions = newTransactions
        }
    }
    
    // MARK: - Private Fetch Methods
    
    /// Get all transactions (no filter)
    private func allTransactions(context: ModelContext) -> [TransactionModel] {
        let fetchDescriptor = createFetchDescriptor()
        do {
            let persistentTransactions = try context.fetch(fetchDescriptor)
            return persistentTransactions.map { TransactionModel(from: $0) }
        } catch {
            print("Error fetching transactions: \(error)")
            return []
        }
    }
    
    /// Get transactions for a specific tag
    private func transactionsForTag(_ tag: PersistentTag, context: ModelContext) -> [TransactionModel] {
        do {
            // Store the tag ID to avoid capturing the tag object in the predicate
            let tagId = tag.id
            
            // First, get all tag assignments for this tag
            let assignmentDescriptor = FetchDescriptor<TransactionTagAssignment>(
                predicate: #Predicate<TransactionTagAssignment> { assignment in
                    assignment.tag?.id == tagId
                }
            )
            let assignments = try context.fetch(assignmentDescriptor)
            
            // Extract the transaction IDs
            let txids = assignments.compactMap { $0.transaction?.txid }
            
            // If no assignments found, return empty array
            guard !txids.isEmpty else { return [] }
            
            // Now fetch transactions with those IDs, sorted by date
            let transactionDescriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate<PersistentTransaction> { transaction in
                    txids.contains(transaction.txid)
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            let persistentTransactions = try context.fetch(transactionDescriptor)
            return persistentTransactions.map { TransactionModel(from: $0) }
        } catch {
            print("Error fetching transactions for tag: \(error)")
            return []
        }
    }
    
    /// Get transactions for a specific contact
    private func transactionsForContact(_ contact: PersistentContact, context: ModelContext) -> [TransactionModel] {
        do {
            // Store the contact ID to avoid capturing the contact object in the predicate
            let contactId = contact.id
            
            // First, get all contact assignments for this contact
            let assignmentDescriptor = FetchDescriptor<TransactionContactAssignment>(
                predicate: #Predicate<TransactionContactAssignment> { assignment in
                    assignment.contact?.id == contactId
                }
            )
            let assignments = try context.fetch(assignmentDescriptor)
            
            // Extract the transaction IDs
            let txids = assignments.compactMap { $0.transaction?.txid }
            
            // If no assignments found, return empty array
            guard !txids.isEmpty else { return [] }
            
            // Now fetch transactions with those IDs, sorted by date
            let transactionDescriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate<PersistentTransaction> { transaction in
                    txids.contains(transaction.txid)
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            let persistentTransactions = try context.fetch(transactionDescriptor)
            return persistentTransactions.map { TransactionModel(from: $0) }
        } catch {
            print("Error fetching transactions for contact: \(error)")
            return []
        }
    }
    
    /// Create fetch descriptor for all transactions (no filter)
    private func createFetchDescriptor() -> FetchDescriptor<PersistentTransaction> {
        var descriptor = FetchDescriptor<PersistentTransaction>()
        descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        return descriptor
    }
}
