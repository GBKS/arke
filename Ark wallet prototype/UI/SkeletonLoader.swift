//
//  SkeletonLoader.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/21/25.
//

import SwiftUI

struct SkeletonLoader: View {
    let itemCount: Int
    let itemHeight: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    
    init(
        itemCount: Int = 5,
        itemHeight: CGFloat = 60,
        spacing: CGFloat = 12,
        cornerRadius: CGFloat = 8
    ) {
        self.itemCount = itemCount
        self.itemHeight = itemHeight
        self.spacing = spacing
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<itemCount, id: \.self) { index in
                SkeletonLoaderBox(
                    height: itemHeight,
                    cornerRadius: cornerRadius,
                    delay: Double(index) * 0.2
                )
            }
        }
    }
}

struct SkeletonLoaderBox: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    let delay: Double
    
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(isAnimating ? 0.12 : 0.04))
            .frame(height: height)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    isAnimating = true
                }
            }
    }
}

#Preview {
    VStack {
        Text("Transaction List Skeleton")
            .font(.headline)
            .padding(.bottom)
        
        SkeletonLoader(
            itemCount: 5,
            itemHeight: 64,
            spacing: 15,
            cornerRadius: 15
        )
    }
    .padding()
}
