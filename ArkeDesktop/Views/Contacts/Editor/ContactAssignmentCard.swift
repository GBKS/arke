//
//  ContactAssignmentCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import ArkeUI

struct ContactAssignmentCard: View {
    let contact: ContactModel
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ContactAvatarView(avatarData: contact.avatarData, size: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let notes = contact.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text("contacts_assigned_to_this_transaction")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("action_remove") {
                onRemove()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.Arke.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.Arke.blue.opacity(0.3), lineWidth: 1)
        )
    }
}
