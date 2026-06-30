//
//  ContactService+NativeIntegration.swift
//  Arké
//
//  Native Contacts app integration
//

import Foundation
import ArkeUI
import SwiftData

extension ContactService {
    
    /// Import a contact from native Contacts app
    func importFromNativeContact(nativeID: String, nativeData: ImportedContactData) async throws -> ContactModel {
        return try await taskManager.execute(key: "importNativeContact_\(nativeID)") {
            try await self.performImportFromNativeContact(nativeID: nativeID, nativeData: nativeData)
        }
    }
    
    private func performImportFromNativeContact(nativeID: String, nativeData: ImportedContactData) async throws -> ContactModel {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Check if already imported
            let existingDescriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.nativeContactID == nativeID }
            )
            let existingContacts = try modelContext.fetch(existingDescriptor)
            
            if let existingContact = existingContacts.first {
                print("ℹ️ Contact already imported from native: \(existingContact.cachedName)")
                // Return existing contact
                _ = existingContact.addresses
                return ContactModel(from: existingContact)
            }
            
            // Create new contact with native link
            let now = Date()
            let newContact = ContactModel(
                cachedName: nativeData.fullName,
                avatarData: nativeData.imageData,
                createdAt: now,
                updatedAt: now,
                nativeContactID: nativeData.identifier,
                lastSyncedFromNative: now
            )
            
            return try await createContact(newContact)
            
        } catch {
            print("❌ Failed to import from native contact: \(error)")
            self.error = "Failed to import contact: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Refresh a linked contact from native Contacts app
    func refreshFromNativeContact(contactID: UUID) async throws -> ContactModel {
        return try await taskManager.execute(key: "refreshNativeContact_\(contactID)") {
            try await self.performRefreshFromNativeContact(contactID: contactID)
        }
    }
    
    private func performRefreshFromNativeContact(contactID: UUID) async throws -> ContactModel {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent contact
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactID }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            
            guard let persistentContact = existingContacts.first else {
                throw ContactServiceError.contactNotFound(contactID)
            }
            
            guard let nativeID = persistentContact.nativeContactID else {
                throw ContactServiceError.custom("Contact is not linked to native Contacts")
            }
            
            // Fetch from native contacts
            let nativeService = NativeContactService()
            guard let nativeData = try await nativeService.extractContactData(identifier: nativeID) else {
                // Native contact was deleted - unlink but keep the contact
                print("⚠️ Native contact deleted, unlinking: \(persistentContact.cachedName)")
                persistentContact.nativeContactID = nil
                persistentContact.lastSyncedFromNative = nil
                persistentContact.touch()
                try modelContext.save()
                
                throw ContactServiceError.custom("Native contact no longer exists")
            }
            
            // Update contact with fresh data
            persistentContact.cachedName = nativeData.fullName
            if let imageData = nativeData.imageData {
                persistentContact.avatarData = imageData
            }
            persistentContact.lastSyncedFromNative = Date()
            persistentContact.touch()
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = contacts.firstIndex(where: { $0.id == contactID }) {
                _ = persistentContact.addresses
                contacts[index] = ContactModel(from: persistentContact)
            }
            
            print("✅ Refreshed contact from native: \(persistentContact.cachedName)")
            
            _ = persistentContact.addresses
            return ContactModel(from: persistentContact)
            
        } catch {
            print("❌ Failed to refresh from native contact: \(error)")
            self.error = "Failed to refresh contact: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Unlink a contact from native Contacts (but keep the contact)
    func unlinkFromNativeContact(contactID: UUID) async throws {
        return try await taskManager.execute(key: "unlinkNativeContact_\(contactID)") {
            try await self.performUnlinkFromNativeContact(contactID: contactID)
        }
    }
    
    private func performUnlinkFromNativeContact(contactID: UUID) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent contact
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactID }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            
            guard let persistentContact = existingContacts.first else {
                throw ContactServiceError.contactNotFound(contactID)
            }
            
            guard persistentContact.nativeContactID != nil else {
                throw ContactServiceError.custom("Contact is not linked to native Contacts")
            }
            
            let contactName = persistentContact.cachedName
            
            // Clear native contact link
            persistentContact.nativeContactID = nil
            persistentContact.lastSyncedFromNative = nil
            persistentContact.touch()
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = contacts.firstIndex(where: { $0.id == contactID }) {
                _ = persistentContact.addresses
                contacts[index] = ContactModel(from: persistentContact)
            }
            
            print("✅ Unlinked contact from native: \(contactName)")
            
        } catch {
            print("❌ Failed to unlink from native contact: \(error)")
            self.error = "Failed to unlink contact: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Link an existing contact to a native Contact
    func linkToNativeContact(contactID: UUID, nativeContactData: ImportedContactData) async throws -> ContactModel {
        return try await taskManager.execute(key: "linkNativeContact_\(contactID)") {
            try await self.performLinkToNativeContact(contactID: contactID, nativeContactData: nativeContactData)
        }
    }
    
    private func performLinkToNativeContact(contactID: UUID, nativeContactData: ImportedContactData) async throws -> ContactModel {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent contact
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactID }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            
            guard let persistentContact = existingContacts.first else {
                throw ContactServiceError.contactNotFound(contactID)
            }
            
            // Validate contact is not already linked
            if persistentContact.nativeContactID != nil {
                throw ContactServiceError.custom("Contact is already linked to native Contacts")
            }
            
            // Check if the native contact is already linked to another contact
            let nativeID = nativeContactData.identifier
            let checkDescriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.nativeContactID == nativeID }
            )
            let linkedContacts = try modelContext.fetch(checkDescriptor)
            
            if !linkedContacts.isEmpty {
                throw ContactServiceError.custom("This native contact is already linked to another wallet contact")
            }
            
            let contactName = persistentContact.cachedName
            
            // Link to native contact (preserve local data, only establish link)
            persistentContact.nativeContactID = nativeContactData.identifier
            persistentContact.lastSyncedFromNative = Date()
            persistentContact.touch()
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = contacts.firstIndex(where: { $0.id == contactID }) {
                _ = persistentContact.addresses
                contacts[index] = ContactModel(from: persistentContact)
            }
            
            print("✅ Linked contact '\(contactName)' to native contact '\(nativeContactData.fullName)'")
            
            _ = persistentContact.addresses
            return ContactModel(from: persistentContact)
            
        } catch {
            print("❌ Failed to link to native contact: \(error)")
            self.error = "Failed to link contact: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Check if a native contact ID is already imported
    func isNativeContactImported(_ nativeID: String) async -> Bool {
        guard let modelContext = modelContext else {
            return false
        }
        
        do {
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.nativeContactID == nativeID }
            )
            let existingContacts = try modelContext.fetch(descriptor)
            return !existingContacts.isEmpty
        } catch {
            print("❌ Failed to check if native contact imported: \(error)")
            return false
        }
    }
}
