//
//  ContactDetailView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct ContactDetailView_iOS: View {
    let contact: ContactModel
    let onSendToAddress: (ContactAddressModel) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNavigateToActivity: (ContactModel?) -> Void
    
    @Environment(\.serviceContainer) private var serviceContainer
    @Environment(\.dismiss) private var dismiss
    
    @Environment(WalletManager.self) private var walletManager
    
    // MARK: - ViewModel
    
    @State private var viewModel: ContactDetailViewModel?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        contentView
            .task(id: contact.id) {                
                // Initialize ViewModel as soon as environment is available
                viewModel = ContactDetailViewModel(
                    contact: contact,
                    serviceContainer: serviceContainer,
                    walletManager: walletManager
                )
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        listContent
            .toolbar {
                if contact.contactType.canBeEdited {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.buttonEdit) {
                            onEdit()
                        }
                    }
                }
            }
            .confirmationDialog(L10n.buttonDeleteContact,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.buttonDelete, role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(L10n.buttonCancel, role: .cancel) {}
            } message: {
                Text(String(localized: "message_confirm_delete", defaultValue: "Are you sure you want to delete \(contact.displayName)?"))
            }
            .sheet(isPresented: contactImportSheetBinding) {
                contactImportSheetView
            }
            .alert(String(localized: "contacts_link", defaultValue: "Contact Link"), isPresented: alertBinding) {
                Button(L10n.buttonOk, role: .cancel) { }
            } message: {
                if let alertMessage = viewModel?.alertMessage {
                    Text(alertMessage)
                }
            }
    }
    
    private var listContent: some View {
        List {
            headerSection
            
            // Signet Faucet section (only for faucet contacts on signet network)
            if contact.contactType == .faucet && isSignetNetwork {
                signetFaucetSection
            }
            
            if viewModel?.hasTransactionData == true {
                transactionSummarySection
            }
            
            addressesSection
            
            if let notes = contact.notes, !notes.isEmpty {
                notesSection(notes)
            }
            
            if let viewModel, contact.contactType.canBeEdited {
                contactDetailsSection(viewModel: viewModel)
            }
            
            if contact.contactType.canBeDeleted {
                managementSection
            }
        }
    }
    
    private var headerSection: some View {
        Section {
            ContactHeaderView(contact: contact)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listRowBackground(Color.clear)
    }
    
    private var transactionSummarySection: some View {
        Section {
            ContactTransactionSummaryView(
                contact: contact,
                onViewActivity: {
                    onNavigateToActivity(contact) // Filter by this contact
                }
            )
        }
    }
    
    private var addressesSection: some View {
        Section {
            ContactAddressesSection(
                contact: contact,
                onSendToAddress: onSendToAddress
            )
        }
    }
    
    private func notesSection(_ notes: String) -> some View {
        Section(String(localized: "label_notes", defaultValue: "Notes")) {
            Text(notes)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
    
    private func contactDetailsSection(viewModel: ContactDetailViewModel) -> some View {
        Section {
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
        }
    }
    
    private var managementSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(L10n.buttonDeleteContact, systemImage: "trash")
                    .foregroundStyle(Color.Arke.red)
            }
        }
    }
    
    private var contactImportSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showingContactImport ?? false },
            set: { if let viewModel { viewModel.showingContactImport = $0 } }
        )
    }
    
    private var contactImportSheetView: some View {
        NavigationStack {
            ContactImportSheet(
                onSelect: { importedData in
                    Task {
                        await viewModel?.handleContactImportSelection(importedData)
                    }
                    viewModel?.showingContactImport = false
                },
                onCancel: {
                    viewModel?.showingContactImport = false
                }
            )
        }
        .presentationDetents([.medium, .large])
    }
    
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showingAlert ?? false },
            set: { if let viewModel { viewModel.showingAlert = $0 } }
        )
    }
    
    // MARK: - Computed Properties
    
    /// Check if we're on signet network
    private var isSignetNetwork: Bool {
        guard let networkConfig = walletManager.networkConfig else { return false }
        return networkConfig.networkType.lowercased() == "signet"
    }
    

    
    // MARK: - Signet Faucet Section
    
    private var signetFaucetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {                
                // Request button
                faucetRequestButton
                
                // Status message
                if let viewModel, viewModel.showingFaucetAlert {
                    faucetStatusMessage
                }
            }
            .padding(.vertical, 8)
        }
        .listSectionSpacing(15)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    private var faucetRequestButton: some View {
        Button {
            requestFaucet()
        } label: {
            HStack {
                if viewModel?.isRequestingFaucet == true {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.Arke.gold4))
                        .controlSize(.small)
                } else {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.Arke.gold4)
                }
                Text(viewModel?.isRequestingFaucet == true ? String(localized: "status_requesting", defaultValue: "Requesting...") : String(localized: "onboarding_ask_test_bitcoin", defaultValue: "Ask for test bitcoin"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.Arke.gold4)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel?.isRequestingFaucet == true || walletManager.arkAddress.isEmpty)
    }
    
    private var faucetStatusMessage: some View {
        Group {
            if let alertType = viewModel?.faucetAlertType {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon(for: alertType))
                        .foregroundStyle(statusColor(for: alertType))
                    
                    Text(viewModel?.faucetAlertMessage ?? "")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(15)
                .background(statusColor(for: alertType).opacity(0.1))
                .cornerRadius(15)
            }
        }
    }
    
    private func statusIcon(for type: FaucetAlertType) -> String {
        switch type {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .rateLimited:
            return "clock.fill"
        case .insufficientFunds:
            return "drop.slash.fill"
        }
    }
    
    private func statusColor(for type: FaucetAlertType) -> Color {
        switch type {
        case .success:
            return .Arke.green
        case .error:
            return .Arke.red
        case .rateLimited:
            return .Arke.orange
        case .insufficientFunds:
            return .Arke.yellow
        }
    }
    
    private func requestFaucet() {
        // Use the user's own Ark address
        let address = walletManager.arkAddress
        guard !address.isEmpty else { return }
        
        Task {
            guard let viewModel else { return }
            
            // Check notification status and request if not determined
            let notificationAction = await viewModel.checkNotificationStatus()
            print("🔔 [Faucet] Notification action: \(notificationAction)")
            
            if notificationAction == .promptForPermission {
                // Request notification permission directly
                print("🔔 [Faucet] Requesting notification permission...")
                let success = await viewModel.registerForNotifications()
                print("🔔 [Faucet] Notification registration result: \(success)")
            }
            
            // Proceed with faucet request regardless of notification result
            await viewModel.requestSignetFaucet(toAddress: address) {
                onNavigateToActivity(nil)
            }
        }
    }
}
