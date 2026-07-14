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
                    title: "contacts_contact_type",
                    value: contact.contactType.displayName
                )
                
                DetailRow(
                    title: "contacts_added",
                    value: contact.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                
                if contact.updatedAt != contact.createdAt {
                    DetailRow(
                        title: "contacts_last_updated",
                        value: contact.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                
                DetailRow(
                    title: "contacts_contact_id",
                    value: contact.id.uuidString
                )
            }
        } label: {
            Text("label_details")
                .font(.headline)
                .fontWeight(.semibold)
        }
    }
}
