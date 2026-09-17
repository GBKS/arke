//
//  ContactChip.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI

public enum ContactChipSize {
    case small
    case medium
    case large
    
    var fontSize: Font {
        switch self {
        case .small:
            return .caption2
        case .medium:
            return .subheadline
        case .large:
            return .body
        }
    }
    
    var avatarSize: CGFloat {
        switch self {
        case .small:
            return 12
        case .medium:
            return 16
        case .large:
            return 20
        }
    }
    
    // Used by pill-shaped variant.
    var leadingPadding: CGFloat {
        switch self {
        case .small:
            return 4
        case .medium:
            return 6
        case .large:
            return 8
        }
    }
    
    // Used by pill-shaped variant.
    var trailingPadding: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 12
        case .large:
            return 16
        }
    }
    
    // Used by selectable variant.
    var horizontalPadding: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 12
        case .large:
            return 16
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
        }
    }
    
    var spacing: CGFloat {
        switch self {
        case .small:
            return 6
        case .medium:
            return 8
        case .large:
            return 10
        }
    }
}

public struct ContactChip: View {
    let avatarData: Data?
    let displayName: String
    let notes: String?
    let isClickable: Bool
    let size: ContactChipSize
    let action: (() -> Void)?
    
    // Convenience initializers
    public init(avatarData: Data?, displayName: String, notes: String?, size: ContactChipSize = .medium, action: @escaping () -> Void) {
        self.avatarData = avatarData
        self.displayName = displayName
        self.notes = notes
        self.isClickable = true
        self.size = size
        self.action = action
    }
    
    public init(avatarData: Data?, displayName: String, notes: String?, size: ContactChipSize = .medium) {
        self.avatarData = avatarData
        self.displayName = displayName
        self.notes = notes
        self.isClickable = false
        self.size = size
        self.action = nil
    }
    
    public var body: some View {
        let chipContent = HStack(spacing: size.spacing) {
            // Avatar
            ContactAvatarView(avatarData: avatarData, size: size.avatarSize)
            
            Text(displayName)
                .font(size.fontSize)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.leading, size.leadingPadding)
        .padding(.trailing, size.trailingPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color.Arke.blue.opacity(0.1))
        .foregroundColor(.Arke.blue)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(Color.Arke.blue.opacity(0.3), lineWidth: 1)
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

public struct ContactChip_Selectable: View {
    let avatarData: Data?
    let displayName: String
    let notes: String?
    let size: ContactChipSize
    @Binding var isSelected: Bool
    let onToggle: (() -> Void)?
    
    public init(avatarData: Data?, displayName: String, notes: String?, size: ContactChipSize = .medium, isSelected: Binding<Bool>, onToggle: (() -> Void)? = nil) {
        self.avatarData = avatarData
        self.displayName = displayName
        self.notes = notes
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
                // Avatar - use a larger size for the selectable variant
                ContactAvatarView(avatarData: avatarData, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.body)
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    
                    if let notes = notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.Arke.gold)
                }
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.Arke.gold.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
    
    @State private var isPressed: Bool = false
}

public struct ContactChip_Removable: View {
    let avatarData: Data?
    let displayName: String
    let notes: String?
    let size: ContactChipSize
    let onRemove: () -> Void
    
    public init(avatarData: Data?, displayName: String, notes: String?, size: ContactChipSize = .medium, onRemove: @escaping () -> Void) {
        self.avatarData = avatarData
        self.displayName = displayName
        self.notes = notes
        self.size = size
        self.onRemove = onRemove
    }
    
    public var body: some View {
        HStack(spacing: size.spacing) {
            // Avatar
            ContactAvatarView(avatarData: avatarData, size: size.avatarSize)
            
            Text(displayName)
                .font(size.fontSize)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(size.fontSize)
                    .foregroundColor(.Arke.blue.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.leading, size.leadingPadding)
        .padding(.trailing, size.trailingPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color.Arke.blue.opacity(0.1))
        .foregroundColor(.Arke.blue)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(Color.Arke.blue.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

// MARK: - Preview Support

#Preview("Contact Chips") {
    ScrollView {
        VStack(spacing: 16) {
            // Different sizes - non-clickable
            VStack(alignment: .leading, spacing: 8) {
                Text("Small Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    ContactChip(avatarData: nil, displayName: "John Doe", notes: nil, size: .small)
                    ContactChip(avatarData: nil, displayName: "Jane Smith", notes: "Friend from work", size: .small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Medium Size (Default)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    ContactChip(avatarData: nil, displayName: "Alice Brown", notes: nil)
                    ContactChip(avatarData: nil, displayName: "Jane Smith", notes: "Colleague")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Large Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    ContactChip(avatarData: nil, displayName: "Bob Wilson", notes: nil, size: .large)
                    ContactChip(avatarData: nil, displayName: "Jane Smith", notes: "Old friend", size: .large)
                }
            }

            Divider()

            // Clickable chips with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Clickable - Small")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    ContactChip(avatarData: nil, displayName: "John Doe", notes: nil, size: .small) {
                        print("Contact tapped")
                    }
                    ContactChip(avatarData: nil, displayName: "Alice Brown", notes: nil, size: .small) {
                        print("Alice tapped")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clickable - Large")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    ContactChip(avatarData: nil, displayName: "Bob Wilson", notes: "Friend", size: .large) {
                        print("Contact tapped")
                    }
                }
            }

            Divider()

            // Selectable chips with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Selectable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ContactChip_Selectable(
                        avatarData: nil,
                        displayName: "John Doe",
                        notes: nil,
                        size: .small,
                        isSelected: .constant(false)
                    )
                    ContactChip_Selectable(
                        avatarData: nil,
                        displayName: "Bob Wilson",
                        notes: "Colleague",
                        size: .large,
                        isSelected: .constant(true)
                    )
                }
            }

            // Removable chip with different sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Removable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ContactChip_Removable(
                        avatarData: nil,
                        displayName: "Alice Brown",
                        notes: nil,
                        size: .small
                    ) {
                        print("Remove contact")
                    }
                    ContactChip_Removable(
                        avatarData: nil,
                        displayName: "Jane Smith",
                        notes: "Friend",
                        size: .medium
                    ) {
                        print("Remove contact")
                    }
                    ContactChip_Removable(
                        avatarData: nil,
                        displayName: "Alice Brown",
                        notes: "Colleague",
                        size: .large
                    ) {
                        print("Remove contact")
                    }
                }
            }
        }
        .padding()
    }
}
