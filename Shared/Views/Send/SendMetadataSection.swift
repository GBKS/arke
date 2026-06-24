//
//  SendMetadataSection.swift
//  Arké
//
//  Created for Phase 3b: Send Metadata Enhancement
//  Three icon buttons for assigning contact, tags, and note during send
//

import SwiftUI
import SwiftData
import ArkeUI

public struct SendMetadataSection: View {
    @Binding var pendingMetadata: PendingPaymentMetadata?
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    
    @State private var showContactSelector = false
    @State private var showTagSelector = false
    @State private var showNoteEditor = false
    
    // Local state for tracking selections
    @State private var selectedContactId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    
    public var body: some View {
        HStack(spacing: 20) {
            // Contact button
            Button {
                showContactSelector = true
            } label: {
                VStack(spacing: 4) {
                    iconView(
                        systemName: "person.circle.fill",
                        isFilled: pendingMetadata?.hasContact ?? false
                    )
                    Text("Contact")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Tags button
            Button {
                showTagSelector = true
            } label: {
                VStack(spacing: 4) {
                    iconView(
                        systemName: "tag.circle.fill",
                        isFilled: pendingMetadata?.hasTags ?? false
                    )
                    Text("Tags")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Note button
            Button {
                showNoteEditor = true
            } label: {
                VStack(spacing: 4) {
                    iconView(
                        systemName: "note.text",
                        isFilled: pendingMetadata?.hasNotes ?? false
                    )
                    Text("Note")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showContactSelector) {
            NavigationStack {
                contactSelectorContent
                    .navigationTitle("Assign Contact")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
            #if os(macOS)
            .frame(width: 500, height: 600)
            #endif
        }
        .sheet(isPresented: $showTagSelector) {
            NavigationStack {
                tagSelectorContent
                    .navigationTitle("Assign Tags")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
            #if os(macOS)
            .frame(width: 500, height: 600)
            #endif
        }
        .sheet(isPresented: $showNoteEditor) {
            SendNoteEditorSheet(
                note: Binding(
                    get: { pendingMetadata?.notes ?? "" },
                    set: { newNote in
                        updateNote(newNote)
                    }
                ),
                onDismiss: {
                    showNoteEditor = false
                }
            )
            #if os(macOS)
            .frame(width: 500, height: 400)
            #endif
        }
        .task {
            loadCurrentAssignments()
        }
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private func iconView(systemName: String, isFilled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 32))
            .foregroundColor(isFilled ? .Arke.gold : .secondary)
            .symbolRenderingMode(isFilled ? .multicolor : .monochrome)
    }
    
    // MARK: - Contact Selector Content
    
    @ViewBuilder
    private var contactSelectorContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                if walletManager.hasContacts {
                    ForEach(Array(walletManager.alphabeticalContacts.enumerated()), id: \.element.id) { index, contact in
                        VStack(spacing: 0) {
                            ContactChip_Selectable(
                                avatarData: contact.avatarData,
                                displayName: contact.displayName,
                                notes: contact.notes,
                                isSelected: Binding(
                                    get: { selectedContactId == contact.id },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedContactId = contact.id
                                        } else {
                                            selectedContactId = nil
                                        }
                                    }
                                )
                            )
                            .padding(.horizontal)
                            
                            if index < walletManager.alphabeticalContacts.count - 1 {
                                Divider()
                                    .padding(.leading, 25)
                                    .padding(.trailing, 25)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2.slash",
                        description: Text("Create a contact first to assign it to this payment")
                    )
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showContactSelector = false
                } label: {
                    Text("Cancel")
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    applyContactSelection()
                    showContactSelector = false
                } label: {
                    Text("Done")
                }
            }
        }
    }
    
    // MARK: - Tag Selector Content
    
    @ViewBuilder
    private var tagSelectorContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                if walletManager.hasTags {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(walletManager.tags) { tag in
                            TagChip_Selectable(
                                tag: tag.appearance,
                                isSelected: Binding(
                                    get: { selectedTagIds.contains(tag.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedTagIds.insert(tag.id)
                                        } else {
                                            selectedTagIds.remove(tag.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag.slash",
                        description: Text("Create a tag first to assign it to this payment")
                    )
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showTagSelector = false
                } label: {
                    Text("Cancel")
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    applyTagSelection()
                    showTagSelector = false
                } label: {
                    Text("Done")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentAssignments() {
        guard let metadata = pendingMetadata else { return }
        
        // Load contact assignment
        selectedContactId = metadata.contact?.id
        
        // Load tag assignments
        selectedTagIds = Set(metadata.associatedTags.compactMap { $0.id })
    }
    
    /// Find the transaction that matches this pending metadata (if it exists)
    private func findMatchedTransaction() -> PersistentTransaction? {
        guard let metadata = pendingMetadata,
              let txid = metadata.matchedTxid else {
            return nil
        }
        
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    private func applyContactSelection() {
        guard let metadata = pendingMetadata else { return }
        
        // Find the selected contact
        let selectedContact: PersistentContact?
        if let contactId = selectedContactId {
            let descriptor = FetchDescriptor<PersistentContact>(
                predicate: #Predicate { $0.id == contactId }
            )
            selectedContact = try? modelContext.fetch(descriptor).first
        } else {
            selectedContact = nil
        }
        
        // Apply to pending metadata
        metadata.contact = selectedContact
        
        // If transaction already exists, apply directly to it as well
        if let transaction = findMatchedTransaction() {
            // Remove existing contact assignments
            if let existingAssignments = transaction.contactAssignments {
                for assignment in existingAssignments {
                    modelContext.delete(assignment)
                }
            }
            
            // Add new contact assignment
            if let contact = selectedContact {
                let assignment = TransactionContactAssignment(
                    contact: contact,
                    transaction: transaction
                )
                modelContext.insert(assignment)
            }
        } else {
            // Transaction doesn't exist yet, mark metadata as modified for re-application
            metadata.markAsModified()
        }
        
        // Save changes
        try? modelContext.save()
    }
    
    private func applyTagSelection() {
        guard let metadata = pendingMetadata else { return }
        
        // Fetch all selected tags
        var selectedTags: [PersistentTag] = []
        for tagId in selectedTagIds {
            let descriptor = FetchDescriptor<PersistentTag>(
                predicate: #Predicate { $0.id == tagId }
            )
            if let persistentTag = try? modelContext.fetch(descriptor).first {
                selectedTags.append(persistentTag)
            }
        }
        
        // Apply to pending metadata
        // Remove all existing tag assignments
        if let existingAssignments = metadata.tagAssignments {
            for assignment in existingAssignments {
                modelContext.delete(assignment)
            }
        }
        metadata.tagAssignments = []
        
        // Add new tag assignments to pending metadata
        for tag in selectedTags {
            let assignment = PendingTagAssignment(
                tag: tag,
                pendingMetadata: metadata
            )
            modelContext.insert(assignment)
        }
        
        // If transaction already exists, apply directly to it as well
        if let transaction = findMatchedTransaction() {
            // Remove existing tag assignments from transaction
            if let existingTransactionTags = transaction.tagAssignments {
                for assignment in existingTransactionTags {
                    modelContext.delete(assignment)
                }
            }
            
            // Add new tag assignments to transaction
            for tag in selectedTags {
                let assignment = TransactionTagAssignment(
                    tag: tag,
                    transaction: transaction
                )
                modelContext.insert(assignment)
            }
        } else {
            // Transaction doesn't exist yet, mark metadata as modified for re-application
            metadata.markAsModified()
        }
        
        // Save changes
        try? modelContext.save()
    }
    
    private func updateNote(_ newNote: String) {
        guard let metadata = pendingMetadata else { return }
        
        // Determine the final note value
        let finalNote: String?
        if newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalNote = nil
        } else {
            finalNote = newNote
        }
        
        // Apply to pending metadata
        metadata.notes = finalNote
        
        // If transaction already exists, apply directly to it as well
        if let transaction = findMatchedTransaction() {
            transaction.notes = finalNote
        } else {
            // Transaction doesn't exist yet, mark metadata as modified for re-application
            metadata.markAsModified()
        }
        
        // Save changes
        try? modelContext.save()
    }
}
