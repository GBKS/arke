//
//  TagPreviewCard.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

struct TagPreviewCard: View {
    let tag: TagModel
    let isEmpty: Bool
    
    init(tag: TagModel, isEmpty: Bool = false) {
        self.tag = tag
        self.isEmpty = isEmpty
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Preview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                if isEmpty {
                    Text("Enter a name to see preview")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    TagChip(tag: tag)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 20) {
        TagPreviewCard(
            tag: TagModel(name: "Coffee", colorHex: "#8B4513", emoji: "☕"),
            isEmpty: false
        )
        
        TagPreviewCard(
            tag: TagModel(name: "", colorHex: "#4A90E2", emoji: ""),
            isEmpty: true
        )
    }
    .padding()
}