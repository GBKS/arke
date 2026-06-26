//
//  TagChip.swift
//  ArkéUI
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

// MARK: - Data Model

/// Lightweight data model for rendering tag chips
/// This keeps the component free of domain dependencies
public struct TagAppearance {
    public let name: String
    public let color: Color
    public let emoji: String

    public init(name: String, color: Color, emoji: String) {
        self.name = name
        self.color = color
        self.emoji = emoji
    }
}

// MARK: - Size Configuration

public enum TagChipSize {
    case small
    case medium
    case large
    case huge

    var fontSize: Font {
        switch self {
        case .small:
            return .caption2
        case .medium:
            return .subheadline
        case .large:
            return .body
        case .huge:
            return .title3
        }
    }

    var emojiSize: Font {
        switch self {
        case .small:
            return .system(size: 10)
        case .medium:
            return .caption2
        case .large:
            return .caption
        case .huge:
            return .body
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:
            return 6
        case .medium:
            return 8
        case .large:
            return 12
        case .huge:
            return 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small:
            return 3
        case .medium:
            return 4
        case .large:
            return 6
        case .huge:
            return 8
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 12
        case .large:
            return 16
        case .huge:
            return 20
        }
    }

    var spacing: CGFloat {
        switch self {
        case .small:
            return 3
        case .medium:
            return 4
        case .large:
            return 6
        case .huge:
            return 6
        }
    }
}

// MARK: - Basic TagChip

public struct TagChip: View {
    let tag: TagAppearance
    let isClickable: Bool
    let size: TagChipSize
    let action: (() -> Void)?

    // Convenience initializers
    public init(tag: TagAppearance, size: TagChipSize = .medium, action: @escaping () -> Void) {
        self.tag = tag
        self.isClickable = true
        self.size = size
        self.action = action
    }

    public init(tag: TagAppearance, size: TagChipSize = .medium) {
        self.tag = tag
        self.isClickable = false
        self.size = size
        self.action = nil
    }

    public var body: some View {
        let chipContent = HStack(spacing: size.spacing) {
            if !tag.emoji.isEmpty {
                Text(tag.emoji)
                    .font(size.emojiSize)
            }

            Text(tag.name)
                .font(size.fontSize)
                .fontWeight(.medium)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(tag.color.opacity(0.2))
        .foregroundColor(tag.color)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(tag.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))

        if isClickable {
            Button(action: {
                action?()
            }) {
                chipContent
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
        } else {
            chipContent
        }
    }

    @State private var isPressed: Bool = false
}

// MARK: - Selectable Variant

public struct TagChip_Selectable: View {
    let tag: TagAppearance
    let size: TagChipSize
    @Binding var isSelected: Bool
    let onToggle: (() -> Void)?

    public init(tag: TagAppearance, size: TagChipSize = .medium, isSelected: Binding<Bool>, onToggle: (() -> Void)? = nil) {
        self.tag = tag
        self.size = size
        self._isSelected = isSelected
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: {
            isSelected.toggle()
            onToggle?()
        }) {
            HStack(spacing: size.spacing) {
                if !tag.emoji.isEmpty {
                    Text(tag.emoji)
                        .font(size.emojiSize)
                }

                Text(tag.name)
                    .font(size.fontSize)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(isSelected ? tag.color.opacity(0.3) : tag.color.opacity(0.1))
            .foregroundColor(isSelected ? tag.color : tag.color.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(
                        isSelected ? tag.color : tag.color.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(size.emojiSize)
                        .foregroundColor(tag.color)
                        .background(
                            Circle()
                                .fill(.background)
                                .padding(1)
                        )
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }

    @State private var isPressed: Bool = false
}

// MARK: - Removable Variant

public struct TagChip_Removable: View {
    let tag: TagAppearance
    let size: TagChipSize
    let onRemove: () -> Void

    public init(tag: TagAppearance, size: TagChipSize = .medium, onRemove: @escaping () -> Void) {
        self.tag = tag
        self.size = size
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: size.spacing) {
            if !tag.emoji.isEmpty {
                Text(tag.emoji)
                    .font(size.emojiSize)
            }

            Text(tag.name)
                .font(size.fontSize)
                .fontWeight(.medium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(size.emojiSize)
                    .foregroundColor(tag.color.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(tag.color.opacity(0.2))
        .foregroundColor(tag.color)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(tag.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

// MARK: - Preview Support

#Preview("Basic TagChip") {
    ScrollView {
        VStack(spacing: 16) {
            // Different sizes - non-clickable
            VStack(alignment: .leading, spacing: 8) {
                Text("Small Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Coffee", color: Color(hex: "#8B4513") ?? .brown, emoji: "☕"), size: .small)
                    TagChip(tag: TagAppearance(name: "Food", color: Color(hex: "#FF6B35") ?? .orange, emoji: "🍕"), size: .small)
                    TagChip(tag: TagAppearance(name: "Transport", color: Color(hex: "#4A90E2") ?? .blue, emoji: "🚗"), size: .small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Medium Size (Default)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Coffee", color: Color(hex: "#8B4513") ?? .brown, emoji: "☕"))
                    TagChip(tag: TagAppearance(name: "Food", color: Color(hex: "#FF6B35") ?? .orange, emoji: "🍕"))
                    TagChip(tag: TagAppearance(name: "Transport", color: Color(hex: "#4A90E2") ?? .blue, emoji: "🚗"))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Large Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Coffee", color: Color(hex: "#8B4513") ?? .brown, emoji: "☕"), size: .large)
                    TagChip(tag: TagAppearance(name: "Food", color: Color(hex: "#FF6B35") ?? .orange, emoji: "🍕"), size: .large)
                    TagChip(tag: TagAppearance(name: "Transport", color: Color(hex: "#4A90E2") ?? .blue, emoji: "🚗"), size: .large)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Huge Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Coffee", color: Color(hex: "#8B4513") ?? .brown, emoji: "☕"), size: .huge)
                    TagChip(tag: TagAppearance(name: "Food", color: Color(hex: "#FF6B35") ?? .orange, emoji: "🍕"), size: .huge)
                    TagChip(tag: TagAppearance(name: "Transport", color: Color(hex: "#4A90E2") ?? .blue, emoji: "🚗"), size: .huge)
                }
            }

            Divider()

            // Clickable chips with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Clickable - Small")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Shopping", color: Color(hex: "#7B68EE") ?? .purple, emoji: "🛒"), size: .small) {
                        print("Shopping tapped")
                    }
                    TagChip(tag: TagAppearance(name: "Bills", color: Color(hex: "#FF4444") ?? .red, emoji: "📄"), size: .small) {
                        print("Bills tapped")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clickable - Large")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Income", color: Color(hex: "#32CD32") ?? .green, emoji: "💰"), size: .large) {
                        print("Income tapped")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clickable - Huge")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip(tag: TagAppearance(name: "Income", color: Color(hex: "#32CD32") ?? .green, emoji: "💰"), size: .huge) {
                        print("Income tapped")
                    }
                }
            }

            Divider()

            // Selectable chips with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Selectable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip_Selectable(
                        tag: TagAppearance(name: "Investment", color: Color(hex: "#FFD700") ?? .yellow, emoji: "📈"),
                        size: .small,
                        isSelected: .constant(false)
                    )
                    TagChip_Selectable(
                        tag: TagAppearance(name: "Gift", color: Color(hex: "#FF69B4") ?? .pink, emoji: "🎁"),
                        size: .large,
                        isSelected: .constant(true)
                    )
                    TagChip_Selectable(
                        tag: TagAppearance(name: "Savings", color: Color(hex: "#20B2AA") ?? .teal, emoji: "🏦"),
                        size: .huge,
                        isSelected: .constant(true)
                    )
                }
            }

            // Removable chip with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Removable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TagChip_Removable(
                        tag: TagAppearance(name: "Custom", color: Color(hex: "#9370DB") ?? .purple, emoji: "⭐"),
                        size: .small
                    ) {
                        print("Remove custom tag")
                    }
                    TagChip_Removable(
                        tag: TagAppearance(name: "Premium", color: Color(hex: "#FF8C00") ?? .orange, emoji: "💎"),
                        size: .large
                    ) {
                        print("Remove premium tag")
                    }
                    TagChip_Removable(
                        tag: TagAppearance(name: "Featured", color: Color(hex: "#DB7093") ?? .pink, emoji: "🌟"),
                        size: .huge
                    ) {
                        print("Remove featured tag")
                    }
                }
            }
        }
        .padding()
    }
}
