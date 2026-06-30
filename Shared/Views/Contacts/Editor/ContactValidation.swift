//
//  ContactValidation.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/04/25.
//

import Foundation
import ArkeUI

/// Validation logic for contact data
struct ContactValidation {
    let name: String
    let notes: String?
    let existingContacts: [ContactModel]
    let editingContactId: UUID?
    
    // MARK: - Validation Rules
    
    var isValidName: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName.count <= 50
    }
    
    var nameExists: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return existingContacts.contains { existingContact in
            existingContact.cachedName.lowercased() == trimmedName.lowercased() &&
            existingContact.id != editingContactId
        }
    }
    
    var isValidNotes: Bool {
        guard let notes = notes else { return true }
        return notes.count <= 500
    }
    
    var isValid: Bool {
        isValidName && !nameExists && isValidNotes
    }
    
    // MARK: - Error Messages
    
    var nameError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return "Name is required"
        }
        
        if trimmedName.count > 50 {
            return "Name must be 50 characters or less"
        }
        
        if nameExists {
            return "A contact with this name already exists"
        }
        
        return nil
    }
    
    var notesError: String? {
        guard let notes = notes else { return nil }
        
        if notes.count > 500 {
            return "Notes must be 500 characters or less"
        }
        
        return nil
    }
}