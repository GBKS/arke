//
//  ContactService+Addresses.swift
//  Arké
//
//  Contact address cache management
//

import Foundation
import ArkeUI

extension ContactService {
    
    /// Update a contact's addresses in the local in-memory cache after address changes
    func updateContactAddresses(_ contactId: UUID, addresses: [ContactAddressModel]) {
        guard let contactIndex = contacts.firstIndex(where: { $0.id == contactId }) else { return }
        
        let updatedContact = ContactModel(
            id: contacts[contactIndex].id,
            cachedName: contacts[contactIndex].cachedName,
            notes: contacts[contactIndex].notes,
            avatarData: contacts[contactIndex].avatarData,
            createdAt: contacts[contactIndex].createdAt,
            updatedAt: Date(),
            contactType: contacts[contactIndex].contactType,  // Preserve contact type
            nativeContactID: contacts[contactIndex].nativeContactID,  // Preserve native contact link
            lastSyncedFromNative: contacts[contactIndex].lastSyncedFromNative,  // Preserve sync date
            transactionCount: contacts[contactIndex].transactionCount,
            sentAmount: contacts[contactIndex].sentAmount,
            receivedAmount: contacts[contactIndex].receivedAmount,
            addresses: addresses
        )
        
        contacts[contactIndex] = updatedContact
    }
}
