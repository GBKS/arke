//
//  ContactModel+Persistence.swift
//  Ark wallet prototype
//
//  The `ContactModel` value type itself now lives in the ArkéUI package as a
//  pure, previewable presentation model. This file holds the app-side bridging
//  between that value type and the SwiftData `PersistentContact` store, plus the
//  `NetworkConfig`-based address helper, kept here so the model stays free of
//  SwiftData and remains previewable in isolation.
//

import Foundation
import ArkeUI

extension ContactModel {
    /// Initialize from persistent contact
    init(from persistentContact: PersistentContact) {
        // One resolution for the count and both amounts: each of those
        // aggregates runs its own fetch now that they no longer walk cached
        // relationships (see PersistentContact.associatedTransactions).
        let transactions = persistentContact.associatedTransactions
        let sent = transactions.filter { $0.type == "sent" }.reduce(0) { $0 + $1.amount }
        let received = transactions.filter { $0.type == "received" }.reduce(0) { $0 + $1.amount }

        self.init(
            id: persistentContact.id,
            cachedName: persistentContact.cachedName,
            notes: persistentContact.notes,
            avatarData: persistentContact.avatarData,
            createdAt: persistentContact.createdAt,
            updatedAt: persistentContact.updatedAt,
            contactType: persistentContact.type,
            nativeContactID: persistentContact.nativeContactID,
            lastSyncedFromNative: persistentContact.lastSyncedFromNative,
            transactionCount: transactions.count,
            sentAmount: sent,
            receivedAmount: received,
            addresses: persistentContact.liveAddresses.map { ContactAddressModel(from: $0) }
        )
    }

    /// Row-weight conversion: identity + display fields + addresses (one
    /// fetch). The aggregate fields stay nil — they are Optional on
    /// ContactModel and every consumer nil-guards (formattedTransactionCount
    /// etc.). Computing them walks every one of the contact's transactions,
    /// which made bridging a transaction list O(M²) per frequent contact and
    /// turned each refresh into thousands of main-actor fetches (2026-09-24
    /// review finding). Use the full `init(from:)` only on contact-detail and
    /// statistics surfaces, where the aggregates are the point.
    init(rowFrom persistentContact: PersistentContact) {
        self.init(
            id: persistentContact.id,
            cachedName: persistentContact.cachedName,
            notes: persistentContact.notes,
            avatarData: persistentContact.avatarData,
            createdAt: persistentContact.createdAt,
            updatedAt: persistentContact.updatedAt,
            contactType: persistentContact.type,
            nativeContactID: persistentContact.nativeContactID,
            lastSyncedFromNative: persistentContact.lastSyncedFromNative,
            transactionCount: nil,
            sentAmount: nil,
            receivedAmount: nil,
            addresses: persistentContact.liveAddresses.map { ContactAddressModel(from: $0) }
        )
    }

    /// Convert to persistent model
    func toPersistentContact() -> PersistentContact {
        let persistentContact = PersistentContact(
            id: self.id,
            cachedName: self.cachedName,
            notes: self.notes,
            avatarData: self.avatarData,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            contactType: self.contactType,
            nativeContactID: self.nativeContactID,
            lastSyncedFromNative: self.lastSyncedFromNative
        )

        // Note: Addresses should be managed separately through the ContactAddressService
        // to avoid complex relationship management during contact creation

        return persistentContact
    }

    /// Get addresses compatible with a specific network configuration
    func addressesForNetwork(_ networkConfig: NetworkConfig) -> [ContactAddressModel] {
        addresses.filter { $0.isCompatibleWith(networkConfig) }
    }
}
