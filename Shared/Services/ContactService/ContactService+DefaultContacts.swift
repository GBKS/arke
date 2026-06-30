//
//  ContactService+DefaultContacts.swift
//  Arké
//
//  Default contact creation (Faucetto Signetto)
//

import Foundation
import ArkeUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension ContactService {
    
    /// Create default contacts if none exist
    func createDefaultContactsIfNeeded() async {
        // Check if we should create default contacts
        // Only create if no contacts exist at all
        guard contactCount == 0 else {
            print("ℹ️ Contacts already exist, skipping default contact creation")
            return
        }
        
        await taskManager.execute(key: "createDefaultContacts") {
            await self.performCreateDefaultContacts()
        }
    }
    
    // Faucetto Signetto is a default contact for signet testing
    private func performCreateDefaultContacts() async {
        guard let modelContext = modelContext else {
            print("❌ Cannot create default contacts: no model context")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            var avatarData: Data?
            
            #if os(iOS)
            if let image = UIImage(named: "faucetto-signetto"),
               let imageData = image.pngData() {
                avatarData = imageData
            }
            #elseif os(macOS)
            if let image = NSImage(named: "faucetto-signetto"),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                if let imageData = bitmapRep.representation(using: .png, properties: [:]) {
                    avatarData = imageData
                }
            }
            #endif
            
            // Create "Faucetto Signetto" system contact
            let defaultContact = ContactModel(
                cachedName: "Faucetto Signetto",
                notes: "I'll help you test Arké. You can request free test bitcoin from me, and send me some back.",
                avatarData: avatarData,
                contactType: .faucet
            )
            
            // Create the contact
            let persistentContact = defaultContact.toPersistentContact()
            modelContext.insert(persistentContact)
            
            // Save to get the contact persisted before adding addresses
            try modelContext.save()
            
            print("✅ Created default system contact: \(defaultContact.cachedName)")
            
            // Now add addresses using ContactAddressService
            // We need to get the service from the ServiceContainer
            let contactAddressService = ServiceContainer.shared.contactAddressService
            
            // Placeholder Ark address (signet format)
            // This is a valid signet Ark address format - replace with actual faucet address
            //let arkAddress = "tark1pem36wcfzqqpsp9x4spq03lgxz0ypsh36553g5ruj8te8w7wgehx7h4a58q2emxezqyphvs9qmw3et6eutxx6netps535rdr8c5mjv2703sc50e96s4f9qygx5rkzk"
            
            // Placeholder Bitcoin signet address (tb1q format)
            //let onchainAddress = "tb1ptg6t5dqn0dq6z2sj56zkakzfrvynr38pa4lhdkhuq0tpc9wdmdtqd53lwz"
            
            // BIP-353 address for dynamic address resolution
            let bip353Address = "₿faucetto@sto.ph"
            
            // Add BIP-353 address for dynamic resolution (primary)
            do {
                let bip353AddressModel = try await contactAddressService.validateAndCreateAddress(
                    bip353Address,
                    for: persistentContact.id,
                    label: "Primary Address",
                    isPrimary: true
                )
                print("✅ Added BIP-353 address to contact: \(bip353AddressModel.shortAddress)")
            } catch {
                print("⚠️ Failed to add BIP-353 address to default contact: \(error)")
                // Continue even if address creation fails
            }
            
            /*
            
            // Add Ark address
            do {
                let arkAddressModel = try await contactAddressService.validateAndCreateAddress(
                    arkAddress,
                    for: persistentContact.id,
                    label: "Ark Address",
                    isPrimary: true
                )
                print("✅ Added primary Ark address to contact: \(arkAddressModel.shortAddress)")
            } catch {
                print("⚠️ Failed to add Ark address to default contact: \(error)")
                // Continue even if address creation fails
            }
            
            // Add onchain address
            do {
                let onchainAddressModel = try await contactAddressService.validateAndCreateAddress(
                    onchainAddress,
                    for: persistentContact.id,
                    label: "Onchain Address",
                    isPrimary: false
                )
                print("✅ Added onchain address to contact: \(onchainAddressModel.shortAddress)")
            } catch {
                print("⚠️ Failed to add onchain address to default contact: \(error)")
                // Continue even if address creation fails
            }
             */
            
            // Reload contacts to update the in-memory cache with addresses
            await loadContacts()
            
            print("✅ Default contact setup complete")
            
        } catch {
            print("❌ Failed to create default contacts: \(error)")
            self.error = "Failed to create default contacts: \(error)"
        }
    }
}
