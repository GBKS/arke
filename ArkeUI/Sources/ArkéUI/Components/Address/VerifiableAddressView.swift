//
//  VerifiableAddressView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 1/26/26.
//

import SwiftUI

/// A view that displays an address in chunks that can be individually tapped to mark as verified.
/// Designed for address verification workflows where users need to confirm each chunk.
public struct VerifiableAddressView: View {
    let address: String
    @State private var verifiedChunks: Set<Int> = []

    public init(address: String) {
        self.address = address
    }

    private var fontSize: CGFloat {
        #if os(macOS)
        18
        #else
        22
        #endif
    }
    
    public var body: some View {
        let chunks = address.chunked(into: 4)
        let indexedChunks = chunks.enumerated().map { IndexedChunk(index: $0.offset, chunk: $0.element) }
        let spacing = fontSize * 0.3
        
        FlexWrapView(data: indexedChunks, spacing: spacing) { indexedChunk in
            let isVerified = verifiedChunks.contains(indexedChunk.index)
            let isFirstOrLast = indexedChunk.index < 2 || indexedChunk.index >= chunks.count - 2
            let textColor: Color = isFirstOrLast ? .primary : .secondary
            
            Text(indexedChunk.chunk)
                .foregroundStyle(textColor)
                .fontWeight(isFirstOrLast ? .semibold : .regular)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isVerified ? Color.green.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.3), lineWidth: isVerified ? 1.5 : 0)
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isVerified {
                            verifiedChunks.remove(indexedChunk.index)
                        } else {
                            verifiedChunks.insert(indexedChunk.index)
                        }
                    }
                }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct FlexWrapView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    let spacing: CGFloat
    
    public init(data: Data, spacing: CGFloat = 4, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.spacing = spacing
    }
    
    public var body: some View {
        FlexWrapLayout(spacing: spacing) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}

public struct FlexWrapLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, in: proposal.width ?? 0).size
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, in: bounds.width).offsets
        
        for (offset, subview) in zip(offsets, subviews) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }
    
    private func layout(sizes: [CGSize], in width: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var result: [CGPoint] = []
        var currentPosition: CGPoint = .zero
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for size in sizes {
            if currentPosition.x + size.width > width && currentPosition.x > 0 {
                // Start new line
                currentPosition.x = 0
                currentPosition.y += lineHeight + spacing
                lineHeight = 0
            }
            
            result.append(currentPosition)
            currentPosition.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, currentPosition.x - spacing)
        }
        
        let totalSize = CGSize(width: maxX, height: currentPosition.y + lineHeight)
        return (result, totalSize)
    }
}

public struct IndexedChunk: Hashable {
    public let index: Int
    public let chunk: String

    public init(index: Int, chunk: String) {
        self.index = index
        self.chunk = chunk
    }
}

#Preview {
    VStack(spacing: 30) {
        VerifiableAddressView(
            address: "tark1pem36wcfzqqp44guvcz4ycd2k8m68g7n4rxal2347q43ez3hk6ysmc4n37ee5g9ezqyp7wd8j7ujtgulmvzgsfz9ss9udsmu9g20f7ryndwh0uxgn4t0hfms35rkpt"
        )
        
        Divider()
        
        VerifiableAddressView(
            address: "tb1pqyr54pwg9x93el66th0ngjdrpxn0k4stv7hrqhuywrmlar22wh8q4lekg3"
        )
    }
    .padding()
}
