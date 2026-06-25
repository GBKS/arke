//
//  TagPreviewCard.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI
import ArkeUI

struct TagPreviewCard: View {
    let tag: TagModel
    let isEmpty: Bool
    
    init(tag: TagModel, isEmpty: Bool = false) {
        self.tag = tag
        self.isEmpty = isEmpty
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("label_preview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                if isEmpty {
                    Text("placeholder_name_preview")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    TagChip(tag: tag.appearance)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
