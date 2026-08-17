//
//  ContactDetailsDisclosure.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct ContactDetailsDisclosure: View {
    let contact: ContactModel
    let onRefreshFromNativeContact: (() -> Void)?
    let onUnlinkNativeContact: (() -> Void)?
    let onLinkNativeContact: (() -> Void)?
    
    var body: some View {
        DisclosureGroup {
            VStack(spacing: 12) {
                NativeContactLinkDetail(
                    contact: contact,
                    onRefresh: onRefreshFromNativeContact ?? {},
                    onUnlink: onUnlinkNativeContact ?? {},
                    onLink: onLinkNativeContact ?? {}
                )
                .padding(.top, 12)
                
                Divider()
                    .padding(.vertical, 4)
                
                DetailRow(
                    title: String(localized: "contacts_contact_type", defaultValue: "Contact Type"),
                    value: contact.contactType.displayName
                )
                
                DetailRow(
                    title: String(localized: "contacts_added", defaultValue: "Added"),
                    value: contact.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                
                if contact.updatedAt != contact.createdAt {
                    DetailRow(
                        title: String(localized: "contacts_last_updated", defaultValue: "Last Updated"),
                        value: contact.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                
                DetailRow(
                    title: String(localized: "contacts_contact_id", defaultValue: "Contact ID"),
                    value: contact.id.uuidString
                )
            }
        } label: {
            Text(L10n.labelDetails)
                .font(.headline)
                .fontWeight(.semibold)
        }
    }
}
