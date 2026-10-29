//
//  ScratchableMnemonicGrid_iOS.swift
//  Arké
//
//  Created by Christoph on 1/27/26.
//

import SwiftUI
import UIKit

struct ScratchableMnemonicGrid_iOS: View {
    let mnemonic: String
    @Binding var revealAll: Bool
    
    @State private var scratchedPoints: [CGPoint] = []
    @State private var lastHapticTime: Date = .distantPast
    @State private var showHandIcon: Bool = true
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let minPointDistance: CGFloat = 3.0
    private let brushSize: CGFloat = 75.0
    private let hapticThrottleInterval: TimeInterval = 0.08
    
    var body: some View {
        MnemonicGrid(mnemonic: mnemonic)
            .overlay {
                if !revealAll {
                    ScratchOverlayView_iOS(
                        scratchedPoints: $scratchedPoints,
                        brushSize: brushSize
                    )
                    .overlay {
                        if showHandIcon {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleScratch(at: value.location)
                            }
                    )
                }
            }
            .onAppear {
                hapticGenerator.prepare()
            }
            .onDisappear {
                // Reset scratch state when view disappears
                scratchedPoints = []
                showHandIcon = true
            }
            .onChange(of: revealAll) { oldValue, newValue in
                if newValue {
                    showHandIcon = false
                } else {
                    // Hiding again restores the untouched surface, not the
                    // earlier scratch holes.
                    scratchedPoints = []
                    showHandIcon = true
                }
            }
    }
    
    private func handleScratch(at location: CGPoint) {
        // Hide hand icon on first scratch
        if showHandIcon {
            showHandIcon = false
        }
        
        // Distance-based throttling for performance
        if let lastPoint = scratchedPoints.last {
            let distance = hypot(location.x - lastPoint.x, location.y - lastPoint.y)
            guard distance > minPointDistance else { return }
        }
        
        scratchedPoints.append(location)
        
        // Time-based haptic throttling
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) >= hapticThrottleInterval {
            hapticGenerator.impactOccurred(intensity: 0.5)
            lastHapticTime = now
        }
    }
}

struct ScratchOverlayView_iOS: View {
    @Binding var scratchedPoints: [CGPoint]
    let brushSize: CGFloat
    let cornerRadius: CGFloat = 12.0
    
    var body: some View {
        Canvas { context, size in
            // Draw the scratch texture as the base
            if let resolvedImage = context.resolveSymbol(id: "scratchTexture") {
                context.draw(resolvedImage, in: CGRect(origin: .zero, size: size))
            }
            
            // Cut out scratched areas using destination-out blend mode
            context.blendMode = .destinationOut
            for point in scratchedPoints {
                let rect = CGRect(
                    x: point.x - brushSize / 2,
                    y: point.y - brushSize / 2,
                    width: brushSize,
                    height: brushSize
                )
                context.fill(Circle().path(in: rect), with: .color(.white))
            }
        } symbols: {
            Image("scratch-surface") // Placeholder - replace with actual texture image
                .resizable()
                .scaledToFill()
                .tag("scratchTexture")
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
