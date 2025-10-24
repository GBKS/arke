//
//  ArkeButton.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

enum ArkeButtonSize {
    case small, medium, large
    
    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small: return (120, 32)
        case .medium: return (160, 40)
        case .large: return (200, 44)
        }
    }
    
    var font: Font {
        switch self {
        case .small: return .body
        case .medium: return .title3
        case .large: return .title2
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 100
        }
    }
}

enum ArkeButtonVariant {
    case filled, outline, ghost
}

struct ArkeButtonStyle: ButtonStyle {
    let size: ArkeButtonSize
    let variant: ArkeButtonVariant
    let color: Color
    
    init(size: ArkeButtonSize = .medium, variant: ArkeButtonVariant = .filled, color: Color = Color(r: 248, g: 209, b: 117)) {
        self.size = size
        self.variant = variant
        self.color = color
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
            .foregroundColor(foregroundColor(for: variant, isPressed: configuration.isPressed))
            .frame(minWidth: size.dimensions.width, minHeight: size.dimensions.height)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(backgroundColor(for: variant, isPressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: size.cornerRadius)
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
            return isPressed ? .primary.opacity(0.6) : .primary
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

// MARK: - Convenience Extensions

extension View {
    func buttonStyle(size: ArkeButtonSize, variant: ArkeButtonVariant = .filled, color: Color = Color(r: 248, g: 209, b: 117)) -> some View {
        self.buttonStyle(ArkeButtonStyle(size: size, variant: variant, color: color))
    }
    
    func iconButtonStyle(size: ArkeIconButtonSize = .medium, variant: ArkeButtonVariant = .filled, color: Color = Color(r: 248, g: 209, b: 117)) -> some View {
        self.buttonStyle(ArkeIconButtonStyle(size: size, variant: variant, color: color))
    }
}

#Preview {
    VStack(spacing: 20) {
        VStack(spacing: 16) {
            Text("Button Sizes")
                .font(.headline)
            
            HStack {
                Button("Small") { }
                    .buttonStyle(size: .small)
                Button("Medium") { }
                    .buttonStyle(size: .medium)
                Button("Large") { }
                    .buttonStyle(size: .large)
            }
        }
        
        VStack(spacing: 16) {
            Text("Buttons with Icons")
                .font(.headline)
            
            HStack {
                Button {
                    // Action
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add Item")
                    }
                }
                .buttonStyle(size: .medium, variant: .filled)
                
                Button {
                    // Action
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                        Text("Continue")
                    }
                }
                .buttonStyle(size: .medium, variant: .outline)
                
                Button {
                    // Action
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart")
                        Text("Like")
                    }
                }
                .buttonStyle(size: .medium, variant: .ghost)
            }
        }
        
        VStack(spacing: 16) {
            Text("Button Variants")
                .font(.headline)
            
            HStack {
                Button("Filled Button") { }
                    .buttonStyle(size: .medium, variant: .filled)
                
                Button("Outline Button") { }
                    .buttonStyle(size: .medium, variant: .outline)
                
                Button("Ghost Button") { }
                    .buttonStyle(size: .medium, variant: .ghost)
            }
        }
        
        VStack(spacing: 16) {
            Text("Different Colors")
                .font(.headline)
            
            HStack {
                Button("Blue Filled") { }
                    .buttonStyle(size: .medium, variant: .filled, color: .blue)
                
                Button("Red Outline") { }
                    .buttonStyle(size: .medium, variant: .outline, color: .red)
                
                Button("Green Ghost") { }
                    .buttonStyle(size: .medium, variant: .ghost, color: .green)
            }
        }
    }
    .padding()
}
