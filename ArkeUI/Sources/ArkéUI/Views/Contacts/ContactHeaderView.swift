//
//  ContactHeaderView.swift
//  ArkéUI
//
//  Created by Christoph on 11/13/25.
//  Moved into ArkéUI as a pure, previewable presentation view.
//

import SwiftUI

public struct ContactHeaderView: View {
    let contact: ContactModel

    public init(contact: ContactModel) {
        self.contact = contact
    }

    public var body: some View {
        HStack(spacing: 15) {
            ContactAvatarView(avatarData: contact.avatarData, size: 75)

            VStack(alignment: .leading, spacing: 8) {
                Text(contact.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(String(localized: "status_added", defaultValue: "Added \(contact.createdAt.formatted(date: .abbreviated, time: .omitted))", bundle: .module))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    ContactHeaderView(contact: .sampleAlice)
        .padding()
}
