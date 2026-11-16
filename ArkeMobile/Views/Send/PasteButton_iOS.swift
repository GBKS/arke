//
//  PasteButton_iOS.swift
//  Arké
//
//  Created by Assistant on 12/17/25.
//

import SwiftUI
import ArkeUI

/// A circular button that pastes clipboard content into the send form
/// Appears on the camera view when clipboard contains content
struct PasteButton_iOS: View {
    let action: () -> Void
    
    private let buttonSize: CGFloat = 64
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Blurred dark disc so the glyph reads on both bright and
                // dark camera scenes (same recipe as the system Camera app and the
                // empty contact button).
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                
                // Icon
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(String(localized: "action_paste_clipboard", defaultValue: "Paste from clipboard"))
        .accessibilityHint(String(localized: "send_paste_hint", defaultValue: "Pastes payment address or invoice from clipboard"))
    }
}

// MARK: - Button Style

/// A button style that scales down on press with haptic feedback
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    // Haptic feedback on press
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                }
            }
    }
}
