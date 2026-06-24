//
//  PersistentContact.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import SwiftData

@Model
final class PersistentContact {
    var id: UUID = UUID()  // Default for CloudKit, removed .unique constraint
    var cachedName: String = ""  // Default for CloudKit
    var notes: String?
    var avatarData: Data?
    var createdAt: Date = Date()  // Default for CloudKit
    var updatedAt: Date = Date()  // Default for CloudKit
    var contactType: String = ContactType.standard.rawValue  // Default for CloudKit - stored as String for CloudKit compatibility
    
    // Native contact integration
    var nativeContactID: String?           // CNContact.identifier for linked native contacts
    var lastSyncedFromNative: Date?        // When we last imported/refreshed from native contact
    
    // Relationship to contact assignments (not direct to transactions for better control)
    // MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \TransactionContactAssignment.contact)
    var contactAssignments: [TransactionContactAssignment]? = []
    
    // Relationship to addresses - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade)
    var addresses: [PersistentContactAddress]? = []
    
    // Relationship to pending payment metadata - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade)
    var pendingPaymentMetadata: [PendingPaymentMetadata]? = []
    
    init(id: UUID = UUID(), cachedName: String, notes: String? = nil, avatarData: Data? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), contactType: ContactType = .standard, nativeContactID: String? = nil, lastSyncedFromNative: Date? = nil) {
        self.id = id
        self.cachedName = cachedName
        self.notes = notes
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contactType = contactType.rawValue
        self.nativeContactID = nativeContactID
        self.lastSyncedFromNative = lastSyncedFromNative
    }
    
    // Type-safe computed property for contactType
    var type: ContactType {
        get { ContactType(rawValue: contactType) ?? .standard }
        set { contactType = newValue.rawValue }
    }
    
    // Display name (just the cached name for now)
    var displayName: String {
        cachedName.isEmpty ? "Unknown Contact" : cachedName
    }
    
    // Check if this contact is linked to a native contact
    var isLinkedToNativeContact: Bool {
        nativeContactID != nil
    }
    
    // Get all transactions that have this contact
    var associatedTransactions: [PersistentTransaction] {
        (contactAssignments ?? []).compactMap { $0.transaction }
    }
    
    // Count of associated transactions
    var transactionCount: Int {
        contactAssignments?.count ?? 0
    }
    
    // Total amount (net: received - sent)
    var totalTransactionAmount: Int {
        let sent = sentAmount
        let received = receivedAmount
        return received - sent
    }
    
    // Sum of sent transaction amounts
    var sentAmount: Int {
        associatedTransactions
            .filter { $0.type == "sent" }
            .reduce(0) { $0 + $1.amount }
    }
    
    // Sum of received transaction amounts
    var receivedAmount: Int {
        associatedTransactions
            .filter { $0.type == "received" }
            .reduce(0) { $0 + $1.amount }
    }
    
    // Helper method to update the updatedAt timestamp
    func touch() {
        updatedAt = Date()
    }
    
    // MARK: - Address Management
    
    /// Get the primary address if one exists
    var primaryAddress: PersistentContactAddress? {
        addresses?.first { $0.isPrimary }
    }
    
    /// Get addresses by format
    func addresses(for format: AddressFormat) -> [PersistentContactAddress] {
        (addresses ?? []).filter { $0.format == format }
    }
    
    /// Get addresses compatible with a specific network
    func addresses(for networkConfig: NetworkConfig) -> [PersistentContactAddress] {
        (addresses ?? []).filter { $0.isCompatibleWith(networkConfig) }
    }
    
    /// Count of addresses
    var addressCount: Int {
        addresses?.count ?? 0
    }
}
