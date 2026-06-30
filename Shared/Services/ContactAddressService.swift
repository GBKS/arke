//
//  ContactAddressService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/05/25.
//

import Foundation
import ArkeUI
import SwiftUI
import SwiftData

/// Service responsible for managing contact address operations
@MainActor
@Observable
class ContactAddressService {
    
    // MARK: - Published Properties
    
    /// Error message for address operations
    var error: String?
    
    /// Loading state for address operations
    var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    private let taskManager: TaskDeduplicationManager
    private var modelContext: ModelContext?
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
    }
    
    // MARK: - SwiftData Integration
    
    /// Set the model context for persistence operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Address CRUD Operations
    
    /// Validate and create a new address for a contact
    func validateAndCreateAddress(
        _ addressString: String,
        for contactId: UUID,
        label: String? = nil,
        isPrimary: Bool = false
    ) async throws -> ContactAddressModel {
        
        return try await taskManager.execute(key: "createAddress_\(contactId)_\(addressString.hash)") {
            try await self.performValidateAndCreateAddress(addressString, contactId: contactId, label: label, isPrimary: isPrimary)
        }
    }
    
    private func performValidateAndCreateAddress(
        _ addressString: String,
        contactId: UUID,
        label: String?,
        isPrimary: Bool
    ) async throws -> ContactAddressModel {
        
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Use AddressValidator to parse and validate
        guard let paymentRequest = AddressValidator.parsePaymentRequest(addressString),
              let primaryDestination = paymentRequest.primaryDestination else {
            throw ContactServiceError.invalidAddress(addressString)
        }
        
        do {
            // Check if this exact address already exists for this contact
            let normalizedAddressString = addressString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let existingDescriptor = FetchDescriptor<PersistentContactAddress>(
                predicate: #Predicate<PersistentContactAddress> { address in
                    address.normalizedAddress == normalizedAddressString &&
                    address.contact?.id == contactId
                }
            )
            let existingAddresses = try modelContext.fetch(existingDescriptor)
            
            if !existingAddresses.isEmpty {
                throw ContactServiceError.duplicateAddress(addressString)
            }
            
            // Find the contact
            let contactDescriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactId }
            )
            let contacts = try modelContext.fetch(contactDescriptor)
            guard let contact = contacts.first else {
                throw ContactServiceError.contactNotFound(contactId)
            }
            
            // If setting as primary, remove primary status from other addresses
            if isPrimary {
                if let addresses = contact.addresses {
                    for existingAddress in addresses {
                        existingAddress.isPrimary = false
                    }
                }
            }
            
            // Create the address model from primary destination
            let addressModel = ContactAddressModel(
                from: primaryDestination,
                contactId: contactId,
                label: label,
                isPrimary: isPrimary
            )
            
            // Create persistent address
            let persistentAddress = addressModel.toPersistentAddress()
            persistentAddress.contact = contact
            modelContext.insert(persistentAddress)
            
            // Update contact timestamp
            contact.touch()
            
            // Save changes
            try modelContext.save()
            
            print("✅ Created address for contact \(contact.cachedName): \(addressModel.shortAddress)")
            return addressModel
            
        } catch {
            print("❌ Failed to create address: \(error)")
            self.error = "Failed to create address: \(error)"
            throw error
        }
    }
    
    /// Update an existing address
    func updateAddress(_ updatedAddress: ContactAddressModel) async throws {
        return try await taskManager.execute(key: "updateAddress_\(updatedAddress.id)") {
            try await self.performUpdateAddress(updatedAddress)
        }
    }
    
    private func performUpdateAddress(_ updatedAddress: ContactAddressModel) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent address
            let descriptor = FetchDescriptor<PersistentContactAddress>(
                predicate: #Predicate<PersistentContactAddress> { $0.id == updatedAddress.id }
            )
            let existingAddresses = try modelContext.fetch(descriptor)
            
            guard let persistentAddress = existingAddresses.first else {
                throw ContactServiceError.addressNotFound(updatedAddress.id)
            }
            
            // If setting as primary, remove primary status from other addresses for this contact
            if updatedAddress.isPrimary && !persistentAddress.isPrimary {
                if let contact = persistentAddress.contact,
                   let addresses = contact.addresses {
                    for otherAddress in addresses where otherAddress.id != updatedAddress.id {
                        otherAddress.isPrimary = false
                    }
                }
            }
            
            // Update properties
            persistentAddress.label = updatedAddress.label
            persistentAddress.isPrimary = updatedAddress.isPrimary
            persistentAddress.touch()
            
            // Update contact timestamp
            persistentAddress.contact?.touch()
            
            // Save changes
            try modelContext.save()
            
            print("✅ Updated address: \(updatedAddress.shortAddress)")
            
        } catch {
            print("❌ Failed to update address: \(error)")
            self.error = "Failed to update address: \(error)"
            throw error
        }
    }
    
    /// Delete an address
    func deleteAddress(_ addressId: UUID) async throws {
        return try await taskManager.execute(key: "deleteAddress_\(addressId)") {
            try await self.performDeleteAddress(addressId)
        }
    }
    
    private func performDeleteAddress(_ addressId: UUID) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find the address
            let descriptor = FetchDescriptor<PersistentContactAddress>(
                predicate: #Predicate<PersistentContactAddress> { $0.id == addressId }
            )
            let addresses = try modelContext.fetch(descriptor)
            
            guard let address = addresses.first else {
                throw ContactServiceError.addressNotFound(addressId)
            }
            
            let contactName = address.contact?.cachedName ?? "Unknown"
            let shortAddress = address.shortAddress
            
            // Update contact timestamp
            address.contact?.touch()
            
            // Delete the address
            modelContext.delete(address)
            
            // Save changes
            try modelContext.save()
            
            print("✅ Deleted address from contact \(contactName): \(shortAddress)")
            
        } catch {
            print("❌ Failed to delete address: \(error)")
            self.error = "Failed to delete address: \(error)"
            throw error
        }
    }
    
    /// Set an address as primary (and unset others for the same contact)
    func setPrimaryAddress(_ addressId: UUID, for contactId: UUID) async throws {
        return try await taskManager.execute(key: "setPrimary_\(addressId)_\(contactId)") {
            try await self.performSetPrimaryAddress(addressId, contactId: contactId)
        }
    }
    
    private func performSetPrimaryAddress(_ addressId: UUID, contactId: UUID) async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find the contact
            let contactDescriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate<PersistentContact> { $0.id == contactId }
            )
            let contacts = try modelContext.fetch(contactDescriptor)
            guard let contact = contacts.first else {
                throw ContactServiceError.contactNotFound(contactId)
            }
            
            // Find the target address
            guard let targetAddress = contact.addresses?.first(where: { $0.id == addressId }) else {
                throw ContactServiceError.addressNotFound(addressId)
            }
            
            // Remove primary status from all addresses for this contact
            if let addresses = contact.addresses {
                for address in addresses {
                    address.isPrimary = false
                }
            }
            
            // Set the target address as primary
            targetAddress.isPrimary = true
            targetAddress.touch()
            contact.touch()
            
            // Save changes
            try modelContext.save()
            
            print("✅ Set primary address for contact \(contact.cachedName): \(targetAddress.shortAddress)")
            
        } catch {
            print("❌ Failed to set primary address: \(error)")
            self.error = "Failed to set primary address: \(error)"
            throw error
        }
    }
    
    /// Load addresses for a specific contact
    func loadAddressesForContact(_ contactId: UUID) async -> [ContactAddressModel] {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading addresses")
            return []
        }
        
        do {
            let descriptor = FetchDescriptor<PersistentContactAddress>(
                predicate: #Predicate<PersistentContactAddress> { 
                    $0.contact?.id == contactId 
                }
            )
            let persistentAddresses = try modelContext.fetch(descriptor)
            
            // Sort in Swift since SwiftData sorting has limitations
            let sortedAddresses = persistentAddresses.sorted { lhs, rhs in
                // Primary addresses first
                if lhs.isPrimary != rhs.isPrimary {
                    return lhs.isPrimary
                }
                // Then by creation date
                return lhs.createdAt < rhs.createdAt
            }
            
            return sortedAddresses.map { ContactAddressModel(from: $0) }
            
        } catch {
            print("❌ Failed to load addresses for contact: \(error)")
            self.error = "Failed to load addresses: \(error)"
            return []
        }
    }
    
    // MARK: - Address Validation
    
    /// Check if a payment request is valid
    func validateAddress(_ addressString: String) -> Bool {
        return AddressValidator.isValidPaymentRequest(addressString)
    }
    
    /// Check if a payment request is valid for a specific network
    func validateAddress(_ addressString: String, for networkConfig: NetworkConfig) -> Bool {
        return AddressValidator.isValidPaymentRequest(addressString, for: networkConfig)
    }
    
    /// Parse a payment request and return detailed information
    func parsePaymentRequest(_ addressString: String) -> PaymentRequest? {
        return AddressValidator.parsePaymentRequest(addressString)
    }
    
    /// Normalize an address string for comparison
    func normalizeAddress(_ address: String) -> String {
        return address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    // MARK: - Bulk Operations
    
    /// Import multiple addresses for a contact
    func importAddresses(_ addressStrings: [String], for contactId: UUID, baseLabel: String? = nil) async throws -> [ContactAddressModel] {
        var createdAddresses: [ContactAddressModel] = []
        
        for (index, addressString) in addressStrings.enumerated() {
            do {
                let label = baseLabel.map { "\($0) \(index + 1)" }
                let address = try await validateAndCreateAddress(
                    addressString,
                    for: contactId,
                    label: label,
                    isPrimary: index == 0 && createdAddresses.isEmpty
                )
                createdAddresses.append(address)
            } catch {
                print("⚠️ Failed to import address \(addressString): \(error)")
                // Continue with other addresses
            }
        }
        
        return createdAddresses
    }
}