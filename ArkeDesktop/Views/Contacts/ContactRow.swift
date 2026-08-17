//
//  ContactRow.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import ArkeUI

struct ContactRow: View {
    @Binding var selectedContact: ContactModel?
    
    let contact: ContactModel
    let onTransactionCountTap: ((ContactModel) -> Void)?
    let onSendTap: ((ContactModel) -> Void)?
    
    init(contact: ContactModel, onTransactionCountTap: ((ContactModel) -> Void)? = nil, onSendTap: ((ContactModel) -> Void)? = nil, selectedContact: Binding<ContactModel?>) {
        self.contact = contact
        self.onTransactionCountTap = onTransactionCountTap
        self.onSendTap = onSendTap
        self._selectedContact = selectedContact
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarData = contact.avatarData,
               let nsImage = NSImage(data: avatarData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                        )
            } else {
                // Default avatar with initials
                Circle()
                    .fill(Color.Arke.blue.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(contact.displayName.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                    }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                if let notes = contact.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 4) {
                    // Transaction statistics
                    if let transactionCount = contact.formattedTransactionCount {
                        Text(transactionCount)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Amount statistics in a horizontal layout
                    HStack(spacing: 12) {
                        if let sentAmount = contact.formattedSentAmount {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.primary)
                                    .font(.caption2)
                                Text(sentAmount)
                                    .foregroundColor(.primary)
                            }
                            .font(.caption2)
                        }
                        
                        if let receivedAmount = contact.formattedReceivedAmount {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.Arke.green)
                                    .font(.caption2)
                                Text(receivedAmount)
                                    .foregroundColor(.Arke.green)
                            }
                            .font(.caption2)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTransactionCountTap?(contact)
                }
                
                // Send button - only show if contact has a primary address
                if contact.primaryAddress != nil {
                    Button(action: {
                        onSendTap?(contact)
                    }) {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(ArkeIconButtonStyle(size: .small))
                    .help(String(format: String(localized: "help_send_to", defaultValue: "Send to %@"), contact.displayName))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(selectedContact == contact ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .cornerRadius(15)
        .onTapGesture {
            selectedContact = contact
        }
    }
}
