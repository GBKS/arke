//
//  ContactInfoBanner.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/7/25.
//

import SwiftUI
import ArkeUI

struct ContactInfoBanner: View {
    let contact: ContactModel
    let onClear: () -> Void
    let onViewContact: () -> Void
    
    init(contact: ContactModel, onClear: @escaping () -> Void, onViewContact: @escaping () -> Void) {
        self.contact = contact
        self.onClear = onClear
        self.onViewContact = onViewContact
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onViewContact) {
                ContactAvatarView(avatarData: contact.avatarData, size: 48)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "send_sending_to", defaultValue: "Sending to"))
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                Button(action: onViewContact) {
                    Text(contact.displayName)
                        .font(.title2)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                #endif
            }
            
            Spacer()
            
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.actionClearContact)
        }
    }
}
