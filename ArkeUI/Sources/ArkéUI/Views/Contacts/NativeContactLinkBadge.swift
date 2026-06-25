//
//  NativeContactLinkBadge.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/11/25.
//

import SwiftUI

/// Badge indicating a contact is linked to native macOS Contacts
public struct NativeContactLinkBadge: View {
    let isLinked: Bool
    let lastSynced: Date?
    var size: BadgeSize = .medium
    var showLabel: Bool = true

    public init(
        isLinked: Bool,
        lastSynced: Date?,
        size: BadgeSize = .medium,
        showLabel: Bool = true
    ) {
        self.isLinked = isLinked
        self.lastSynced = lastSynced
        self.size = size
        self.showLabel = showLabel
    }

    public var body: some View {
        if isLinked {
            HStack(spacing: 4) {
                Image(systemName: "link.circle.fill")
                    .font(size.iconFont)
                    .foregroundStyle(Color.Arke.blue)
                
                if showLabel {
                    Text("Linked to Contacts")
                        .font(size.textFont)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    public enum BadgeSize {
        case small
        case medium
        case large

        var iconFont: Font {
            switch self {
            case .small: return .caption
            case .medium: return .subheadline
            case .large: return .body
            }
        }
        
        var textFont: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }
    }
}

// MARK: - Previews

#Preview("Badge - Linked") {
    NativeContactLinkBadge(
        isLinked: true,
        lastSynced: Date().addingTimeInterval(-3600)
    )
    .padding()
}

#Preview("Badge - Not Linked") {
    NativeContactLinkBadge(
        isLinked: false,
        lastSynced: nil
    )
    .padding()
}

#Preview("Badge Sizes") {
    VStack(alignment: .leading, spacing: 16) {
        NativeContactLinkBadge(isLinked: true, lastSynced: Date(), size: .small)
        NativeContactLinkBadge(isLinked: true, lastSynced: Date(), size: .medium)
        NativeContactLinkBadge(isLinked: true, lastSynced: Date(), size: .large)
        
        Divider()
        
        NativeContactLinkBadge(isLinked: true, lastSynced: Date(), size: .medium, showLabel: false)
    }
    .padding()
}
