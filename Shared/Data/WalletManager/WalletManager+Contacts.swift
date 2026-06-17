//
//  WalletManager+Contacts.swift
//  Arké
//
//  Contact management operations
//  All operations delegate to ContactService for persistence and relationship management
//

import Foundation
import SwiftData
import OSLog

extension WalletManager {
    
    // MARK: - Contact Properties
    
    var contacts: [ContactModel] {
        contactService.contacts
    }
    
    var alphabeticalContacts: [ContactModel] {
        contactService.alphabeticalContacts
    }
    
    var recentContacts: [ContactModel] {
        contactService.recentContacts
    }
    
    var contactCount: Int {
        contactService.contactCount
    }
    
    var hasContacts: Bool {
        contactService.hasContacts
    }
    
    var contactServiceError: String? {
        contactService.error
    }
    
    /// Access to ContactService for SwiftUI environment injection
    var contactServiceForEnvironment: ContactService {
        contactService
    }
    
    // MARK: - Contact Operations
    
    /// Create a new contact
    func createContact(_ contactModel: ContactModel) async throws -> ContactModel {
        return try await contactService.createContact(contactModel)
    }
    
    /// Update an existing contact
    func updateContact(_ contactModel: ContactModel) async throws {
        try await contactService.updateContact(contactModel)
    }
    
    /// Delete a contact
    func deleteContact(_ contactId: UUID) async throws {
        try await contactService.deleteContact(contactId)
    }
    
    /// Assign a contact to a transaction
    func assignContact(_ contactId: UUID, to transactionTxid: String) async throws {
        try await contactService.assignContact(contactId, to: transactionTxid)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after contact assignment")
    }
    
    /// Assign a contact to a transaction with address learning and bulk assignment
    /// This method performs three operations:
    /// 1. Assigns the contact to the specified transaction
    /// 2. Learns the address from the transaction and adds it to the contact (if new)
    /// 3. Auto-assigns the contact to all other unassigned transactions with the same address
    /// - Parameters:
    ///   - contactId: The UUID of the contact to assign
    ///   - transactionTxid: The transaction ID to assign the contact to
    /// - Returns: The number of additional transactions that were auto-assigned (beyond the primary assignment)
    @discardableResult
    func assignContactWithAddressLearning(_ contactId: UUID, to transactionTxid: String) async throws -> Int {
        guard let modelContext = modelContext else {
            throw BarkErrorArke.commandFailed("Model context not available")
        }
        
        Self.logger.debug("Starting contact assignment with address learning for transaction: \(transactionTxid)")

        // First, assign the contact to the transaction
        try await contactService.assignContact(contactId, to: transactionTxid)
        Self.logger.debug("Created basic contact assignment")
        
        // Try to get the transaction and its address
        let transactionDescriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate<PersistentTransaction> { $0.txid == transactionTxid }
        )
        let transactions = try modelContext.fetch(transactionDescriptor)
        
        guard let transaction = transactions.first,
              let address = transaction.address,
              !address.isEmpty else {
            // Transaction has no address, just return after basic assignment
            Self.logger.debug("Transaction \(transactionTxid) has no address, skipping address learning")
            return 0
        }
        
        // Get the contact to check if it already has this address
        let contactDescriptor = FetchDescriptor<PersistentContact>(
            predicate: #Predicate<PersistentContact> { $0.id == contactId }
        )
        let contacts = try modelContext.fetch(contactDescriptor)
        
        guard let contact = contacts.first else {
            Self.logger.warning("Contact \(contactId) not found for address learning")
            return 0
        }
        
        // Normalize the address for comparison
        let normalizedAddress = address.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        
        // Detect payment method type and skip single-use identifiers
        let paymentMethod = PaymentMethod.detect(from: address)
        if paymentMethod.isSingleUse {
            Self.logger.debug("Skipping address learning for single-use payment type: \(paymentMethod.displayType)")
            Self.logger.debug("Contact assignment complete - No auto-assignment for single-use payments")
            dataVersion += 1
            Self.logger.debug("DataVersion incremented to \(self.dataVersion) after contact assignment")
            return 0
        }
        
        // Check if the contact already has this address
        let hasAddress = contact.addresses?.contains { 
            $0.normalizedAddress == normalizedAddress 
        } ?? false
        
        // Add the address to the contact if it's new
        if !hasAddress {
            do {
                // Determine if this should be the primary address
                let isPrimary = contact.addresses?.isEmpty ?? true
                
                let newAddress = try await contactAddressService.validateAndCreateAddress(
                    address,
                    for: contactId,
                    label: "From transaction",
                    isPrimary: isPrimary
                )
                
                Self.logger.info("Added address to contact '\(contact.cachedName)': \(newAddress.shortAddress)")
            } catch {
                // Don't fail the whole operation if address creation fails
                Self.logger.warning("Failed to add address to contact: \(error)")
            }
        } else {
            Self.logger.debug("Contact '\(contact.cachedName)' already has address \(address)")
        }
        
        // Step 2: Find all other transactions with the same address
        // Note: We can't use lowercased() in predicates, so we fetch all transactions with addresses
        // and filter in memory for case-insensitive comparison
        let allTransactionsWithAddressDescriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate<PersistentTransaction> { transaction in
                transaction.address != nil
            }
        )
        let allTransactionsWithAddresses = try modelContext.fetch(allTransactionsWithAddressDescriptor)
        
        // Filter in memory for case-insensitive address matching
        let allTransactionsWithAddress = allTransactionsWithAddresses.filter { transaction in
            guard let txAddress = transaction.address else { return false }
            return txAddress.lowercased() == normalizedAddress
        }
        
        // Filter to only transactions without any contact assignments
        let unassignedTransactions = allTransactionsWithAddress.filter { tx in
            (tx.contactAssignments?.isEmpty ?? true) && tx.txid != transactionTxid
        }
        
        // Bulk assign the contact to all unassigned transactions
        var autoAssignedCount = 0
        for unassignedTransaction in unassignedTransactions {
            // Create the assignment
            let assignment = TransactionContactAssignment(contact: contact, transaction: unassignedTransaction)
            modelContext.insert(assignment)
            autoAssignedCount += 1
        }
        
        // Save all the new assignments at once
        if autoAssignedCount > 0 {
            do {
                contact.touch() // Update contact's timestamp
                try modelContext.save()
                Self.logger.info("Auto-assigned contact '\(contact.cachedName)' to \(autoAssignedCount) additional transaction(s) with address \(address)")
            } catch {
                Self.logger.warning("Failed to save auto-assignments: \(error)")
                // Don't throw - the main assignment already succeeded
            }
        } else {
            Self.logger.debug("No additional transactions to auto-assign (all transactions with this address already have contacts)")
        }

        // Final summary
        Self.logger.debug("Contact assignment complete - Total auto-assigned: \(autoAssignedCount)")
        
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after contact assignment with address learning")
        
        return autoAssignedCount
    }
    
    /// Remove a contact assignment from a transaction
    func unassignContact(_ contactId: UUID, from transactionTxid: String) async throws {
        try await contactService.unassignContact(contactId, from: transactionTxid)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after contact unassignment")
    }
    
    /// Remove all contact assignments from a transaction
    func removeContactAssignment(from transactionId: String) async throws {
        try await contactService.removeAllContactsFromTransaction(transactionId)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after removing all contact assignments")
    }
    
    /// Get all transactions with a specific contact
    func getTransactionsWithContact(_ contactId: UUID) async throws -> [TransactionModel] {
        return try await contactService.getTransactionsWithContact(contactId)
    }
    
    /// Get all contacts assigned to a specific transaction
    func getTransactionContacts(_ transactionId: String) async throws -> [ContactModel] {
        return try await contactService.getContactsForTransaction(transactionId)
    }
    
    /// Check if a transaction has any contacts
    func transactionHasContacts(_ transactionId: String) async throws -> Bool {
        let contacts = try await getTransactionContacts(transactionId)
        return !contacts.isEmpty
    }
    
    /// Search contacts by name
    func searchContacts(_ searchText: String) -> [ContactModel] {
        return contactService.searchContacts(searchText)
    }
    
    /// Get contact usage statistics
    func getContactStatistics() async throws -> [ContactStatistic] {
        return try await contactService.getContactStatistics()
    }
    
    /// Find or create contact by name
    func findOrCreateContact(name: String) async throws -> ContactModel {
        return try await contactService.findOrCreateContact(name: name)
    }
    
    /// Clear contact service errors
    func clearContactError() {
        contactService.clearError()
    }
    
    /// Refresh contacts from storage
    func refreshContacts() async {
        await contactService.refreshContacts()
    }
    
    /// Create default contacts if needed
    func createDefaultContactsIfNeeded() async {
        await contactService.createDefaultContactsIfNeeded()
    }
}
