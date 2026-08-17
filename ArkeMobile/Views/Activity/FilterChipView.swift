//
//  FilterChipView.swift
//  Arké
//
//  Created by Christoph on 12/17/25.
//

import SwiftUI
import ArkeUI

struct FilterChipView: View {
    let filterText: String
    let avatarData: Data?
    let showAvatar: Bool
    let onClear: () -> Void
    
    init(
        filterText: String,
        avatarData: Data? = nil,
        showAvatar: Bool = false,
        onClear: @escaping () -> Void
    ) {
        self.filterText = filterText
        self.avatarData = avatarData
        self.showAvatar = showAvatar
        self.onClear = onClear
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                // Filter icon/indicator
                if showAvatar {
                    ContactAvatarView(avatarData: avatarData, size: 30)
                }
                
                Text(filterText)
                    .font(.body)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Clear button
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "button_clear_filter", defaultValue: "Clear Filter"))
                .buttonStyle(.plain)
                .padding(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
    }
}

// Convenience initializers for specific filter types
extension FilterChipView {
    init(tag: PersistentTag, onClear: @escaping () -> Void) {
        self.init(
            filterText: tag.displayName,
            avatarData: nil,
            showAvatar: false,
            onClear: onClear
        )
    }
    
    init(contact: PersistentContact, onClear: @escaping () -> Void) {
        self.init(
            filterText: contact.displayName,
            avatarData: contact.avatarData,
            showAvatar: true,
            onClear: onClear
        )
    }
}
