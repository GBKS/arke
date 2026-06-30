//
//  ContactService+CRUD.swift
//  Arké
//
//  Contact Create, Read, Update, Delete operations
//

import Foundation
import ArkeUI
import SwiftData

extension ContactService {
    
    /// Load all contacts from SwiftData
    func loadContacts() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading contacts")
            return
        }
        
        do {
            var descriptor = FetchDescriptor<PersistentContact>(sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ])
            // Prefetch the addresses relationship to avoid lazy loading issues
            descriptor.relationshipKeyPathsForPrefetching = [\.addresses]
            
            let persistentContacts = try modelContext.fetch(descriptor)
            
            // Convert to UI models (addresses will now be included)
            self.contacts = persistentContacts.map { ContactModel(from: $0) }
            
            print("👥 Loaded \(contacts.count) contacts with addresses from SwiftData")
            
        } catch {
            print("❌ Failed to load contacts: \(error)")
            self.error = "Failed to load contacts: \(error)"
        }
    }
    
    /// Create a new contact
    func createContact(_ contactModel: ContactModel) async throws -> ContactModel {
        return try await taskManager.execute(key: "createContact_\(contactModel.cachedName)") {
            try await self.performCreateContact(contactModel)
        }
    }
    
    private func performCreateContact(_ contactModel: ContactModel) async throws -> ContactModel {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Check if contact with same name already exists
            let contactName = contactModel.cachedName
            let existingDescriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.cachedName == contactName }
            )
            let existingContacts = try modelContext.fetch(existingDescriptor)
            
            if !existingContacts.isEmpty {
                throw ContactServiceError.contactAlreadyExists(contactModel.cachedName)
            }
            
            // Create persistent contact
            let persistentContact = contactModel.toPersistentContact()
            modelContext.insert(persistentContact)
            
            // Save changes
            try modelContext.save()
            
            // Add to local array
            // Access addresses to ensure they're loaded (though new contacts won't have addresses yet)
            _ = persistentContact.addresses
            let newContact = ContactModel(from: persistentContact)
            self.contacts.append(newContact)
            
            print("✅ Created contact: \(newContact.cachedName)")
            return newContact
            
        } catch {
            print("❌ Failed to create contact: \(error)")
            self.error = "Failed to create contact: \(error)"
            throw error
        }
    }
    
    /// Update an existing contact
    func updateContact(_ updatedContact: ContactModel) async throws {
        return try await taskManager.execute(key: "updateContact_\(updatedContact.id)") {
            try await self.performUpdateContact(updatedContact)
        }
    }
    
    private func performUpdateContact(_ updatedContact: ContactModel) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent contact
            let contactId = updatedContact.id
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactId }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            
            guard let persistentContact = existingContacts.first else {
                throw ContactServiceError.contactNotFound(updatedContact.id)
            }
            
            // Update properties
            persistentContact.cachedName = updatedContact.cachedName
            persistentContact.notes = updatedContact.notes
            persistentContact.avatarData = updatedContact.avatarData
            persistentContact.touch() // Update timestamp
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = contacts.firstIndex(where: { $0.id == updatedContact.id }) {
                // Access addresses to ensure they're loaded
                _ = persistentContact.addresses
                contacts[index] = ContactModel(from: persistentContact)
            }
            
            print("✅ Updated contact: \(updatedContact.cachedName)")
            
        } catch {
            print("❌ Failed to update contact: \(error)")
            self.error = "Failed to update contact: \(error)"
            throw error
        }
    }
    
    /// Delete a contact and all its assignments
    func deleteContact(_ contactId: UUID) async throws {
        return try await taskManager.execute(key: "deleteContact_\(contactId)") {
            try await self.performDeleteContact(contactId)
        }
    }
    
    private func performDeleteContact(_ contactId: UUID) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find the contact
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactId }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            
            guard let persistentContact = existingContacts.first else {
                throw ContactServiceError.contactNotFound(contactId)
            }
            
            let contactName = persistentContact.cachedName
            
            // Delete the contact (cascade will delete assignments)
            modelContext.delete(persistentContact)
            
            // Save changes
            try modelContext.save()
            
            // Remove from local array
            contacts.removeAll { $0.id == contactId }
            
            print("✅ Deleted contact: \(contactName)")
            
        } catch {
            print("❌ Failed to delete contact: \(error)")
            self.error = "Failed to delete contact: \(error)"
            throw error
        }
    }
    
    /// Load contacts with their addresses included
    func loadContactsWithAddresses() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading contacts")
            return
        }
        
        do {
            var descriptor = FetchDescriptor<PersistentContact>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            // Prefetch the addresses relationship to avoid lazy loading issues
            descriptor.relationshipKeyPathsForPrefetching = [\.addresses]
            
            let persistentContacts = try modelContext.fetch(descriptor)
            
            // Convert to UI models (addresses will now be included)
            self.contacts = persistentContacts.map { ContactModel(from: $0) }
            
            print("👥 Loaded \(contacts.count) contacts with addresses from SwiftData")
            
        } catch {
            print("❌ Failed to load contacts with addresses: \(error)")
            self.error = "Failed to load contacts with addresses: \(error)"
        }
    }
}
