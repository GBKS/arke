//
//  TagValidation.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import SwiftUI
import ArkeUI

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
            "#DC8228", "#D2AF1E", "#2FA854", "#288C82",
            "#2A7FAF", "#4B50A0", "#6E468C", "#BE5069",
            "#C33C2D"
        ]
        return colors.randomElement() ?? "#2A7FAF"
    }
}
