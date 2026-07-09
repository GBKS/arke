//
//  EmojiPickerGrid.swift
//  ArkéUI
//
//  Created by Assistant on 7/9/26.
//  Inline replacement for the former EmojiPickerSheet.
//

import SwiftUI

/// Inline emoji picker shown below the tag preview in the tag editor.
/// Selecting an emoji updates the binding but keeps the grid open so
/// the user can keep experimenting.
public struct EmojiPickerGrid: View {
    @Binding var selectedEmoji: String

    public init(selectedEmoji: Binding<String>) {
        self._selectedEmoji = selectedEmoji
    }

    // Common emoji categories for tags. The first tuple element is a
    // localization key resolved against the package bundle.
    private static let emojiCategories = [
        ("emoji_category_food_drink", ["☕", "🍕", "🍔", "🍎", "🍰", "🍜", "🍺", "🥗", "🍩", "🍳"]),
        ("emoji_category_transportation", ["🚗", "🚌", "✈️", "🚂", "🚲", "🛴", "🚁", "⛽", "🚕", "🛻"]),
        ("emoji_category_shopping", ["🛒", "🛍️", "👕", "👟", "📱", "💻", "🎮", "📚", "🛏️", "🪑"]),
        ("emoji_category_money", ["💰", "💳", "💎", "🏦", "📈", "📊", "💸", "🪙", "💵", "🧾"]),
        ("emoji_category_activities", ["⚽", "🏀", "🎵", "🎬", "🎨", "📖", "🎯", "🎲", "🏃", "🏋️"]),
        ("emoji_category_objects", ["📄", "📱", "💻", "⌚", "🎁", "🔑", "💡", "🛠️", "📋", "🗂️"]),
        ("emoji_category_symbols", ["⭐", "❤️", "✅", "❌", "⚠️", "🔥", "💯", "✨", "🎯", "📍"])
    ]

    /// A random emoji from the picker's catalog, used to seed new tags
    /// (tags always have an emoji).
    public static func randomEmoji() -> String {
        emojiCategories.flatMap(\.1).randomElement() ?? "⭐"
    }

    public var body: some View {
        LazyVStack(alignment: .center, spacing: 15) {
            ForEach(Self.emojiCategories, id: \.0) { category in
                VStack(alignment: .center, spacing: 15) {
                    Text(LocalizedStringKey(category.0), bundle: .module)
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(category.1, id: \.self) { emoji in
                            Button(action: {
                                selectedEmoji = emoji
                            }) {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        selectedEmoji == emoji ? Color.Arke.gold.opacity(0.2) : Color.systemBackground
                                    )
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(selectedEmoji == emoji ? Color.Arke.gold : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedEmoji == emoji ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color.systemControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

#Preview {
    @Previewable @State var selectedEmoji = "📱"

    ScrollView {
        EmojiPickerGrid(selectedEmoji: $selectedEmoji)
            .padding()
    }
}
