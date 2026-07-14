//
//  PaymentInfoReceivedSheet.swift
//  Arké
//
//  Sheet displayed when payment info is received via proximity exchange
//

import SwiftUI
import SwiftData
import ArkeUI

struct PaymentInfoReceivedSheet: View {
    let receivedInfo: ReceivedPaymentInfo
    let onPay: (String) -> Void
    let onNavigateToContact: (ContactModel) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var manager
    @Query private var contacts: [PersistentContact]
    
    // State for contact creation
    @State private var createdContact: ContactModel?
    @State private var isCreatingContact = false
    
    // Parse BIP-21 URI to extract address and label
    private var parsedURI: ParsedBIP21URI {
        BIP21URIHelper.parseBIP21URI(receivedInfo.bip21URI)
    }
    
    // Check if this address already exists in contacts
    private var existingContact: PersistentContact? {
        contacts.first { contact in
            contact.addresses?.contains { address in
                address.normalizedAddress == parsedURI.address.lowercased()
            } ?? false
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    // Avatar or default icon
                    if let avatarData = receivedInfo.avatarData,
                       let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.Arke.blue.opacity(0.3), lineWidth: 3)
                            )
                            .padding(.top, 24)
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.Arke.blue)
                            .padding(.top, 24)
                    }
                    
                    Text("activity_payment_info_received")
                        .font(.system(size: 30, design: .serif))
                    
                    if let label = parsedURI.label, !label.isEmpty {
                        Text("From \(label)")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.bottom, 32)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Contact info if exists
                        if let contact = existingContact {
                            contactInfoSection(contact: contact)
                        }
                        
                        // Ark Address section (if present in BIP-21 URI)
                        if let arkAddress = parsedURI.arkAddress, !arkAddress.isEmpty {
                            arkAddressSection(arkAddress: arkAddress)
                        }
                        
                        // Bitcoin Address section
                        addressSection
                        
                        /*
                        // Label section (if present in BIP-21 URI)
                        if let label = parsedURI.label, !label.isEmpty {
                            labelSection(label: label)
                        }
                        */
                        
                        // Amount section (if present in BIP-21 URI)
                        if let amount = parsedURI.amount {
                            amountSection(amount: amount)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    // Pay button
                    Button {
                        onPay(receivedInfo.bip21URI)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                            Text("activity_pay")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    
                    // Add to Contacts / View Contact button
                    if let contact = createdContact {
                        // Show "View Contact" button after successful creation
                        Button {
                            onNavigateToContact(contact)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("activity_view_contact")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
                    } else if existingContact == nil {
                        // Show "Add to Contacts" button if not already in contacts and not yet created
                        Button {
                            Task {
                                await createContact()
                            }
                        } label: {
                            HStack {
                                if isCreatingContact {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color.Arke.gold4))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                Text(isCreatingContact ? LocalizedStringKey("activity_adding") : LocalizedStringKey("activity_add_to_contacts"))
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
                        .disabled(isCreatingContact)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(uiColor: .systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.Arke.gold)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Contact Creation
    
    private func createContact() async {
        isCreatingContact = true
        
        do {
            // Create contact model with data from received payment info
            let contactName = parsedURI.label ?? "Unknown"
            let newContactModel = ContactModel(
                cachedName: contactName,
                avatarData: receivedInfo.avatarData,
                addresses: []  // We'll add addresses after contact creation
            )
            
            // Create the contact via WalletManager
            let createdContactModel = try await manager.createContact(newContactModel)
            
            // Now add the Bitcoin address
            if !parsedURI.address.isEmpty {
                do {
                    _ = try await manager.contactAddressService.validateAndCreateAddress(
                        parsedURI.address,
                        for: createdContactModel.id,
                        label: "From proximity exchange",
                        isPrimary: true
                    )
                } catch {
                    print("⚠️ Failed to add Bitcoin address to contact: \(error)")
                }
            }
            
            // Add Ark address if present
            if let arkAddress = parsedURI.arkAddress, !arkAddress.isEmpty {
                do {
                    _ = try await manager.contactAddressService.validateAndCreateAddress(
                        arkAddress,
                        for: createdContactModel.id,
                        label: "From proximity exchange",
                        isPrimary: parsedURI.address.isEmpty  // Primary if no Bitcoin address
                    )
                } catch {
                    print("⚠️ Failed to add Ark address to contact: \(error)")
                }
            }
            
            // Refresh contacts to get updated model with addresses
            await manager.refreshContacts()
            
            // Get the updated contact with addresses
            if let updatedContact = manager.contacts.first(where: { $0.id == createdContactModel.id }) {
                createdContact = updatedContact
            } else {
                createdContact = createdContactModel
            }
            
            print("✅ Successfully created contact '\(contactName)' from proximity exchange")
            
        } catch {
            print("❌ Failed to create contact: \(error)")
            // TODO: Show error to user
        }
        
        isCreatingContact = false
    }
    
    // MARK: - View Components
    
    private func contactInfoSection(contact: PersistentContact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("nav_title_contact")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 12) {
                // Avatar
                if let avatarData = contact.avatarData, let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.blue.gradient)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(String(contact.cachedName.prefix(1)).uppercased())
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.cachedName)
                        .font(.headline)
                    
                    if let notes = contact.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func arkAddressSection(arkAddress: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("activity_ark_address")
                .font(.body)
                .foregroundStyle(.secondary)
            
            ExpandableAddressView(address: arkAddress, isExpanded: .constant(false), animated: false)
        }
    }
    
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("activity_bitcoin_address")
                .font(.body)
                .foregroundStyle(.secondary)
            
            ExpandableAddressView(address: parsedURI.address, isExpanded: .constant(false), animated: false)
        }
    }
    
    private func labelSection(label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("activity_label")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Text(label)
                .font(.title3)
        }
    }
    
    private func amountSection(amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("label_amount")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Text(BitcoinFormatter.shared.formatAccountingAmount(amount, transactionType: .sent))
                .font(.title3)
        }
    }
}

// MARK: - Helper for BIP-21 URI Parsing

struct ParsedBIP21URI {
    let address: String
    let arkAddress: String?
    let label: String?
    let amount: Int?
    let message: String?
}

extension BIP21URIHelper {
    static func parseBIP21URI(_ uri: String) -> ParsedBIP21URI {
        // Strip the bitcoin: scheme if present
        let cleanedURI = uri.replacingOccurrences(of: "bitcoin:", with: "")
        
        // Split address from parameters
        let components = cleanedURI.components(separatedBy: "?")
        let address = components.first ?? uri
        
        var arkAddress: String?
        var label: String?
        var amount: Int?
        var message: String?
        
        // Parse query parameters if present
        if components.count > 1, let queryString = components.last {
            let params = queryString.components(separatedBy: "&")
            for param in params {
                let keyValue = param.components(separatedBy: "=")
                guard keyValue.count == 2 else { continue }
                
                let key = keyValue[0]
                let value = keyValue[1].removingPercentEncoding ?? keyValue[1]
                
                switch key {
                case "ark":
                    arkAddress = value
                case "label":
                    label = value
                case "amount":
                    // BIP-21 amount is in BTC, convert to sats
                    if let btcAmount = Double(value) {
                        amount = Int(btcAmount * 100_000_000)
                    }
                case "message":
                    message = value
                default:
                    break
                }
            }
        }
        
        return ParsedBIP21URI(address: address, arkAddress: arkAddress, label: label, amount: amount, message: message)
    }
}
