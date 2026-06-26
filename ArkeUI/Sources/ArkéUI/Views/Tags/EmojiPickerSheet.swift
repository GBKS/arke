//
//  EmojiPickerSheet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI

public struct EmojiPickerSheet: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss

    public init(selectedEmoji: Binding<String>) {
        self._selectedEmoji = selectedEmoji
    }

    // Common emoji categories for tags. The first tuple element is a
    // localization key resolved against the package bundle.
    private let emojiCategories = [
        ("emoji_category_recent", ["☕", "🍕", "🚗", "🛒", "📄", "💰", "📈", "🎁"]),
        ("emoji_category_food_drink", ["☕", "🍕", "🍔", "🍎", "🍰", "🍜", "🍺", "🥗", "🍩", "🍳"]),
        ("emoji_category_transportation", ["🚗", "🚌", "✈️", "🚂", "🚲", "🛴", "🚁", "⛽", "🚕", "🛻"]),
        ("emoji_category_shopping", ["🛒", "🛍️", "👕", "👟", "📱", "💻", "🎮", "📚", "🛏️", "🪑"]),
        ("emoji_category_money", ["💰", "💳", "💎", "🏦", "📈", "📊", "💸", "🪙", "💵", "🧾"]),
        ("emoji_category_activities", ["⚽", "🏀", "🎵", "🎬", "🎨", "📖", "🎯", "🎲", "🏃", "🏋️"]),
        ("emoji_category_objects", ["📄", "📱", "💻", "⌚", "🎁", "🔑", "💡", "🛠️", "📋", "🗂️"]),
        ("emoji_category_symbols", ["⭐", "❤️", "✅", "❌", "⚠️", "🔥", "💯", "✨", "🎯", "📍"])
    ]
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(emojiCategories, id: \.0) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringKey(category.0), bundle: .module)
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 5) {
                                ForEach(category.1, id: \.self) { emoji in
                                    Button(action: {
                                        selectedEmoji = emoji
                                        dismiss()
                                    }) {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                selectedEmoji == emoji ? Color.Arke.blue.opacity(0.2) : Color.clear
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(selectedEmoji == emoji ? [.isButton, .isSelected] : .isButton)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Text("button_choose_emoji", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(Text("button_done", bundle: .module))
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedEmoji = "📱"
    
    EmojiPickerSheet(selectedEmoji: $selectedEmoji)
}
