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
            transactionCount: persistentContact.transactionCount,
            sentAmount: persistentContact.sentAmount,
            receivedAmount: persistentContact.receivedAmount,
            addresses: (persistentContact.addresses ?? []).map { ContactAddressModel(from: $0) }
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
