//
//  TagPreviewCard.swift
//  ArkéUI
//
//  Created by Assistant on 10/30/25.
//  Moved into ArkéUI as a pure, previewable presentation view.
//

import SwiftUI

public struct TagPreviewCard: View {
    let tag: TagModel
    let isEmpty: Bool

    public init(tag: TagModel, isEmpty: Bool = false) {
        self.tag = tag
        self.isEmpty = isEmpty
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("label_preview", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                if isEmpty {
                    Text("placeholder_name_preview", bundle: .module)
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

#Preview {
    VStack(spacing: 16) {
        TagPreviewCard(tag: .sampleFood)
        TagPreviewCard(tag: .sampleFood, isEmpty: true)
    }
    .padding()
}
