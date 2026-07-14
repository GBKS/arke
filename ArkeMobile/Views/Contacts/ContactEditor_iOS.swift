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
                Text("contacts_editor_title")
                Text("contacts_editor_placeholder")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(editingContact == nil ? "New Contact" : String(localized: "button_edit_contact"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("button_cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("button_save") {
                    // Implement save logic
                    if let contact = editingContact {
                        onSave(contact)
                    }
                }
            }
        }
    }
}
