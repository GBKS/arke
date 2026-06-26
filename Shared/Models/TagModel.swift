//
//  TagModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/29/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct TagModel: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let emoji: String
    let createdDate: Date
    let isSystemTag: Bool
    
    init(id: UUID = UUID(), name: String, colorHex: String, emoji: String, createdDate: Date = Date(), isSystemTag: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.emoji = emoji
        self.createdDate = createdDate
        self.isSystemTag = isSystemTag
    }
    
    // Initialize from persistent tag
    init(from persistentTag: PersistentTag) {
        self.id = persistentTag.id
        self.name = persistentTag.name
        self.colorHex = persistentTag.colorHex
        self.emoji = persistentTag.emoji
        self.createdDate = persistentTag.createdDate
        self.isSystemTag = persistentTag.isSystemTag
    }
    
    // Computed property for SwiftUI Color
    var color: Color {
        Color(hex: colorHex) ?? .Arke.blue
    }
    
    // Display name with emoji
    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
    
    // Convert to TagAppearance for UI rendering
    var appearance: TagAppearance {
        TagAppearance(name: name, color: color, emoji: emoji)
    }
    
    // For creating common tags
    static func createDefaultTags() -> [TagModel] {
        return [
            TagModel(name: "Savings", colorHex: "#DC8228", emoji: "💰"),
            TagModel(name: "Food", colorHex: "#D2AF1E", emoji: "🍕"),
            TagModel(name: "Transport", colorHex: "#2FA854", emoji: "🚗"),
            TagModel(name: "Shopping", colorHex: "#288C82", emoji: "🛒"),
            TagModel(name: "Bills", colorHex: "#2A7FAF", emoji: "📄"),
            TagModel(name: "Income", colorHex: "#4B50A0", emoji: "💰"),
            TagModel(name: "Investment", colorHex: "#6E468C", emoji: "📈"),
            TagModel(name: "Gift", colorHex: "#BE5069", emoji: "🎁"),
            TagModel(name: "Balance", colorHex: "#C33C2D", emoji: "👜", isSystemTag: true)
        ]
    }
    
    // Convert to persistent model
    func toPersistentTag() -> PersistentTag {
        return PersistentTag(
            id: self.id,
            name: self.name,
            colorHex: self.colorHex,
            emoji: self.emoji,
            createdDate: self.createdDate,
            isSystemTag: self.isSystemTag
        )
    }
}
