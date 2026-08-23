//
//  ContactService+BulkOperations.swift
//  Arké
//
//  Bulk operations for managing multiple contacts
//

import Foundation
import SwiftData
import ArkeUI

extension ContactService {
    
    /// Delete all contacts, their addresses, and their assignments from SwiftData
    /// This is used during wallet deletion when user chooses to delete all cloud data
    func deleteAllContacts() async throws {
        return try await taskManager.execute(key: "deleteAllContacts") {
            try await self.performDeleteAllContacts()
        }
    }
    
    private func performDeleteAllContacts() async throws {
        guard let modelContext = modelContext else {
            throw ContactServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch all contacts
            let descriptor = FetchDescriptor<PersistentContact>()
            let allContacts = try modelContext.fetch(descriptor)
            
            guard !allContacts.isEmpty else {
                print("ℹ️ [ContactService] No contacts to delete")
                return
            }
            
            let contactCount = allContacts.count
            
            // Count addresses and assignments before deletion
            var totalAddresses = 0
            var totalAssignments = 0
            for contact in allContacts {
                totalAddresses += contact.addresses?.count ?? 0
                totalAssignments += contact.contactAssignments?.count ?? 0
            }
            
            // Delete all contacts (cascade will handle addresses and assignments)
            for contact in allContacts {
                modelContext.delete(contact)
            }
            
            // Save changes
            try modelContext.save()
            
            // Clear local array
            contacts.removeAll()
            
            print("🗑️ [ContactService] Deleted \(contactCount) contacts, \(totalAddresses) addresses, and \(totalAssignments) contact assignments from SwiftData")
            
        } catch {
            print("❌ [ContactService] Failed to delete all contacts: \(error)")
            self.error = "Failed to delete all contacts: \(error)"
            throw error
        }
    }

    // MARK: - Avatar Maintenance

    /// One-time pass that re-encodes oversized stored avatars down to the
    /// standard avatar size (512px JPEG). Historical write paths stored raw
    /// native-contact photos and the full-resolution faucet PNG; this shrinks
    /// existing wallets' SwiftData store, CloudKit payloads, and metadata
    /// exports. Gated by a UserDefaults flag so the avatar blobs are only
    /// loaded once per install.
    func reencodeOversizedAvatarsIfNeeded() async {
        let flagKey = "ContactService.avatarReencodePass.v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        guard let modelContext = modelContext else { return }

        do {
            let allContacts = try modelContext.fetch(FetchDescriptor<PersistentContact>())
            var reencodedCount = 0

            for contact in allContacts {
                guard let data = contact.avatarData,
                      data.count > AvatarImageProcessor.oversizedThresholdBytes,
                      let processed = AvatarImageProcessor.processedData(from: data),
                      processed.count < data.count else { continue }

                contact.avatarData = processed
                contact.touch()
                reencodedCount += 1
                print("🖼️ [ContactService] Re-encoded avatar for '\(contact.cachedName)': \(data.count) → \(processed.count) bytes")
            }

            if reencodedCount > 0 {
                try modelContext.save()
                await loadContacts()
                print("✅ [ContactService] Avatar re-encode pass complete: \(reencodedCount) avatar(s) shrunk")
            }

            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // Don't set the flag — retry on next launch
            print("⚠️ [ContactService] Avatar re-encode pass failed: \(error)")
        }
    }
}
