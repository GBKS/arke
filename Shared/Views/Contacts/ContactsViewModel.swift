//
//  ContactsViewModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/4/25.
//

import SwiftUI
import ArkeUI
import Combine

/// Shared view model for contact management across macOS and iOS
@Observable
@MainActor
final class ContactsViewModel {
    
    // MARK: - Dependencies
    
    private let walletManager: WalletManager
    
    // MARK: - State
    
    var contactsWithStatistics: [ContactModel] = []
    var showingNewContactEditor = false
    var editingContact: ContactModel?
    var isLoadingStatistics = false
    var errorMessage: String?
    var searchText = ""
    
    // MARK: - CloudKit Observation
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(walletManager: WalletManager) {
        self.walletManager = walletManager
        startObservingCloudKitChanges()
    }
    
    // MARK: - CloudKit Change Observation
    
    /// Start observing CloudKit remote change notifications
    private func startObservingCloudKitChanges() {
        NotificationCenter.default
            .publisher(for: .cloudKitDataDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleCloudKitChange()
                }
            }
            .store(in: &cancellables)
        
        print("📱 [ContactsViewModel] Started observing CloudKit changes")
    }
    
    /// Handle CloudKit remote changes by reloading contact statistics
    private func handleCloudKitChange() async {
        print("📱 [ContactsViewModel] CloudKit change detected - reloading contact statistics")
        await loadContactsWithStatistics()
    }
    
    deinit {
        cancellables.removeAll()
        print("📱 [ContactsViewModel] Stopped observing CloudKit changes")
    }
    
    // MARK: - Computed Properties
    
    /// Whether the wallet has any contacts
    var hasContacts: Bool {
        !walletManager.alphabeticalContacts.isEmpty
    }
    
    /// All contacts (with statistics if loaded, otherwise fallback to base contacts)
    var contacts: [ContactModel] {
        contactsWithStatistics.isEmpty ? walletManager.alphabeticalContacts : contactsWithStatistics
    }
    
    /// Filtered contacts based on search text
    var filteredContacts: [ContactModel] {
        guard !searchText.isEmpty else { return contacts }
        
        return contacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            contact.notes?.localizedCaseInsensitiveContains(searchText) ?? false ||
            contact.addresses.contains { address in
                address.address.localizedCaseInsensitiveContains(searchText) ||
                address.label?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    /// Contacts grouped alphabetically by first letter
    var groupedContacts: [(String, [ContactModel])] {
        let sorted = filteredContacts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        
        let grouped = Dictionary(grouping: sorted) { contact in
            let firstChar = contact.displayName.prefix(1).uppercased()
            return firstChar.isEmpty ? "#" : 
                   (firstChar.rangeOfCharacter(from: .letters) != nil ? firstChar : "#")
        }
        
        return grouped.sorted { $0.key < $1.key }
    }
    
    // MARK: - Actions
    
    func loadContactsWithStatistics() async {
        isLoadingStatistics = true
        errorMessage = nil
        defer { isLoadingStatistics = false }
        
        do {
            let statistics = try await walletManager.getContactStatistics()
            let statisticsDict = Dictionary(uniqueKeysWithValues: statistics.map { ($0.contactId, $0) })
            
            let enrichedContacts = walletManager.alphabeticalContacts.map { contact in
                if let stat = statisticsDict[contact.id] {
                    return ContactModel(
                        id: contact.id,
                        cachedName: contact.cachedName,
                        notes: contact.notes,
                        avatarData: contact.avatarData,
                        createdAt: contact.createdAt,
                        updatedAt: contact.updatedAt,
                        contactType: contact.contactType,
                        nativeContactID: contact.nativeContactID,
                        lastSyncedFromNative: contact.lastSyncedFromNative,
                        transactionCount: stat.transactionCount,
                        sentAmount: stat.sentAmount,
                        receivedAmount: stat.receivedAmount,
                        addresses: contact.addresses
                    )
                } else {
                    return ContactModel(
                        id: contact.id,
                        cachedName: contact.cachedName,
                        notes: contact.notes,
                        avatarData: contact.avatarData,
                        createdAt: contact.createdAt,
                        updatedAt: contact.updatedAt,
                        contactType: contact.contactType,
                        nativeContactID: contact.nativeContactID,
                        lastSyncedFromNative: contact.lastSyncedFromNative,
                        transactionCount: 0,
                        sentAmount: 0,
                        receivedAmount: 0,
                        addresses: contact.addresses
                    )
                }
            }
            
            contactsWithStatistics = enrichedContacts
            print("✅ Loaded \(enrichedContacts.count) contacts with statistics")
        } catch {
            print("❌ Failed to load contact statistics: \(error)")
            errorMessage = "Failed to load contact statistics"
            // Fall back to contacts without statistics
            contactsWithStatistics = walletManager.alphabeticalContacts
        }
    }
    
    func createNewContact(_ contact: ContactModel) async {
        do {
            let createdContact = try await walletManager.createContact(contact)
            print("✅ Successfully created contact: \(createdContact.displayName)")
            await loadContactsWithStatistics()
        } catch {
            print("❌ Failed to create contact: \(error)")
            errorMessage = "Failed to create contact: \(error.localizedDescription)"
        }
    }
    
    func updateContact(_ contact: ContactModel) async {
        do {
            try await walletManager.updateContact(contact)
            print("✅ Successfully updated contact: \(contact.displayName)")
            await loadContactsWithStatistics()
        } catch {
            print("❌ Failed to update contact: \(error)")
            errorMessage = "Failed to update contact: \(error.localizedDescription)"
        }
    }
    
    func deleteContact(_ contact: ContactModel) async {
        do {
            try await walletManager.deleteContact(contact.id)
            print("✅ Successfully deleted contact: \(contact.displayName)")
            await loadContactsWithStatistics()
        } catch {
            print("❌ Failed to delete contact: \(error)")
            errorMessage = "Failed to delete contact: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sheet Management
    
    func showNewContactEditor() {
        print("🔵 [ContactsViewModel.showNewContactEditor] Setting showingNewContactEditor to TRUE")
        showingNewContactEditor = true
        print("🔵 [ContactsViewModel.showNewContactEditor] showingNewContactEditor is now: \(showingNewContactEditor)")
    }
    
    func hideNewContactEditor() {
        showingNewContactEditor = false
    }
    
    func showEditContactEditor(for contact: ContactModel) {
        print("🔧 ContactsViewModel: Showing edit editor for contact: \(contact.displayName) (ID: \(contact.id))")
        editingContact = contact
    }
    
    func hideEditContactEditor() {
        print("🔧 ContactsViewModel: Hiding edit editor")
        editingContact = nil
    }
}
