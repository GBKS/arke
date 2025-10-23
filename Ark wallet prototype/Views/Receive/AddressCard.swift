//
//  AddressCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

extension String {
    func chunked(into size: Int) -> [String] {
        var result: [String] = []
        var index = 0
        
        while index < self.count {
            let start = self.index(self.startIndex, offsetBy: index)
            let remainingCount = self.count - index
            
            if remainingCount >= size {
                // Full chunk
                let end = self.index(start, offsetBy: size)
                result.append(String(self[start..<end]))
                index += size
            } else {
                // Last chunk - keep it as is, don't pad
                let end = self.index(start, offsetBy: remainingCount)
                result.append(String(self[start..<end]))
                break
            }
        }
        
        return result
    }
}

struct FlexWrapLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, in: proposal.width ?? 0).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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

struct FlexWrapView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    let spacing: CGFloat
    
    init(data: Data, spacing: CGFloat = 4, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.spacing = spacing
    }
    
    var body: some View {
        FlexWrapLayout(spacing: spacing) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}

struct IndexedChunk: Hashable {
    let index: Int
    let chunk: String
}

struct AddressCard: View {
    let address: String
    let shareContent: String?
    @State private var showingCopied = false
    @State private var fontSize: CGFloat = 14
    
    init(address: String, shareContent: String? = nil) {
        self.address = address
        self.shareContent = shareContent
    }
    
    private func formattedAddress() -> some View {
        let chunks = address.chunked(into: 4)
        let indexedChunks = chunks.enumerated().map { IndexedChunk(index: $0.offset, chunk: $0.element) }
        let spacing = fontSize * 0.3 // Proportional to font size
        
        return FlexWrapView(data: indexedChunks, spacing: spacing) { indexedChunk in
            let isFirstOrLast = indexedChunk.index < 2 || indexedChunk.index >= chunks.count - 2
            let textColor: Color = isFirstOrLast ? .primary : .secondary
            let textWeight: Font.Weight = isFirstOrLast ? .semibold : .regular
            
            Text(indexedChunk.chunk)
                .foregroundStyle(textColor)
                .fontWeight(textWeight)
                .lineLimit(1)
                .fixedSize()
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                formattedAddress()
                    .font(.system(size: fontSize, design: .monospaced))
                    .animation(.easeInOut(duration: 0.3), value: fontSize)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            fontSize = fontSize == 14 ? 20 : 14
                        }
                    }
                
                Spacer()
    
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                    showingCopied = true
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showingCopied = false
                    }
                } label: {
                    Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy address")
            }
        }
    }
}

#Preview {
    AddressCard(
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        shareContent: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    )
    .padding()
}
