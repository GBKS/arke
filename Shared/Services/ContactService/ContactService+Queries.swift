//
//  ContactService+Queries.swift
//  Arké
//
//  Query and search operations
//

import Foundation
import ArkeUI
import SwiftData

extension ContactService {
    
    /// Get all transactions that have a specific contact
    func getTransactionsWithContact(_ contactId: UUID) async throws -> [TransactionModel] {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        do {
            // Find contact assignments for this contact
            let assignmentDescriptor = FetchDescriptor<TransactionContactAssignment>(
                predicate: #Predicate<TransactionContactAssignment> { $0.contact?.id == contactId }
            )
            let assignments = try modelContext.fetch(assignmentDescriptor)
            
            // Extract persistent transactions and convert to UI models
            let persistentTransactions = assignments.compactMap { $0.transaction }
            return persistentTransactions.map { TransactionModel(from: $0) }
            
        } catch {
            print("❌ Failed to get transactions for contact: \(error)")
            throw error
        }
    }
    
    /// Get all contacts assigned to a specific transaction
    func getContactsForTransaction(_ transactionId: String) async throws -> [ContactModel] {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        do {
            // Find contact assignments for this transaction
            var assignmentDescriptor = FetchDescriptor<TransactionContactAssignment>(
                predicate: #Predicate<TransactionContactAssignment> { $0.transaction?.txid == transactionId }
            )
            // Prefetch the contact relationship and its addresses
            assignmentDescriptor.relationshipKeyPathsForPrefetching = [\.contact]
            
            let assignments = try modelContext.fetch(assignmentDescriptor)
            
            // Extract contacts and convert to UI models
            // Note: We need to manually access addresses within the model context
            let contactModels: [ContactModel] = assignments.compactMap { assignment in
                guard let contact = assignment.contact else { return nil }
                // Access addresses to ensure they're loaded before conversion
                _ = contact.addresses
                return ContactModel(from: contact)
            }
            return contactModels
            
        } catch {
            print("❌ Failed to get contacts for transaction: \(error)")
            throw error
        }
    }
    
    /// Search contacts by name
    func searchContacts(_ searchText: String) -> [ContactModel] {
        guard !searchText.isEmpty else { return contacts }
        
        return contacts.filter { contact in
            contact.cachedName.localizedCaseInsensitiveContains(searchText) ||
            (contact.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    /// Get contact statistics
    func getContactStatistics() async throws -> [ContactStatistic] {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        do {
            let contactDescriptor = FetchDescriptor<PersistentContact>()
            let persistentContacts = try modelContext.fetch(contactDescriptor)
            
            let statistics = persistentContacts.map { contact in
                ContactStatistic(
                    contactId: contact.id,
                    contactName: contact.displayName,
                    transactionCount: contact.transactionCount,
                    totalAmount: contact.totalTransactionAmount,
                    sentAmount: contact.sentAmount,
                    receivedAmount: contact.receivedAmount,
                    lastActivity: contact.updatedAt
                )
            }
            
            return statistics.sorted { $0.transactionCount > $1.transactionCount }
            
        } catch {
            print("❌ Failed to get contact statistics: \(error)")
            throw error
        }
    }
    
    /// Find or create contact by name
    func findOrCreateContact(name: String) async throws -> ContactModel {
        // First try to find existing contact
        if let existingContact = contacts.first(where: { $0.cachedName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existingContact
        }
        
        // Create new contact if not found
        let newContact = ContactModel(cachedName: name)
        return try await createContact(newContact)
    }
    
    /// Get addresses for a specific contact
    func getAddresses(for contactId: UUID) -> [ContactAddressModel] {
        return contacts.first { $0.id == contactId }?.addresses ?? []
    }
}
