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
        ArkeIconButtonContent(
            configuration: configuration,
            size: size,
            variant: variant,
            color: color
        )
    }
}

private struct ArkeIconButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let size: ArkeIconButtonSize
    let variant: ArkeButtonVariant
    let color: Color
    
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        configuration.label
            .font(.system(size: size.iconSize, weight: .medium))
            .foregroundColor(foregroundColor(for: variant, isPressed: configuration.isPressed, isEnabled: isEnabled))
            .frame(width: size.diameter, height: size.diameter)
            .background(
                Circle()
                    .fill(backgroundColor(for: variant, isPressed: configuration.isPressed, isEnabled: isEnabled))
                    .overlay(
                        Circle()
                            .stroke(borderColor(for: variant, isEnabled: isEnabled), lineWidth: variant == .outline ? 2 : 0)
                    )
                    .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func foregroundColor(for variant: ArkeButtonVariant, isPressed: Bool, isEnabled: Bool) -> Color {
        switch variant {
        case .filled:
            return isEnabled ? .black : .black.opacity(0.25)
        case .outline:
            return isEnabled ? (isPressed ? .white : color) : color.opacity(0.25)
        case .ghost:
            return isEnabled ? (isPressed ? .black.opacity(0.6) : .black) : .black.opacity(0.25)
        }
    }
    
    private func backgroundColor(for variant: ArkeButtonVariant, isPressed: Bool, isEnabled: Bool) -> Color {
        switch variant {
        case .filled:
            return isEnabled ? (isPressed ? color.opacity(0.8) : color) : color.opacity(0.25)
        case .outline:
            return isEnabled ? (isPressed ? color : Color.clear) : Color.clear
        case .ghost:
            return isEnabled ? (isPressed ? color.opacity(0.1) : Color.clear) : Color.clear
        }
    }
    
    private func borderColor(for variant: ArkeButtonVariant, isEnabled: Bool) -> Color {
        switch variant {
        case .filled, .ghost:
            return Color.clear
        case .outline:
            return isEnabled ? color : color.opacity(0.25)
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
        
        VStack(spacing: 16) {
            Text("Disabled State")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .filled)
                .disabled(true)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .outline)
                .disabled(true)
                
                Button {
                    // Action
                } label: {
                    Image(systemName: "star.fill")
                }
                .iconButtonStyle(variant: .ghost)
                .disabled(true)
            }
        }
        
    }
    .padding()
}

