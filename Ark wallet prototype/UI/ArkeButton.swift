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
    let isLoading: Bool
    
    init(size: ArkeButtonSize = .medium, variant: ArkeButtonVariant = .filled, color: Color = .arkeGold, isLoading: Bool = false) {
        self.size = size
        self.variant = variant
        self.color = color
        self.isLoading = isLoading
    }
    
    func makeBody(configuration: Configuration) -> some View {
        ArkeButtonContent(
            configuration: configuration,
            size: size,
            variant: variant,
            color: color,
            isLoading: isLoading
        )
    }
}

private struct ArkeButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let size: ArkeButtonSize
    let variant: ArkeButtonVariant
    let color: Color
    let isLoading: Bool
    
    @Environment(\.isEnabled) private var isEnabled
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                Image(systemName: "arrow.2.circlepath")
                    .font(size.font)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
            }
            
            configuration.label
        }
        .font(size.font)
        .fontWeight(.semibold)
        .padding(.horizontal, 20)
        .foregroundColor(foregroundColor(for: variant, isPressed: configuration.isPressed, isEnabled: isEnabled && !isLoading))
        .frame(minWidth: size.dimensions.width, minHeight: size.dimensions.height)
        .background(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(backgroundColor(for: variant, isPressed: configuration.isPressed, isEnabled: isEnabled && !isLoading))
                .overlay(
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .stroke(borderColor(for: variant, isEnabled: isEnabled && !isLoading), lineWidth: variant == .outline ? 2 : 0)
                )
                .scaleEffect(configuration.isPressed && isEnabled && !isLoading ? 0.95 : 1.0)
        )
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func foregroundColor(for variant: ArkeButtonVariant, isPressed: Bool, isEnabled: Bool) -> Color {
        //guard isEnabled else {
            //return Color.secondary.opacity(0.5)
        //}
        
        switch variant {
        case .filled:
            return isEnabled ? .black : .black.opacity(0.25)
        case .outline:
            return isEnabled ? (isPressed ? .white : color) : color.opacity(0.25)
        case .ghost:
            return isEnabled ? (isPressed ? .primary.opacity(0.6) : .primary) : .primary.opacity(0.25)
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
        //guard isEnabled else {
        //    return variant == .outline ? Color.secondary.opacity(0.3) : Color.clear
        //}
        
        switch variant {
        case .filled, .ghost:
            return Color.clear
        case .outline:
            return isEnabled ? color : color.opacity(0.25)
        }
    }
}

// MARK: - Convenience Extensions

extension View {
    func buttonStyle(size: ArkeButtonSize, variant: ArkeButtonVariant = .filled, color: Color = .arkeGold, isLoading: Bool = false) -> some View {
        self.buttonStyle(ArkeButtonStyle(size: size, variant: variant, color: color, isLoading: isLoading))
    }
    
    func iconButtonStyle(size: ArkeIconButtonSize = .medium, variant: ArkeButtonVariant = .filled, color: Color = .arkeGold) -> some View {
        self.buttonStyle(ArkeIconButtonStyle(size: size, variant: variant, color: color))
    }
}

#Preview {
    ScrollView {
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
            
            VStack(spacing: 16) {
                Text("Disabled State")
                    .font(.headline)
                
                HStack {
                    Button("Disabled Filled") { }
                        .buttonStyle(size: .medium, variant: .filled)
                        .disabled(true)
                    
                    Button("Disabled Outline") { }
                        .buttonStyle(size: .medium, variant: .outline)
                        .disabled(true)
                    
                    Button("Disabled Ghost") { }
                        .buttonStyle(size: .medium, variant: .ghost)
                        .disabled(true)
                }
            }
            
            VStack(spacing: 16) {
                Text("Loading State")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    HStack {
                        Button("Loading Filled") { }
                            .buttonStyle(size: .medium, variant: .filled, isLoading: true)
                        
                        Button("Loading Outline") { }
                            .buttonStyle(size: .medium, variant: .outline, isLoading: true)
                        
                        Button("Loading Ghost") { }
                            .buttonStyle(size: .medium, variant: .ghost, isLoading: true)
                    }
                    
                    HStack {
                        Button("Small Loading") { }
                            .buttonStyle(size: .small, variant: .filled, isLoading: true)
                        
                        Button("Large Loading") { }
                            .buttonStyle(size: .large, variant: .filled, color: .blue, isLoading: true)
                    }
                }
            }
        }
        .padding()
    }
    .frame(width: 600, height: 700)
}
