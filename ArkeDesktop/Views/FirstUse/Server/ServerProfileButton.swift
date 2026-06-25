//
//  ServerProfileButton.swift
//  Arké
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct ServerProfileButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.Arke.gold : .white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.Arke.gold.opacity(0.1) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
