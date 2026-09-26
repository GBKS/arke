//
//  PersistentContact.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import ArkeUI
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
    
    // Live assignment rows for this contact, fetch-resolved like
    // PersistentTransaction.liveTagAssignments and for the same reason: the
    // cached `contactAssignments` array can keep listing rows a CloudKit
    // import has already deleted, and reading one of those instances traps
    // ("model instance was invalidated", 2026-09-23).
    var liveAssignments: [TransactionContactAssignment] {
        guard let modelContext else {
            return contactAssignments ?? []
        }

        let contactId = self.id
        let descriptor = FetchDescriptor<TransactionContactAssignment>(
            predicate: #Predicate { $0.contact?.id == contactId }
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // Get all transactions that have this contact (fetch-resolved)
    var associatedTransactions: [PersistentTransaction] {
        liveAssignments.compactMap { $0.transaction }
    }

    /// Addresses resolved through a fetch instead of the cached `addresses`
    /// relationship — same invalidation hazard as `associatedTransactions`.
    var liveAddresses: [PersistentContactAddress] {
        guard let modelContext else {
            return addresses ?? []
        }

        let contactId = self.id
        var descriptor = FetchDescriptor<PersistentContactAddress>(
            predicate: #Predicate { $0.contact?.id == contactId }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]

        return (try? modelContext.fetch(descriptor)) ?? []
    }


    // Count of associated transactions (fetch-resolved, so it can't disagree
    // with associatedTransactions when an import deleted rows under the
    // cached array)
    var transactionCount: Int {
        liveAssignments.count
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
    
    /// Get the primary address if one exists (fetch-resolved via
    /// `liveAddresses` — reading a cached address row's properties can trap
    /// mid-import)
    var primaryAddress: PersistentContactAddress? {
        liveAddresses.first { $0.isPrimary }
    }

    /// Get addresses by format
    func addresses(for format: AddressFormat) -> [PersistentContactAddress] {
        liveAddresses.filter { $0.format == format }
    }

    /// Get addresses compatible with a specific network
    func addresses(for networkConfig: NetworkConfig) -> [PersistentContactAddress] {
        liveAddresses.filter { $0.isCompatibleWith(networkConfig) }
    }

    /// Count of addresses (fetch-resolved)
    var addressCount: Int {
        liveAddresses.count
    }
}
