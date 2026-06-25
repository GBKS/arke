//
//  ContactHeaderView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct ContactHeaderView: View {
    let contact: ContactModel
    
    var body: some View {
        HStack(spacing: 15) {
            ContactAvatarView(avatarData: contact.avatarData, size: 75)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(contact.displayName)
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(String(localized: "status_added", defaultValue: "Added \(contact.createdAt.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
