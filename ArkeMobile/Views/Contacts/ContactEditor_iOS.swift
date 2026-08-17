//
//  ContactEditor_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct ContactEditor_iOS: View {
    let editingContact: ContactModel?
    let onSave: (ContactModel) -> Void
    let onCancel: () -> Void
    let onDelete: (ContactModel) -> Void
    
    @Environment(WalletManager.self) private var manager
    
    var body: some View {
        Form {
            Section {
                Text(String(localized: "contacts_editor_title", defaultValue: "Contact Editor"))
                Text(String(localized: "contacts_editor_placeholder", defaultValue: "Implement your contact editing form here"))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(editingContact == nil ? "New Contact" : String(localized: "button_edit_contact", defaultValue: "Edit Contact"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.buttonCancel, action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.buttonSave) {
                    // Implement save logic
                    if let contact = editingContact {
                        onSave(contact)
                    }
                }
            }
        }
    }
}
