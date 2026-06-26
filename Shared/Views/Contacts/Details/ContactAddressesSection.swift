//
//  ContactAddressesSection.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct ContactAddressesSection: View {
    let contact: ContactModel
    let onSendToAddress: ((ContactAddressModel) -> Void)?
    
    @Environment(WalletManager.self) private var walletManager
    
    @State private var addresses: [ContactAddressModel] = []
    @State private var isLoadingAddresses = false
    @State private var showingAddressEditor = false
    @State private var editingAddress: ContactAddressModel?
    @State private var addressError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("label_addresses")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if contact.contactType.canBeEdited {
                    Button {
                        showAddAddressSheet()
                    } label: {
                        Image(systemName: "plus")
                            .tint(Color.Arke.gold4)
                    }
                    .accessibilityLabel(Text("button_add_new_address"))
                    .buttonStyle(.bordered)
                }
            }
            
            Divider()
            
            if isLoadingAddresses {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .Arke.blue))
                        .scaleEffect(0.7)
                    
                    Text(String(localized: "status_loading_addresses"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else if addresses.isEmpty {
                emptyAddressesView
            } else {
                VStack(spacing: 8) {
                    ForEach(addresses) { address in
                        AddressListItem(
                            address: address,
                            isEditable: contact.contactType.canBeEdited,
                            onEdit: { editAddress(address) },
                            onSetPrimary: {
                                Task { await setPrimaryAddress(address) }
                            },
                            onSendTo: { onSendToAddress?(address) }
                        )
                    }
                }
            }
            
            if let error = addressError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.Arke.red)
                    .padding(.horizontal, 8)
            }
        }
        .onAppear {
            Task { await loadAddresses() }
        }
        .onChange(of: contact.id) { oldValue, newValue in
            Task { await loadAddresses() }
        }
        .sheet(isPresented: Binding(
            get: { showingAddressEditor && editingAddress == nil },
            set: { newValue in
                if !newValue {
                    showingAddressEditor = false
                    editingAddress = nil
                }
            }
        )) {
            ContactAddressEditor(
                contact: contact,
                editingAddress: nil,
                onSave: {
                    showingAddressEditor = false
                    editingAddress = nil
                    Task { await loadAddresses() }
                },
                onCancel: {
                    showingAddressEditor = false
                    editingAddress = nil
                }
            )
        }
        .sheet(item: $editingAddress) { address in
            ContactAddressEditor(
                contact: contact,
                editingAddress: address,
                onSave: {
                    showingAddressEditor = false
                    editingAddress = nil
                    Task { await loadAddresses() }
                },
                onCancel: {
                    showingAddressEditor = false
                    editingAddress = nil
                },
                onDelete: {
                    showingAddressEditor = false
                    editingAddress = nil
                    Task { await deleteAddress(address) }
                }
            )
        }
    }
    
    // MARK: - Subviews
    
    private var emptyAddressesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("contacts_no_addresses_added")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("contacts_add_addresses_help")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background)
        .cornerRadius(8)
    }
    
    // MARK: - Address Actions
    
    private func loadAddresses() async {
        isLoadingAddresses = true
        addressError = nil
        addresses = await walletManager.getAddressesForContact(contact.id)
        isLoadingAddresses = false
    }
    
    private func showAddAddressSheet() {
        editingAddress = nil
        showingAddressEditor = true
    }
    
    private func editAddress(_ address: ContactAddressModel) {
        editingAddress = address
        showingAddressEditor = true
    }
    
    private func deleteAddress(_ address: ContactAddressModel) async {
        do {
            try await walletManager.deleteAddress(address.id)
            await loadAddresses()
            addressError = nil
        } catch {
            addressError = "Failed to delete address: \(error.localizedDescription)"
        }
    }
    
    private func setPrimaryAddress(_ address: ContactAddressModel) async {
        do {
            try await walletManager.setPrimaryAddress(address.id, for: contact.id)
            await loadAddresses()
        } catch {
            addressError = "Failed to set primary address: \(error.localizedDescription)"
        }
    }
}
