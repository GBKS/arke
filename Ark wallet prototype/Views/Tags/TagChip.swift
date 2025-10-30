//
//  TagChip.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

struct TagChip: View {
    let tag: TagModel
    let isClickable: Bool
    let action: (() -> Void)?
    
    // Convenience initializers
    init(tag: TagModel, action: @escaping () -> Void) {
        self.tag = tag
        self.isClickable = true
        self.action = action
    }
    
    init(tag: TagModel) {
        self.tag = tag
        self.isClickable = false
        self.action = nil
    }
    
    var body: some View {
        let chipContent = HStack(spacing: 4) {
            if !tag.emoji.isEmpty {
                Text(tag.emoji)
                    .font(.caption2)
            }
            
            Text(tag.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.opacity(0.2))
        .foregroundColor(tag.color)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tag.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        
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

// MARK: - Alternative implementations for different use cases

struct TagChip_Selectable: View {
    let tag: TagModel
    @Binding var isSelected: Bool
    let onToggle: (() -> Void)?
    
    init(tag: TagModel, isSelected: Binding<Bool>, onToggle: (() -> Void)? = nil) {
        self.tag = tag
        self._isSelected = isSelected
        self.onToggle = onToggle
    }
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
            onToggle?()
        }) {
            HStack(spacing: 4) {
                if !tag.emoji.isEmpty {
                    Text(tag.emoji)
                        .font(.caption2)
                }
                
                Text(tag.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(tag.color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? tag.color.opacity(0.3) : tag.color.opacity(0.1))
            .foregroundColor(isSelected ? tag.color : tag.color.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? tag.color : tag.color.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
    
    @State private var isPressed: Bool = false
}

struct TagChip_Removable: View {
    let tag: TagModel
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            if !tag.emoji.isEmpty {
                Text(tag.emoji)
                    .font(.caption2)
            }
            
            Text(tag.name)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(tag.color.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.opacity(0.2))
        .foregroundColor(tag.color)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tag.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview Support

#Preview("Basic TagChip") {
    VStack(spacing: 16) {
        // Non-clickable chips
        HStack {
            TagChip(tag: TagModel(name: "Coffee", colorHex: "#8B4513", emoji: "☕"))
            TagChip(tag: TagModel(name: "Food", colorHex: "#FF6B35", emoji: "🍕"))
            TagChip(tag: TagModel(name: "Transport", colorHex: "#4A90E2", emoji: "🚗"))
        }
        
        // Clickable chips
        HStack {
            TagChip(tag: TagModel(name: "Shopping", colorHex: "#7B68EE", emoji: "🛒")) {
                print("Shopping tapped")
            }
            TagChip(tag: TagModel(name: "Bills", colorHex: "#FF4444", emoji: "📄")) {
                print("Bills tapped")
            }
            TagChip(tag: TagModel(name: "Income", colorHex: "#32CD32", emoji: "💰")) {
                print("Income tapped")
            }
        }
        
        // Selectable chips
        HStack {
            TagChip_Selectable(
                tag: TagModel(name: "Investment", colorHex: "#FFD700", emoji: "📈"),
                isSelected: .constant(false)
            )
            TagChip_Selectable(
                tag: TagModel(name: "Gift", colorHex: "#FF69B4", emoji: "🎁"),
                isSelected: .constant(true)
            )
        }
        
        // Removable chip
        TagChip_Removable(
            tag: TagModel(name: "Custom", colorHex: "#9370DB", emoji: "⭐")
        ) {
            print("Remove custom tag")
        }
    }
    .padding()
}
