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
                if let contact = pendingMetadata?.contact {
                    ContactAvatarView(
                        avatarData: contact.avatarData,
                        size: 60,
                        height: 44,
                        fallbackText: contact.displayName
                    )
                } else {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 60, height: 44)
                        #if os(iOS)
                        .background(Color(.systemGray5))
                        #else
                        .background(Color(nsColor: .secondaryLabelColor))
                        #endif
                        .cornerRadius(22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pendingMetadata?.hasContact ?? false ? String(localized: "action_change_contact", defaultValue: "Change contact") : String(localized: "action_assign_contact", defaultValue: "Assign contact"))
            .accessibilityHint(String(localized: "accessibility_hint_assign_contact", defaultValue: "Opens contact selector"))
            
            // Tags button
            Button {
                showTagSelector = true
            } label: {
                if let firstTag = pendingMetadata?.associatedTags.first {
                    // Show the first selected tag's emoji and color
                    Text(firstTag.emoji)
                        .font(.title2)
                        .frame(width: 60, height: 44)
                        .background(firstTag.color.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(firstTag.color.opacity(0.75), lineWidth: 1)
                        )
                        .cornerRadius(22)
                } else {
                    // Default empty state
                    Image(systemName: "tag.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 60, height: 44)
                        #if os(iOS)
                        .background(Color(.systemGray5))
                        #else
                        .background(Color(nsColor: .secondaryLabelColor))
                        #endif
                        .cornerRadius(22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tagsAccessibilityLabel)
            .accessibilityHint(String(localized: "accessibility_hint_assign_tags", defaultValue: "Opens tag selector"))
            
            // Note button
            Button {
                showNoteEditor = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.title2)
                        .frame(width: 60, height: 44)
                        .foregroundStyle((pendingMetadata?.hasNotes ?? false) ? Color.Arke.green : .primary)
                        #if os(iOS)
                        .background((pendingMetadata?.hasNotes ?? false) ? Color.Arke.green.opacity(0.15) : Color(.systemGray5))
                        #else
                        .background((pendingMetadata?.hasNotes ?? false) ? Color.Arke.green.opacity(0.15) : Color(nsColor: .secondaryLabelColor))
                        #endif
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke((pendingMetadata?.hasNotes ?? false) ? Color.Arke.green : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pendingMetadata?.hasNotes ?? false ? String(localized: "action_change_note", defaultValue: "Change note") : String(localized: "action_assign_note", defaultValue: "Assign note"))
            .accessibilityHint(String(localized: "accessibility_hint_assign_note", defaultValue: "Opens note editor"))
            .accessibilityValue((pendingMetadata?.hasNotes ?? false) ? String(localized: "accessibility_value_note_present", defaultValue: "Note added") : "")
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showContactSelector) {
            NavigationStack {
                ContactSelectorSheet(
                    selectedContactId: $selectedContactId,
                    transactionId: nil,
                    onAssignContact: { contact in
                        await applyContactSelectionAsync(contact)
                    }
                )
                .navigationTitle(String(localized: "button_assign_contact", defaultValue: "Assign Contact"))
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
                TagSelectorSheet(
                    selectedTagIds: $selectedTagIds,
                    onCreateNewTag: { newTag in
                        await createNewTag(newTag)
                    }
                )
            }
            #if os(macOS)
            .frame(width: 500, height: 600)
            #endif
            .onDisappear {
                applyTagSelection()
            }
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
    
    // MARK: - Accessibility Helpers
    
    private var tagsAccessibilityLabel: String {
        guard let metadata = pendingMetadata else {
            return String(localized: "action_assign_tags", defaultValue: "Assign tags")
        }
        
        let tags = metadata.associatedTags
        if tags.isEmpty {
            return String(localized: "action_assign_tags", defaultValue: "Assign tags")
        } else if tags.count == 1 {
            return String(localized: "Change tags: \(tags[0].name)")
        } else {
            return String(localized: "Change tags: \(tags.count) tags selected")
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
    
    private func applyContactSelectionAsync(_ contact: ContactModel?) async {
        applyContactSelection()
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
    
    private func createNewTag(_ newTag: TagModel) async {
        do {
            let createdTag = try await walletManager.tagServiceForEnvironment.createTag(newTag)
            // Automatically select the newly created tag
            selectedTagIds.insert(createdTag.id)
        } catch {
            print("Failed to create tag: \(error)")
        }
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
