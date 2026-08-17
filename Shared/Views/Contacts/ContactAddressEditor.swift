//
//  ContactAddressEditor.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/5/25.
//

import SwiftUI
import ArkeUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ContactAddressEditor: View {
    
    // MARK: - Properties
    
    /// The contact this address belongs to
    let contact: ContactModel
    
    /// The address being edited (nil for new address)
    let editingAddress: ContactAddressModel?
    
    /// Callback when address is saved
    let onSave: () -> Void
    
    /// Callback when editing is cancelled
    let onCancel: () -> Void
    
    /// Callback when address is deleted (only available when editing)
    let onDelete: (() -> Void)?
    
    /// Address service for validation and operations
    @Environment(WalletManager.self) private var walletManager
    
    // MARK: - Form State
    
    @State private var addressText: String = ""
    @State private var label: String = ""
    @State private var isPrimary: Bool = false
    
    // MARK: - UI State
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var validationResult: PaymentRequest?
    @State private var showingDeleteConfirmation = false
    
    // MARK: - Validation
    
    private var trimmedAddress: String {
        addressText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var isValidAddress: Bool {
        validationResult != nil
    }
    
    private var canSave: Bool {
        isValidAddress && !trimmedAddress.isEmpty && !isLoading
    }
    
    private var isEditing: Bool {
        editingAddress != nil
    }
    
    // MARK: - Initialization
    
    init(
        contact: ContactModel,
        editingAddress: ContactAddressModel? = nil,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.contact = contact
        self.editingAddress = editingAddress
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Contact Info Section
                Section {
                    HStack(spacing: 12) {
                        ContactAvatarView(avatarData: contact.avatarData, size: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.displayName)
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                    }
                }
                
                // Address Field Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.labelAddress)
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        TextField(String(localized: "placeholder_payment_destination", defaultValue: "Enter Bitcoin address, Lightning address, or BIP-353 name"), text: $addressText, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.body.monospaced())
                            .disabled(isEditing) // Don't allow editing the address itself
                        
                        if !trimmedAddress.isEmpty && !isValidAddress {
                            Label(String(localized: "error_invalid_address", defaultValue: "Invalid address format"), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Label Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "label_label_optional", defaultValue: "Label (Optional)"))
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        TextField(String(localized: "placeholder_address_label", defaultValue: "Enter a label for this address"), text: $label)
                        
                        Text(String(localized: "contacts_label_help", defaultValue: "If left empty, the address format will be used as the label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Primary Toggle
                    Toggle(String(localized: "action_set_primary_address", defaultValue: "Set as primary address"), isOn: $isPrimary)
                        .font(.headline)
                        .fontWeight(.medium)
                }
                
                // Validation Info Section
                if let validationResult = validationResult {
                    Section(String(localized: "receive_address_information", defaultValue: "Address Information")) {
                        // Primary destination info
                        if let primary = validationResult.primaryDestination {
                            LabeledContent(String(localized: "label_format", defaultValue: "Format"), value: primary.format.displayName)
                            
                            if let network = primary.network {
                                LabeledContent(String(localized: "label_network", defaultValue: "Network")) {
                                    Text(network.displayName)
                                        .foregroundColor(network == .mainnet ? .Arke.green : .Arke.orange)
                                }
                            }
                        }
                        
                        // Show if there are alternative payment options
                        if validationResult.hasAlternatives {
                            LabeledContent(String(localized: "send_alternative_options", defaultValue: "Alternative Options"), value: "\(validationResult.alternativeDestinations.count)")
                            
                            ForEach(validationResult.alternativeDestinations) { dest in
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(dest.format.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Error Section
                if let errorMessage = errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundColor(.Arke.red)
                    }
                }
                
                // Delete button (only when editing)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "button_delete_address", defaultValue: "Delete Address"), systemImage: "trash")
                                .foregroundStyle(Color.Arke.red)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? String(localized: "button_edit_address", defaultValue: "Edit Address") : String(localized: "button_add_address", defaultValue: "Add Address"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.buttonCancel)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveAddress()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(L10n.buttonSave)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            setupInitialState()
        }
        .onChange(of: addressText) { _, newValue in
            validateAddress(newValue)
        }
        .confirmationDialog(String(localized: "button_delete_address", defaultValue: "Delete Address"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "button_delete_address_only", defaultValue: "Delete Address Only"), role: .destructive) {
                onDelete?()
            }
            Button(L10n.buttonCancel, role: .cancel) {}
        } message: {
            Text(String(localized: "contacts_remove_address_warning", defaultValue: "This will remove the address from %@'s contact card.\n\nTransactions previously assigned to this contact will remain assigned. You can unassign them individually from the transaction details."))
        }
    }
    
    // MARK: - Actions
    
    private func setupInitialState() {
        if let editingAddress = editingAddress {
            addressText = editingAddress.address
            label = editingAddress.label ?? ""
            isPrimary = editingAddress.isPrimary
            validateAddress(editingAddress.address)
        }
    }
    
    private func validateAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            validationResult = nil
            return
        }
        
        print("validateAddress \(address)")
        
        validationResult = walletManager.parsePaymentRequest(trimmed)
    }
    
    private func saveAddress() async {
        guard canSave else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let finalLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
            
            if let editingAddress = editingAddress {
                // Update existing address
                let updatedAddress = ContactAddressModel(
                    id: editingAddress.id,
                    address: editingAddress.address,
                    normalizedAddress: editingAddress.normalizedAddress,
                    format: editingAddress.format,
                    label: finalLabel,
                    isPrimary: isPrimary,
                    contactId: editingAddress.contactId,
                    network: editingAddress.network,
                    createdAt: editingAddress.createdAt,
                    updatedAt: Date()
                )
                
                try await walletManager.updateAddress(updatedAddress)
            } else {
                // Create new address
                _ = try await walletManager.validateAndCreateAddress(
                    trimmedAddress,
                    for: contact.id,
                    label: finalLabel,
                    isPrimary: isPrimary
                )
            }
            
            onSave()
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
