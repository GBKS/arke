//
//  ContactPickerSheet.swift
//  Arké
//
//  Created by Assistant on 12/15/25.
//

import SwiftUI
import ArkeUI

/// A sheet for selecting a contact to send payment to
/// Filters contacts to only show those with addresses
struct ContactPickerSheet_iOS: View {
    let contacts: [ContactModel]
    let onSelectContact: (ContactModel) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    // Filter contacts to only show those with addresses
    private var contactsWithAddresses: [ContactModel] {
        contacts.filter { $0.hasAddresses }
    }
    
    // Filter based on search text
    private var filteredContacts: [ContactModel] {
        if searchText.isEmpty {
            return contactsWithAddresses
        } else {
            return contactsWithAddresses.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(searchText) ||
                contact.notes?.localizedCaseInsensitiveContains(searchText) ?? false ||
                contact.addresses.contains { address in
                    address.address.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    // Group contacts alphabetically
    private var groupedContacts: [(String, [ContactModel])] {
        let sorted = filteredContacts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        
        let grouped = Dictionary(grouping: sorted) { contact in
            let firstChar = contact.displayName.prefix(1).uppercased()
            return firstChar.isEmpty ? "#" : (firstChar.rangeOfCharacter(from: .letters) != nil ? firstChar : "#")
        }
        
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if contactsWithAddresses.isEmpty {
                    emptyStateView
                } else if filteredContacts.isEmpty {
                    noResultsView
                } else {
                    contactListView
                }
            }
            .navigationTitle("button_select_contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button_cancel") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "placeholder_search_contacts"))
        }
    }
    
    // MARK: - Contact List
    
    @ViewBuilder
    private var contactListView: some View {
        List {
            ForEach(groupedContacts, id: \.0) { section, contacts in
                Section {
                    ForEach(contacts) { contact in
                        ContactPickerRow_iOS(contact: contact) {
                            handleContactSelection(contact)
                        }
                    }
                } header: {
                    Text(section)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Empty States
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("contacts_empty_title", systemImage: "person.2.slash")
        } description: {
            Text(String(localized: "send_no_contacts_addresses", defaultValue: "You don't have any contacts with addresses yet.\n\nAdd addresses to your contacts to quickly send payments."))
        }
    }
    
    @ViewBuilder
    private var noResultsView: some View {
        ContentUnavailableView.search(text: searchText)
    }
    
    // MARK: - Actions
    
    private func handleContactSelection(_ contact: ContactModel) {
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        // Notify parent
        onSelectContact(contact)
        
        // Dismiss sheet
        dismiss()
    }
}

// MARK: - Contact Row

private struct ContactPickerRow_iOS: View {
    let contact: ContactModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar
                ContactAvatarView(
                    avatarData: contact.avatarData,
                    size: 44,
                    fallbackText: contact.cachedName
                )
                
                // Contact Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        // Address count and types
                        Text(contact.addressTypesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Show primary address if available
                        if let primaryAddress = contact.primaryAddress {
                            Text("symbol_bullet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            
                            Text(primaryAddress.label ?? primaryAddress.format.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
