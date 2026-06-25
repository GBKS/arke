//
//  ContactsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI

struct ContactsView: View {
    @Environment(WalletManager.self) private var walletManager
    
    @Binding var selectedContact: ContactModel?
    
    let onSendToAddress: ((ContactAddressModel, ContactModel) -> Void)?
    let onNavigateToActivity: ((ContactModel) -> Void)?
    
    @State private var viewModel: ContactsViewModel?
    
    init(
        selectedContact: Binding<ContactModel?>,
        onNavigateToActivity: ((ContactModel) -> Void)? = nil,
        onSendToAddress: ((ContactAddressModel, ContactModel) -> Void)? = nil
    ) {
        self._selectedContact = selectedContact
        self.onNavigateToActivity = onNavigateToActivity
        self.onSendToAddress = onSendToAddress
    }
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = ContactsViewModel(walletManager: walletManager)
                        await viewModel?.loadContactsWithStatistics()
                    }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: ContactsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Content
                if viewModel.hasContacts {
                    contactsSection(viewModel: viewModel)
                } else {
                    emptyStateView(viewModel: viewModel)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .navigationTitle("contacts_title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showNewContactEditor()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: walletManager.alphabeticalContacts) { _, _ in
            Task {
                await viewModel.loadContactsWithStatistics()
            }
        }
        // Sheet presentation for new contact
        .sheet(isPresented: Binding(
            get: { viewModel.showingNewContactEditor },
            set: { if !$0 { viewModel.hideNewContactEditor() } }
        )) {
            ContactEditor(
                onSave: { contact in
                    Task {
                        await viewModel.createNewContact(contact)
                    }
                    viewModel.hideNewContactEditor()
                },
                onCancel: {
                    viewModel.hideNewContactEditor()
                }
            )
            .environment(walletManager)
            .environment(walletManager.contactServiceForEnvironment)
            .frame(width: 500, height: 500)
        }
        // Sheet presentation for editing contact using item-based approach
        .sheet(item: Binding(
            get: { viewModel.editingContact },
            set: { viewModel.editingContact = $0 }
        )) { contact in
            print("🔧 ContactsView: Creating ContactEditor sheet with contact: \(contact.displayName) (ID: \(contact.id))")
            return ContactEditor(
                editingContact: contact,
                onSave: { updatedContact in
                    print("🔧 ContactsView: ContactEditor onSave called with contact: \(updatedContact.displayName) (ID: \(updatedContact.id))")
                    Task {
                        await viewModel.updateContact(updatedContact)
                    }
                    viewModel.hideEditContactEditor()
                },
                onCancel: {
                    print("🔧 ContactsView: ContactEditor onCancel called")
                    viewModel.hideEditContactEditor()
                }
            )
            .environment(walletManager)
            .environment(walletManager.contactServiceForEnvironment)
            .frame(width: 500, height: 500)
            .onAppear {
                print("🔧 ContactsView: ContactEditor sheet appeared with contact: \(contact.displayName) (ID: \(contact.id))")
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func contactsSection(viewModel: ContactsViewModel) -> some View {
        if viewModel.isLoadingStatistics {
            ProgressView("progress_loading_contact_stats")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                let contacts = viewModel.contacts
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                    ContactRow(
                        contact: contact,
                        onTransactionCountTap: onNavigateToActivity,
                        onSendTap: { contact in
                            if let primaryAddress = contact.primaryAddress {
                                onSendToAddress?(primaryAddress, contact)
                            }
                        },
                        selectedContact: $selectedContact
                    )
                    
                    if index < contacts.count - 1 {
                        Divider()
                            .padding(.leading, 65)
                            .padding(.trailing, 15)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyStateView(viewModel: ContactsViewModel) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 8) {
                Text("No Contacts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("contacts_empty_help")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button("contacts_create_first") {
                viewModel.showNewContactEditor()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 400)
        .frame(maxHeight: .infinity)
    }
}
