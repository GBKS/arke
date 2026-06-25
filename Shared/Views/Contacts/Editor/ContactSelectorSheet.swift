//
//  ContactSelectorSheet.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/04/25.
//

import SwiftUI
import ArkeUI

struct ContactSelectorSheet: View {
    @Binding var selectedContactId: UUID?
    let transactionId: String?
    let onAssignContact: ((ContactModel?) async -> Void)?
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingContactEditor = false
    @State private var currentAssignedContact: ContactModel?
    @State private var pendingContact: ContactModel?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewAutoAssignCount: Int = 0
    @State private var previewAddress: String?
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Existing Contacts Section
                        if walletManager.hasContacts {
                            ForEach(Array(walletManager.alphabeticalContacts.enumerated()), id: \.element.id) { index, contact in
                                VStack(spacing: 0) {
                                    ContactChip_Selectable(
                                        avatarData: contact.avatarData,
                                        displayName: contact.displayName,
                                        notes: contact.notes,
                                        isSelected: Binding(
                                            get: { 
                                                // Show as selected if it's pending OR currently assigned (when no pending)
                                                if let pending = pendingContact {
                                                    return pending.id == contact.id
                                                } else {
                                                    return selectedContactId == contact.id
                                                }
                                            },
                                            set: { isSelected in
                                                if isSelected {
                                                    pendingContact = contact
                                                    selectedContactId = contact.id
                                                    Task {
                                                        await updatePreview(for: contact)
                                                    }
                                                } else {
                                                    pendingContact = nil
                                                    selectedContactId = currentAssignedContact?.id
                                                    previewAutoAssignCount = 0
                                                    previewAddress = nil
                                                }
                                            }
                                        )
                                    )
                                    .padding(.horizontal)
                                    
                                    // Show preview below the selected contact
                                    if let pending = pendingContact, pending.id == contact.id {
                                        ContactAssignmentPreview(
                                            currentContact: currentAssignedContact,
                                            pendingContact: pendingContact,
                                            previewAddress: previewAddress,
                                            previewAutoAssignCount: previewAutoAssignCount
                                        )
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                                    }
                                    
                                    if index < walletManager.alphabeticalContacts.count - 1 {
                                        Divider()
                                            .padding(.leading, 25)
                                            .padding(.trailing, 25)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                
                // Error display
                if let errorMessage = errorMessage {
                    ErrorBox(errorMessage: errorMessage)
                        .padding()
                }
            }
        }
        .disabled(isLoading)
        .toolbar {
            /*
            ToolbarItem(placement: .cancellationAction) {
                if pendingContact != nil || currentAssignedContact != nil {
                    Button {
                        pendingContact = nil
                        selectedContactId = currentAssignedContact?.id
                        previewAutoAssignCount = 0
                        previewAddress = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("button_cancel")
                }
            }
            */
            
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingContactEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("contacts_new_title")
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await applyChanges()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("button_apply")
                .disabled(pendingContact?.id == currentAssignedContact?.id && currentAssignedContact != nil)
            }
        }
        .task {
            await loadCurrentAssignment()
        }
        .sheet(isPresented: $showingContactEditor) {
            ContactEditor(
                editingContact: nil,
                onSave: { contact in
                    Task {
                        await createAndAssignContact(contact)
                    }
                    showingContactEditor = false
                },
                onCancel: {
                    showingContactEditor = false
                }
            )
            .environment(walletManager)
            .environment(walletManager.contactServiceForEnvironment)
            #if os(macOS)
            .frame(width: 500, height: 500)
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    private func updatePreview(for contact: ContactModel) async {
        // Only show preview if we have a transaction ID
        guard let transactionId = transactionId else {
            return
        }
        
        // Get the transaction to find its address and count matches
        let allTransactions = walletManager.transactions
        if let transaction = allTransactions.first(where: { $0.txid == transactionId }),
           let address = transaction.address {
            
            // Check if this is a single-use payment type
            let paymentMethod = PaymentMethod.detect(from: address)
            if paymentMethod.isSingleUse {
                await MainActor.run {
                    previewAddress = nil  // Don't show "will save address" for single-use payments
                    previewAutoAssignCount = 0  // No auto-assignment for unique invoices
                }
                return
            }
            
            await MainActor.run {
                previewAddress = address
                
                // Count how many OTHER transactions would be affected
                let normalizedAddress = address.lowercased()
                previewAutoAssignCount = allTransactions.filter { tx in
                    guard let txAddress = tx.address else { return false }
                    return txAddress.lowercased() == normalizedAddress && tx.txid != transactionId
                }.count
            }
        }
    }
    
    private func applyChanges() async {
        // If we have a transaction ID, use the full assignment logic
        if transactionId != nil {
            if let pending = pendingContact {
                await assignContact(pending)
            } else if currentAssignedContact != nil {
                await removeAssignment()
            }
        } else {
            // Simple mode: just update the binding and call the callback
            if let pending = pendingContact {
                selectedContactId = pending.id
                await onAssignContact?(pending)
            } else {
                selectedContactId = nil
                await onAssignContact?(nil)
            }
        }
        
        // Dismiss after successful application (or error shown)
        if errorMessage == nil {
            await MainActor.run {
                dismiss()
            }
        }
    }
    

    private func loadCurrentAssignment() async {
        // Only load from transaction if we have a transaction ID
        guard let transactionId = transactionId else {
            // Simple mode: just use the bound contact ID
            if let contactId = selectedContactId {
                let contact = walletManager.contacts.first { $0.id == contactId }
                await MainActor.run {
                    currentAssignedContact = contact
                    pendingContact = contact
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let contacts = try await walletManager.getTransactionContacts(transactionId)
            await MainActor.run {
                currentAssignedContact = contacts.first
                selectedContactId = contacts.first?.id
                pendingContact = contacts.first
                isLoading = false
            }
            
            // Load preview data for the current assignment
            if let currentContact = contacts.first {
                await updatePreview(for: currentContact)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load current assignment: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func assignContact(_ contact: ContactModel) async {
        guard let transactionId = transactionId else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Remove existing assignment first if there is one
            if currentAssignedContact != nil {
                try await walletManager.removeContactAssignment(from: transactionId)
            }
            
            // Assign new contact with address learning and bulk assignment
            _ = try await walletManager.assignContactWithAddressLearning(contact.id, to: transactionId)
            
            await MainActor.run {
                currentAssignedContact = contact
                pendingContact = contact
                isLoading = false
            }
            
            await onAssignContact?(contact)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to assign contact: \(error.localizedDescription)"
                selectedContactId = currentAssignedContact?.id
                pendingContact = currentAssignedContact
                isLoading = false
            }
        }
    }
    
    private func removeAssignment() async {
        guard let transactionId = transactionId else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Remove contact from this transaction only
            // Note: This does NOT remove the contact from other transactions
            // or remove the address from the contact's address book
            try await walletManager.removeContactAssignment(from: transactionId)
            
            await MainActor.run {
                currentAssignedContact = nil
                selectedContactId = nil
                pendingContact = nil
                isLoading = false
            }
            
            await onAssignContact?(nil)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to remove assignment: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func createAndAssignContact(_ contact: ContactModel) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let createdContact = try await walletManager.createContact(contact)
            
            // If we have a transaction ID, do full assignment logic
            if let transactionId = transactionId {
                // Remove existing assignment first if there is one
                if currentAssignedContact != nil {
                    try await walletManager.removeContactAssignment(from: transactionId)
                }
                
                // Assign new contact with address learning and bulk assignment
                _ = try await walletManager.assignContactWithAddressLearning(createdContact.id, to: transactionId)
            }
            
            await MainActor.run {
                currentAssignedContact = createdContact
                selectedContactId = createdContact.id
                pendingContact = createdContact
                isLoading = false
            }
            
            await onAssignContact?(createdContact)
            
            // Auto-dismiss after creating and assigning new contact
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create and assign contact: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
