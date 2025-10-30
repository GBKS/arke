//
//  EmojiPickerSheet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI

struct EmojiPickerSheet: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss
    
    // Common emoji categories for tags
    private let emojiCategories = [
        ("Recent", ["☕", "🍕", "🚗", "🛒", "📄", "💰", "📈", "🎁"]),
        ("Food & Drink", ["☕", "🍕", "🍔", "🍎", "🍰", "🍜", "🍺", "🥗", "🍩", "🍳"]),
        ("Transportation", ["🚗", "🚌", "✈️", "🚂", "🚲", "🛴", "🚁", "⛽", "🚕", "🛻"]),
        ("Shopping", ["🛒", "🛍️", "👕", "👟", "📱", "💻", "🎮", "📚", "🛏️", "🪑"]),
        ("Money", ["💰", "💳", "💎", "🏦", "📈", "📊", "💸", "🪙", "💵", "🧾"]),
        ("Activities", ["⚽", "🏀", "🎵", "🎬", "🎨", "📖", "🎯", "🎲", "🏃", "🏋️"]),
        ("Objects", ["📄", "📱", "💻", "⌚", "🎁", "🔑", "💡", "🛠️", "📋", "🗂️"]),
        ("Symbols", ["⭐", "❤️", "✅", "❌", "⚠️", "🔥", "💯", "✨", "🎯", "📍"])
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(emojiCategories, id: \.0) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.0)
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(category.1, id: \.self) { emoji in
                                    Button(action: {
                                        selectedEmoji = emoji
                                        dismiss()
                                    }) {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Choose Emoji")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
