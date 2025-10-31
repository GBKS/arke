//
//  TagValidation.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import SwiftUI

struct TagValidation {
    let name: String
    let existingTags: [TagModel]
    let editingTagId: UUID?
    
    init(name: String, existingTags: [TagModel], editingTagId: UUID? = nil) {
        self.name = name
        self.existingTags = existingTags
        self.editingTagId = editingTagId
    }
    
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isValidName: Bool {
        !trimmedName.isEmpty && name.count <= 30
    }
    
    var nameExists: Bool {
        existingTags.contains { existingTag in
            existingTag.name.lowercased() == trimmedName.lowercased() && 
            existingTag.id != editingTagId
        }
    }
    
    var canSave: Bool {
        isValidName && !nameExists
    }
    
    var nameCharacterCountColor: Color {
        name.count > 25 ? .orange : .secondary
    }
    
    // MARK: - Static Methods
    
    static func suggestRandomColor() -> String {
        let colors = [
            "#FF6B35", "#4A90E2", "#7B68EE", "#32CD32", 
            "#FFD700", "#FF69B4", "#8B4513", "#FF4444",
            "#9370DB", "#20B2AA", "#FF8C00", "#6495ED"
        ]
        return colors.randomElement() ?? "#4A90E2"
    }
}

// MARK: - Color Extension

extension Color {
    static var secondary: Color {
        Color(NSColor.secondaryLabelColor)
    }
}
