//
//  ArkeCircularIcon.swift
//  ArkeUI
//

import SwiftUI

/// A white icon centered on a circular scratch-surface texture with a drop shadow.
/// Used in place of bare SF Symbols for large decorative icons in sheets and modals.
public struct ArkeCircularIcon: View {
    let icon: Image
    let size: CGFloat
    let iconFontSize: CGFloat

    public init(icon: Image, size: CGFloat = 75, iconFontSize: CGFloat = 30) {
        self.icon = icon
        self.size = size
        self.iconFontSize = iconFontSize
    }

    public var body: some View {
        icon
            .font(.system(size: iconFontSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Image("scratch-surface", bundle: .module)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

#Preview {
    VStack(spacing: 24) {
        ArkeCircularIcon(icon: Image(systemName: "arrow.up.circle"))
        ArkeCircularIcon(icon: Image(systemName: "arrow.down.circle"))
        ArkeCircularIcon(icon: Image(systemName: "bolt.fill"), size: 90, iconFontSize: 45)
    }
    .padding(40)
}
