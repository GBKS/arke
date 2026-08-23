//
//  NativeContactService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/11/25.
//

import Foundation
import Contacts
import ArkeUI

/// Service for interacting with macOS native Contacts
@MainActor
class NativeContactService {
    
    // MARK: - Properties
    
    private let contactStore = CNContactStore()
    
    // Keys to fetch from CNContact
    private let keysToFetch: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNamePrefixKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNameSuffixKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor
    ]
    
    // MARK: - Permission Management
    
    /// Get current authorization status
    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }
    
    /// Request access to contacts
    func requestAccess() async -> Bool {
        print("📞 Requesting contacts access...")
        print("📞 Current status: \(authorizationStatus().rawValue)")
        print("📞 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("📞 Info.plist has usage description: \(Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil)")
        
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        // If already determined (granted or denied), return that
        if status == .authorized {
            print("📞 Already authorized")
            return true
        }
        
        if status == .denied || status == .restricted {
            print("📞 Already denied or restricted")
            return false
        }
        
        // Request permission (already on main actor since class is @MainActor)
        print("📞 Requesting permission dialog...")
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            print("📞 Access granted: \(granted)")
            print("📞 New status: \(CNContactStore.authorizationStatus(for: .contacts).rawValue)")
            return granted
        } catch {
            print("❌ Failed to request contacts access: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            return false
        }
    }
    
    /// Check if we have permission to access contacts
    func hasPermission() -> Bool {
        authorizationStatus() == .authorized
    }
    
    // MARK: - Contact Search
    
    /// Search contacts by name query
    func searchContacts(query: String) async throws -> [ContactSearchResult] {
        guard hasPermission() else {
            throw NativeContactError.permissionDenied
        }
        
        // Capture main-actor isolated properties before moving to background thread
        let store = contactStore
        let keys = keysToFetch
        
        // Perform search on background thread using Task instead of Task.detached
        // to inherit priority and avoid priority inversion
        let contacts = try await Task {
            let predicate: NSPredicate
            if query.isEmpty {
                // Fetch all contacts if query is empty
                predicate = CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier())
            } else {
                // Search by name
                predicate = CNContact.predicateForContacts(matchingName: query)
            }
            
            return try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        }.value
        
        // Convert to search results on main actor
        return contacts.map { contact in
            ContactSearchResult(
                id: contact.identifier,
                fullName: formatFullName(from: contact),
                imageData: extractImageData(from: contact)
            )
        }
        .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }
    
    /// Fetch all contacts (useful for browsing)
    func fetchAllContacts() async throws -> [ContactSearchResult] {
        return try await searchContacts(query: "")
    }
    
    // MARK: - Specific Contact Operations
    
    /// Fetch a single contact by identifier
    func fetchContact(identifier: String) async throws -> CNContact? {
        guard hasPermission() else {
            throw NativeContactError.permissionDenied
        }
        
        // Capture main-actor isolated properties before moving to background thread
        let store = contactStore
        let keys = keysToFetch
        
        return try await Task {
            do {
                return try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            } catch let error as NSError {
                if error.domain == CNErrorDomain && error.code == CNError.recordDoesNotExist.rawValue {
                    return nil
                }
                throw error
            }
        }.value
    }
    
    /// Check if a contact still exists
    func contactExists(identifier: String) async -> Bool {
        do {
            let contact = try await fetchContact(identifier: identifier)
            return contact != nil
        } catch {
            return false
        }
    }
    
    /// Extract contact data for import
    func extractContactData(from contact: CNContact) -> ImportedContactData {
        return ImportedContactData(
            identifier: contact.identifier,
            fullName: formatFullName(from: contact),
            imageData: extractImageData(from: contact)
        )
    }
    
    /// Extract contact data by identifier
    func extractContactData(identifier: String) async throws -> ImportedContactData? {
        guard let contact = try await fetchContact(identifier: identifier) else {
            return nil
        }
        return extractContactData(from: contact)
    }
    
    // MARK: - Helper Methods
    
    /// Format full name from CNContact components
    private func formatFullName(from contact: CNContact) -> String {
        var components: [String] = []
        
        if !contact.namePrefix.isEmpty {
            components.append(contact.namePrefix)
        }
        if !contact.givenName.isEmpty {
            components.append(contact.givenName)
        }
        if !contact.middleName.isEmpty {
            components.append(contact.middleName)
        }
        if !contact.familyName.isEmpty {
            components.append(contact.familyName)
        }
        if !contact.nameSuffix.isEmpty {
            components.append(contact.nameSuffix)
        }
        
        let fullName = components.joined(separator: " ")
        return fullName.isEmpty ? "Unnamed Contact" : fullName
    }
    
    /// Extract image data from CNContact (prefer thumbnail for performance)
    private func extractImageData(from contact: CNContact) -> Data? {
        // Prefer thumbnail for better performance (already avatar-sized)
        if let thumbnailData = contact.thumbnailImageData {
            return thumbnailData
        }

        // Fall back to the full image, downscaled — raw imageData is
        // photo-library resolution and would bloat the store and CloudKit
        if contact.imageDataAvailable, let imageData = contact.imageData {
            return AvatarImageProcessor.processedData(from: imageData)
        }

        return nil
    }
}

// MARK: - Supporting Types

/// Lightweight search result for contact picker
struct ContactSearchResult: Identifiable, Hashable {
    let id: String              // CNContact.identifier
    let fullName: String
    let imageData: Data?
    
    /// Display name with fallback
    var displayName: String {
        fullName.isEmpty ? "Unnamed Contact" : fullName
    }
}

/// Extracted data ready for import into app
struct ImportedContactData {
    let identifier: String      // CNContact.identifier
    let fullName: String
    let imageData: Data?
}

// MARK: - Error Handling

enum NativeContactError: LocalizedError {
    case permissionDenied
    case contactNotFound(String)
    case serviceUnavailable
    case searchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission to access contacts was denied. Please enable access in System Settings."
        case .contactNotFound(let identifier):
            return "Contact with identifier \(identifier) not found."
        case .serviceUnavailable:
            return "Contact service is unavailable."
        case .searchFailed(let error):
            return "Failed to search contacts: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to System Settings > Privacy & Security > Contacts and enable access for this app."
        default:
            return nil
        }
    }
}
