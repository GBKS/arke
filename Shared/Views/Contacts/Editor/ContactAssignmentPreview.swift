//
//  ContactAssignmentPreview.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/18/25.
//

import SwiftUI
import ArkeUI

struct ContactAssignmentPreview: View {
    let currentContact: ContactModel?
    let pendingContact: ContactModel?
    let previewAddress: String?
    let previewAutoAssignCount: Int
    
    var body: some View {
        Group {
            if let pendingContact = pendingContact,
               pendingContact.id != currentContact?.id {
                assignmentChangePreview(pendingContact: pendingContact)
            } else if pendingContact == nil && currentContact != nil {
                removalPreview(currentContact: currentContact!)
            }
        }
    }
    
    // MARK: - Subviews
    
    private func assignmentChangePreview(pendingContact: ContactModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "label_this_will", defaultValue: "This will"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                if let current = currentContact {
                    Label("Replace '\(current.displayName)' with '\(pendingContact.displayName)'",
                          systemImage: "arrow.left.arrow.right.circle")
                } else {
                    Label(String(localized: "activity_assign_contact", defaultValue: "Assign '\(pendingContact.displayName)' to this transaction"),
                          systemImage: "checkmark.circle")
                }
                
                if let address = previewAddress {
                    Label(String(localized: "action_save_address_contact", defaultValue: "Save address \(shortAddress(address)) to contact"),
                          systemImage: "plus.circle")
                }
                
                if previewAutoAssignCount > 0 {
                    Label("contacts_auto_assign_preview \(previewAutoAssignCount)",
                          systemImage: "arrow.triangle.branch")
                        .foregroundColor(.Arke.orange)
                }
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.leading, 15)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Arke.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.bottom, 8)
    }
    
    private func removalPreview(currentContact: ContactModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "label_this_will", defaultValue: "This will"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "activity_remove_contact", defaultValue: "Remove '\(currentContact.displayName)' from this transaction only"),
                      systemImage: "xmark.circle")
                    .foregroundColor(.Arke.orange)
                
                // Show info about other transactions if they exist
                if previewAutoAssignCount > 0 {
                    Label("contacts_auto_assign_remain \(previewAutoAssignCount)",
                          systemImage: "info.circle")
                        .foregroundColor(.secondary)
                }
                
                Label(String(localized: "contacts_address_stay", defaultValue: "The address will stay in '\(currentContact.displayName)'s contact card"),
                      systemImage: "info.circle")
                    .foregroundColor(.secondary)
            }
            .font(.callout)
            .padding(.leading, 15)
        }
        .padding()
        .background(Color.Arke.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    
    private func shortAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }
}
