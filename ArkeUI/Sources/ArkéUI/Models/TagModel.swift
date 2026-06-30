//
//  TagModel.swift
//  ArkéUI
//
//  Created by Assistant on 10/29/25.
//  Moved into ArkéUI as a pure presentation value type (no SwiftData/Bark).
//  Persistence bridging lives app-side in TagModel+Persistence.swift.
//

import SwiftUI

/// Pure value type describing a tag for display.
///
/// Holds no dependency on SwiftData, Bark, or app services, so it can be
/// constructed from sample data and rendered in previews in isolation.
/// Conversion to/from the persistent store is provided by the app via an
/// extension (`init(from:)` / `toPersistentTag()`).
public struct TagModel: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let emoji: String
    public let createdDate: Date
    public let isSystemTag: Bool

    public init(id: UUID = UUID(), name: String, colorHex: String, emoji: String, createdDate: Date = Date(), isSystemTag: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.emoji = emoji
        self.createdDate = createdDate
        self.isSystemTag = isSystemTag
    }

    // Computed property for SwiftUI Color
    public var color: Color {
        Color(hex: colorHex) ?? .Arke.blue
    }

    // Display name with emoji
    public var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }

    // Convert to TagAppearance for UI rendering
    public var appearance: TagAppearance {
        TagAppearance(name: name, color: color, emoji: emoji)
    }

    // For creating common tags
    public static func createDefaultTags() -> [TagModel] {
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
}

// MARK: - Sample Data

public extension TagModel {
    /// Stable sample values for previews and tests. No database or Bark required.
    static let sampleFood = TagModel(name: "Food", colorHex: "#D2AF1E", emoji: "🍕")
    static let sampleSavings = TagModel(name: "Savings", colorHex: "#DC8228", emoji: "💰")
    static let sampleSystem = TagModel(name: "Balance", colorHex: "#C33C2D", emoji: "👜", isSystemTag: true)

    static let samples: [TagModel] = [sampleSavings, sampleFood, sampleSystem]
}

// MARK: - Preview

#Preview("TagModel → TagChip") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(TagModel.samples) { tag in
            TagChip(tag: tag.appearance)
        }
    }
    .padding()
}
