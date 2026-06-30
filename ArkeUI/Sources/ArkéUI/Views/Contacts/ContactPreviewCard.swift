//
//  ContactPreviewCard.swift
//  ArkéUI
//
//  Created by Assistant on 11/04/25.
//  Moved into ArkéUI as a pure, previewable presentation view.
//

import SwiftUI

public struct ContactPreviewCard: View {
    let contact: ContactModel
    let isEmpty: Bool

    public init(contact: ContactModel, isEmpty: Bool = false) {
        self.contact = contact
        self.isEmpty = isEmpty
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("label_preview", bundle: .module)
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Avatar
                ContactAvatarView(avatarData: contact.avatarData, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(contact.displayName)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.leading)

                    // Notes preview
                    if let notes = contact.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ContactPreviewCard(contact: .sampleAlice)
        ContactPreviewCard(contact: .sampleBob, isEmpty: true)
    }
    .padding()
}
