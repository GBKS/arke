//
//  TransactionService+AutoTagging.swift
//  Arke
//
//  Automatic tagging and contact assignment logic.
//  Handles Balance system tags and address-based contact linking.
//

import Foundation
import SwiftData
import ArkeUI
import os

// MARK: - TransactionService+AutoTagging

extension TransactionService {
    
    // MARK: Private Tag Management
    
    /// Get the "Balance" system tag, creating it if it doesn't exist
    /// - Returns: The Balance system tag
    /// - Throws: Error if tag creation or fetch fails
    private func getOrCreateBalanceSystemTag() async throws -> PersistentTag {
        guard let modelContext = modelContext else {
            throw TransactionServiceError.noModelContext
        }
        
        // Try to fetch existing "Balance" system tag
        let descriptor = FetchDescriptor<PersistentTag>(
            predicate: #Predicate<PersistentTag> { tag in
                tag.name == "Balance" && tag.isSystemTag == true
            }
        )
        
        let existingTags = try modelContext.fetch(descriptor)
        
        if let existingTag = existingTags.first {
            return existingTag
        }
        
        // Create new "Balance" system tag
        let balanceTag = PersistentTag(
            name: "Balance",
            colorHex: "#C33C2D",
            emoji: "👜",
            createdDate: Date(),
            isSystemTag: true
        )
        
        modelContext.insert(balanceTag)
        try modelContext.save()
        
        Self.logger.info("✨ Created 'Balance' system tag for internal transfers")
        
        return balanceTag
    }
    
    // MARK: Tag Assignment Preservation
    
    /// Cache existing tag assignments for preservation during updates
    /// This method is primarily for logging and verification - SwiftData relationships handle preservation automatically
    private func cacheExistingTagAssignments(from transactions: [PersistentTransaction]) async -> [String: [TransactionTagAssignment]] {
        var cache: [String: [TransactionTagAssignment]] = [:]
        
        for transaction in transactions {
            let tagAssignments = transaction.tagAssignments ?? []
            if !tagAssignments.isEmpty {
                cache[transaction.txid] = tagAssignments
            }
        }
        
        let totalTagAssignments = cache.values.flatMap { $0 }.count
        if totalTagAssignments > 0 {
            Self.logger.info("🏷️ Found \(totalTagAssignments) existing tag assignments across \(cache.count) transactions")
        }
        
        return cache
    }
    
    // MARK: Public Methods
    
    /// Automatically tag an internal transfer with the "Balance" system tag
    /// - Parameter transaction: The internal transfer transaction to tag
    func autoTagInternalTransfer(_ transaction: PersistentTransaction) async {
        guard let modelContext = modelContext else {
            Self.logger.warning("⚠️ No model context available for auto-tagging internal transfer")
            return
        }
        
        do {
            // Get or create the "Balance" system tag
            let balanceTag = try await getOrCreateBalanceSystemTag()
            
            // Check if this transaction already has the Balance tag
            let existingAssignments = transaction.tagAssignments ?? []
            let alreadyTagged = existingAssignments.contains { assignment in
                assignment.tag?.id == balanceTag.id
            }
            
            if alreadyTagged {
                // Already tagged, skip
                return
            }
            
            // Create the tag assignment
            let assignment = TransactionTagAssignment(
                tag: balanceTag,
                transaction: transaction,
                assignedDate: Date()
            )
            modelContext.insert(assignment)
            
            Self.logger.info("🏷️ Auto-tagged internal transfer \(transaction.txid) with 'Balance' system tag")
            
        } catch {
            Self.logger.error("⚠️ Failed to auto-tag internal transfer: \(error.localizedDescription)")
        }
    }
    
    /// Automatically assign a contact to a transaction if the address matches any contact's addresses
    /// - Parameters:
    ///   - address: The transaction address to match against contact addresses
    ///   - transaction: The transaction to assign the contact to
    ///   - modelContext: The SwiftData model context for database operations
    /// - Returns: True if a contact was auto-assigned, false otherwise
    func autoAssignContactForAddress(_ address: String, transaction: PersistentTransaction, modelContext: ModelContext) async -> Bool {
        // Normalize the address for case-insensitive comparison
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        do {
            // Query for any contact address that matches this normalized address
            let addressDescriptor = FetchDescriptor<PersistentContactAddress>(
                predicate: #Predicate<PersistentContactAddress> {
                    $0.normalizedAddress == normalizedAddress
                }
            )
            let matchingAddresses = try modelContext.fetch(addressDescriptor)
            
            guard let matchingAddress = matchingAddresses.first else {
                // No contact found with this address - this is normal, skip silently
                return false
            }
            
            // Check if multiple contacts have this address (unusual but possible)
            if matchingAddresses.count > 1 {
                let contactNames = matchingAddresses.compactMap { $0.contact?.cachedName }.joined(separator: ", ")
                Self.logger.warning("⚠️ Multiple contacts found for address \(address): [\(contactNames)], using first match")
            }
            
            // Get the associated contact
            guard let contact = matchingAddress.contact else {
                Self.logger.warning("⚠️ Contact address found but contact relationship is nil for address: \(address)")
                return false
            }
            
            // Check if this transaction already has this contact assigned (shouldn't happen for new transactions, but defensive)
            let contactAssignments = transaction.contactAssignments ?? []
            let alreadyAssigned = contactAssignments.contains {
                $0.contact?.id == contact.id
            }
            
            if alreadyAssigned {
                // Already assigned, skip
                return false
            }
            
            // Create the auto-assignment
            let assignment = TransactionContactAssignment(contact: contact, transaction: transaction)
            modelContext.insert(assignment)
            
            // Update contact's timestamp
            contact.touch()
            
            Self.logger.info("✅ Auto-assigned contact '\(contact.cachedName)' to transaction \(transaction.txid) based on address \(address)")
            
            return true
            
        } catch {
            // Log but don't fail the transaction insertion
            Self.logger.error("⚠️ Failed to check auto-assignment for address \(address): \(error.localizedDescription)")
            return false
        }
    }
}
