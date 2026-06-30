//
//  WalletManager+ContactAddresses.swift
//  Arké
//
//  Contact address operations
//  All operations delegate to ContactAddressService for validation and persistence
//

import Foundation
import ArkeUI

extension WalletManager {
    
    // MARK: - Contact Address Properties
    
    /// Check if contact address service is loading
    var isContactAddressLoading: Bool {
        contactAddressService.isLoading
    }
    
    /// Get contact address service error
    var contactAddressError: String? {
        contactAddressService.error
    }
    
    // MARK: - Contact Address Operations
    
    /// Validate and create a new address for a contact
    func validateAndCreateAddress(_ addressString: String, for contactId: UUID, label: String? = nil, isPrimary: Bool = false) async throws -> ContactAddressModel {
        return try await contactAddressService.validateAndCreateAddress(addressString, for: contactId, label: label, isPrimary: isPrimary)
    }
    
    /// Update an existing address with full model
    func updateAddress(_ addressModel: ContactAddressModel) async throws {
        try await contactAddressService.updateAddress(addressModel)
    }
    
    /// Delete an address
    func deleteAddress(_ addressId: UUID) async throws {
        try await contactAddressService.deleteAddress(addressId)
    }
    
    /// Get all addresses for a contact
    func getAddressesForContact(_ contactId: UUID) async -> [ContactAddressModel] {
        return await contactAddressService.loadAddressesForContact(contactId)
    }
    
    /// Validate an address format
    func validateAddress(_ addressString: String) -> Bool {
        return contactAddressService.validateAddress(addressString)
    }
    
    /// Parse a payment request and return detailed information
    func parsePaymentRequest(_ addressString: String) -> PaymentRequest? {
        return contactAddressService.parsePaymentRequest(addressString)
    }
    
    /// Set an address as primary for a contact
    func setPrimaryAddress(_ addressId: UUID, for contactId: UUID) async throws {
        try await contactAddressService.setPrimaryAddress(addressId, for: contactId)
    }
    
    /// Clear contact address service errors
    func clearContactAddressError() {
        contactAddressService.error = nil
    }
}
