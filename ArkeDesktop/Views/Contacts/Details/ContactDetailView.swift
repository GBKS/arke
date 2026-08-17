//
//  ContactDetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/5/25.
//

import SwiftUI
import ArkeUI
import AppKit

struct ContactDetailView: View {
    let contact: ContactModel
    let onSendToAddress: ((ContactAddressModel) -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onNavigateToActivity: ((ContactModel) -> Void)?
    
    @Environment(\.serviceContainer) private var serviceContainer
    
    // MARK: - ViewModel
    
    @State private var viewModel: ContactDetailViewModel?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = ContactDetailViewModel(
                            contact: contact,
                            serviceContainer: serviceContainer
                        )
                    }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: ContactDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    ContactHeaderView(contact: contact)
                    
                    // Transaction Statistics Summary
                    if viewModel.hasTransactionData {
                        ContactTransactionSummaryView(
                            contact: contact,
                            onViewActivity: {
                                onNavigateToActivity?(contact)
                            }
                        )
                    }
                }
                
                // Addresses Section
                Divider()
                
                ContactAddressesSection(
                    contact: contact,
                    onSendToAddress: onSendToAddress
                )
                
                // Notes Section
                if let notes = contact.notes, !notes.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "label_notes", defaultValue: "Notes"))
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(notes)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Divider()
                
                // Contact Information Section
                ContactDetailsDisclosure(
                    contact: contact,
                    onRefreshFromNativeContact: {
                        Task {
                            await viewModel.handleRefreshFromNativeContact()
                        }
                    },
                    onUnlinkNativeContact: {
                        Task {
                            await viewModel.handleUnlinkFromNativeContact()
                        }
                    },
                    onLinkNativeContact: {
                        viewModel.handleLinkToNativeContact()
                    }
                )
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(String(localized: "nav_title_contact", defaultValue: "Contact"))
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let onEdit = onEdit {
                    Button(L10n.buttonEdit) {
                        onEdit()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingContactImport },
            set: { viewModel.showingContactImport = $0 }
        )) {
            ContactImportSheet(
                onSelect: { importedData in
                    Task {
                        await viewModel.handleContactImportSelection(importedData)
                    }
                    viewModel.showingContactImport = false
                },
                onCancel: {
                    viewModel.showingContactImport = false
                }
            )
        }
        .alert(String(localized: "contacts_link", defaultValue: "Contact Link"), isPresented: Binding(
            get: { viewModel.showingAlert },
            set: { viewModel.showingAlert = $0 }
        )) {
            Button(L10n.buttonOk, role: .cancel) { }
        } message: {
            if let alertMessage = viewModel.alertMessage {
                Text(alertMessage)
            }
        }
    }
}
