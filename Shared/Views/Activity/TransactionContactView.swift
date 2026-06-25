//
//  TransactionContactView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct TransactionContactView: View {
    let transaction: TransactionModel
    let onNavigateToContact: ((ContactModel) -> Void)?
    @Environment(WalletManager.self) private var walletManager
    
    @State private var showingContactSelector = false
    @State private var assignedContact: ContactModel?
    @State private var isContactLoading = false
    @State private var error: String?
    
    var body: some View {
        // Don't show contact assignment for internal transfers
        // (boarding, offboarding, refresh, exit are user's own operations)
        if transaction.isInternalTransfer {
            EmptyView()
        } else {
            contactAssignmentView
        }
    }
    
    @ViewBuilder
    private var contactAssignmentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isContactLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let assignedContact = assignedContact {
                FlowLayout(alignment: .leading, spacing: 8) {
                    Button {
                        onNavigateToContact?(assignedContact)
                    } label: {
                        ContactChip(avatarData: assignedContact.avatarData, displayName: assignedContact.displayName, notes: assignedContact.notes, size: .large)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Edit contact button styled like a chip
                    /*
                    Button("label_change") {
                        showingContactSelector = true
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .font(.body)
                    .fontWeight(.medium)
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isContactLoading)
                     */
                    
                    Button {
                        showingContactSelector = true
                    } label: {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.body)
                    }
                    .accessibilityLabel("action_change_contact")
                    .buttonStyle(.bordered)
                    .disabled(isContactLoading)
                }
            } else {
                FlowLayout(alignment: .leading, spacing: 8) {
                    // Add contact button styled like a ContactChip
                    /*
                    Button("button_add_contact") {
                        showingContactSelector = true
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .font(.body)
                    .fontWeight(.medium)
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isContactLoading)
                    */
                    
                    Button{
                        showingContactSelector = true
                    } label: {
                        Text("button_add_contact")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Arke.gold2)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isContactLoading)
                }
            }
            
            if let error = error {
                ErrorBox(errorMessage: error)
            }
        }
        .task(id: transaction.txid) {
            await loadAssignedContact()
        }
        .task(id: walletManager.dataVersion) {
            // Reload contact when dataVersion changes
            await loadAssignedContact()
        }
        .sheet(isPresented: $showingContactSelector) {
            NavigationStack {
                ContactSelectorSheet(
                    selectedContactId: Binding(
                        get: { assignedContact?.id },
                        set: { _ in }
                    ),
                    transactionId: transaction.txid,
                    onAssignContact: { contact in
                        await MainActor.run {
                            self.assignedContact = contact
                        }
                    }
                )
                .environment(walletManager)
                .navigationTitle("button_assign_contact")                
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            #if os(macOS)
            .frame(width: 400, height: 400)
            #else
            .presentationDetents([.medium, .large])
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAssignedContact() async {
        isContactLoading = true
        error = nil
        
        do {
            let contacts = try await walletManager.getTransactionContacts(transaction.txid)
            await MainActor.run {
                self.assignedContact = contacts.first
                self.isContactLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isContactLoading = false
            }
        }
    }
    
    private func removeContact() async {
        isContactLoading = true
        error = nil
        
        do {
            // Remove contact from this transaction only
            // Note: This does NOT affect other transactions with the same address
            // or remove the address from the contact's address book
            try await walletManager.removeContactAssignment(from: transaction.txid)
            await MainActor.run {
                self.assignedContact = nil
                self.isContactLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isContactLoading = false
            }
        }
    }
}
