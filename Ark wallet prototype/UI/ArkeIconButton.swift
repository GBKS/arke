//
//  ArkeIconButton.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

enum ArkeIconButtonSize {
    case small, medium, large
    
    var diameter: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 40
        case .large: return 48
        }
    }
    
    var iconSize: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
}

struct ArkeIconButtonStyle: ButtonStyle {
    let size: ArkeIconButtonSize
    let variant: ArkeButtonVariant
    let color: Color
    
    init(size: ArkeIconButtonSize = .medium, variant: ArkeButtonVariant = .filled, color: Color = Color(r: 248, g: 209, b: 117)) {
        self.size = size
        self.variant = variant
        self.color = color
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.iconSize, weight: .medium))
            .foregroundColor(foregroundColor(for: variant, isPressed: configuration.isPressed))
            .frame(width: size.diameter, height: size.diameter)
            .background(
                Circle()
                    .fill(backgroundColor(for: variant, isPressed: configuration.isPressed))
                    .overlay(
                        Circle()
                            .stroke(borderColor(for: variant), lineWidth: variant == .outline ? 2 : 0)
                    )
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func foregroundColor(for variant: ArkeButtonVariant, isPressed: Bool) -> Color {
        switch variant {
        case .filled:
            return .black
        case .outline:
            return isPressed ? .white : color
        case .ghost:
            return isPressed ? .black.opacity(0.6) : .black
        }
    }
    
    private func backgroundColor(for variant: ArkeButtonVariant, isPressed: Bool) -> Color {
        switch variant {
        case .filled:
            return isPressed ? color.opacity(0.8) : color
        case .outline:
            return isPressed ? color : Color.clear
        case .ghost:
            return isPressed ? color.opacity(0.1) : Color.clear
        }
    }
    
    private func borderColor(for variant: ArkeButtonVariant) -> Color {
        switch variant {
        case .filled, .ghost:
            return Color.clear
        case .outline:
            return color
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        
        VStack(spacing: 16) {
            Text("Sizes")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button {
                    // Action
                } label: {
                    Image(systemName: "heart.fill")
                }
                .iconButtonStyle(size: .small)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "heart.fill")
                }
                .iconButtonStyle(size: .medium)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "heart.fill")
                }
                .iconButtonStyle(size: .large)
            }
        }
        
        VStack(spacing: 16) {
            Text("Variants")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .filled)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .outline)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .ghost)
            }
        }
        
        VStack(spacing: 16) {
            Text("Colors")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button {
                    // Action
                } label: {
                    Image(systemName: "plus")
                }
                .iconButtonStyle(variant: .filled, color: .blue)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "minus")
                }
                .iconButtonStyle(variant: .outline, color: .red)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "checkmark")
                }
                .iconButtonStyle(variant: .ghost, color: .green)
            }
        }
        
    }
    .padding()
}

