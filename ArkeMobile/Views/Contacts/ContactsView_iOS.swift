//
//  ContactsView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/4/25.
//

import SwiftUI
import UIKit
import ArkeUI

// MARK: - iOS Contact Management

/// Unified contacts view that handles both selection and management
/// Presents as a sheet with search, add, edit, delete, and send functionality
struct ContactsView_iOS: View {
    /// Called when user selects a contact to send to
    let onSelectContact: (ContactModel, ContactAddressModel) -> Void
    /// Called when user wants to view activity filtered by a contact
    let onNavigateToActivity: ((ContactModel?) -> Void)?
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: ContactsViewModel?
    @State private var showingContactDetail: ContactModel?
    @State private var showStatistics = false
    
    init(
        onSelectContact: @escaping (ContactModel, ContactAddressModel) -> Void,
        onNavigateToActivity: ((ContactModel?) -> Void)? = nil
    ) {
        self.onSelectContact = onSelectContact
        self.onNavigateToActivity = onNavigateToActivity
    }
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        await initializeViewModel()
                    }
            }
        }
    }
    
    private func initializeViewModel() async {
        let vm = ContactsViewModel(walletManager: walletManager)
        await vm.loadContactsWithStatistics()
        viewModel = vm
    }
}

// MARK: - Main Content

extension ContactsView_iOS {
    @ViewBuilder
    private func contentView(viewModel: ContactsViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        NavigationStack {
            Group {
                if viewModel.filteredContacts.isEmpty && !viewModel.searchText.isEmpty {
                    noSearchResultsView(viewModel: viewModel)
                } else if viewModel.contacts.isEmpty {
                    emptyStateView(viewModel: viewModel)
                } else {
                    contactListView(viewModel: viewModel)
                }
            }
            .navigationTitle(L10n.contactsTitle)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: L10n.placeholderSearchContacts)
            .toolbar {
                toolbarContent(viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadContactsWithStatistics()
            }
            .sheet(isPresented: $viewModel.showingNewContactEditor) {
                contactEditorSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.editingContact) { contact in
                contactEditorSheet(viewModel: viewModel, editing: contact)
            }
            .navigationDestination(item: $showingContactDetail) { contact in
                contactDetailView(contact: contact, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Contact List

extension ContactsView_iOS {
    @ViewBuilder
    private func contactListView(viewModel: ContactsViewModel) -> some View {
        List {
            ForEach(viewModel.filteredContacts) { contact in
                contactRowButton(contact: contact)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    @ViewBuilder
    private func contactRowButton(contact: ContactModel) -> some View {
        let button = Button {
            // Tap row = navigate to detail
            showingContactDetail = contact
        } label: {
            ContactRow_iOS(
                contact: contact,
                showStatistics: showStatistics,
                sendButtonStyle: .icon,
                onSendTap: {
                    handleQuickSend(contact: contact)
                }
            )
        }
        .buttonStyle(.plain)
        
        if contact.contactType.canBeDeleted {
            button
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeActionsForContact(contact)
                }
        } else {
            button
        }
    }
    
    @ViewBuilder
    private func swipeActionsForContact(_ contact: ContactModel) -> some View {
        Button(role: .destructive) {
            Task {
                guard let viewModel else { return }
                await viewModel.deleteContact(contact)
            }
        } label: {
            Label(L10n.buttonDelete, systemImage: "trash")
        }
        
        Button {
            viewModel?.showEditContactEditor(for: contact)
        } label: {
            Label(L10n.buttonEdit, systemImage: "paintbrush.pointed.fill")
        }
        .tint(.Arke.blue)
    }
}

// MARK: - Actions

extension ContactsView_iOS {
    private func handleQuickSend(contact: ContactModel) {
        guard let primaryAddress = contact.primaryAddress else {
            print("⚠️ [ContactsView_iOS] No primary address for contact: \(contact.displayName)")
            return
        }
        
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        print("📤 [ContactsView_iOS] Quick send to \(contact.displayName) at \(primaryAddress.address)")
        
        onSelectContact(contact, primaryAddress)
        dismiss()
    }
}

// MARK: - Toolbar

extension ContactsView_iOS {
    @ToolbarContentBuilder
    private func toolbarContent(viewModel: ContactsViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation {
                    showStatistics.toggle()
                }
            } label: {
                Image(systemName: showStatistics ? "chart.bar.fill" : "chart.bar")
            }
            .help(String(localized: "action_toggle_statistics", defaultValue: "Toggle Statistics"))
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button {
                print("🔵 [ContactsView_iOS.toolbar] Plus button tapped - calling showNewContactEditor()")
                viewModel.showNewContactEditor()
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

// MARK: - Empty States

extension ContactsView_iOS {
    @ViewBuilder
    private func emptyStateView(viewModel: ContactsViewModel) -> some View {
        ContentUnavailableView {
            Label(String(localized: "contacts_empty_title", defaultValue: "No Contacts"), systemImage: "person.2.circle")
        } description: {
            Text(String(localized: "contacts_empty_help", defaultValue: "Add contacts to organize your transactions and make sending easier"))
        } actions: {
            Button(String(localized: "contacts_create_first", defaultValue: "Create Your First Contact")) {
                viewModel.showNewContactEditor()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    @ViewBuilder
    private func noSearchResultsView(viewModel: ContactsViewModel) -> some View {
        ContentUnavailableView.search(text: viewModel.searchText)
    }
}

// MARK: - Sheets

extension ContactsView_iOS {
    @ViewBuilder
    private func contactEditorSheet(
        viewModel: ContactsViewModel,
        editing contact: ContactModel? = nil
    ) -> some View {
        NavigationStack {
            ContactEditor(
                editingContact: contact,
                onSave: { updatedContact in
                    Task {
                        if contact != nil {
                            await viewModel.updateContact(updatedContact)
                            viewModel.hideEditContactEditor()
                        } else {
                            await viewModel.createNewContact(updatedContact)
                            viewModel.hideNewContactEditor()
                        }
                    }
                },
                onCancel: {
                    if contact != nil {
                        viewModel.hideEditContactEditor()
                    } else {
                        viewModel.hideNewContactEditor()
                    }
                }
            )
            .environment(walletManager.contactServiceForEnvironment)
        }
    }
    
    @ViewBuilder
    private func contactDetailView(
        contact: ContactModel,
        viewModel: ContactsViewModel
    ) -> some View {
        // `contact` is the navigation snapshot taken when the row was tapped; resolve
        // the live model by id so edits saved while this screen is visible render
        // immediately and a follow-up edit starts from current values.
        let currentContact = viewModel.contacts.first(where: { $0.id == contact.id }) ?? contact
        ContactDetailView_iOS(
            contact: currentContact,
            onSendToAddress: { address in
                print("📤 [ContactsView_iOS] Send to specific address: \(address.address)")
                onSelectContact(currentContact, address)
                dismiss()
            },
            onEdit: {
                viewModel.showEditContactEditor(for: currentContact)
            },
            onDelete: {
                Task {
                    await viewModel.deleteContact(currentContact)
                    showingContactDetail = nil
                }
            },
            onNavigateToActivity: { contact in
                if let contact {
                    print("📊 [ContactsView_iOS] Navigate to activity for: \(contact.displayName)")
                } else {
                    print("📊 [ContactsView_iOS] Navigate to activity (no filter)")
                }
                
                // Dismiss the contact detail view and the contacts sheet
                showingContactDetail = nil
                dismiss()
                
                // Small delay to ensure dismissal completes before navigation
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    onNavigateToActivity?(contact)
                }
            }
        )
    }
}
