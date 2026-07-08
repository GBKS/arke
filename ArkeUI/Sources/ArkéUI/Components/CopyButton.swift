//
//  CopyButton.swift
//  Arké
//
//  Created by Christoph on 6/26/26.
//

import SwiftUI

public enum CopyButtonSize {
    case small, medium, large

    var iconSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 15
        case .large: return 19
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .large: return 4
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 3
        case .medium: return 4
        case .large: return 6
        }
    }
}

public enum CopyButtonStyle {
    /// No background — just the icon.
    case plain
    /// Subtle bordered background tinted with the button color.
    case regular
    /// Solid tinted background with a contrasting icon.
    case prominent

    /// The default icon color for this style, used when no explicit color is provided.
    var defaultIconColor: Color {
        switch self {
        case .plain, .regular:
            return .Arke.goldLabel
        case .prominent:
            return .Arke.gold3
        }
    }

    /// The default background tint for this style, used when no explicit color is provided.
    var defaultBackgroundColor: Color {
        switch self {
        case .plain:
            return .clear
        case .regular, .prominent:
            return .Arke.gold
        }
    }
}

/// A reusable copy-to-clipboard button with a checkmark confirmation animation.
///
/// Copies `content` to the clipboard when tapped, briefly swapping the icon to a
/// checkmark with a spring animation. Supports three sizes and three styles.
public struct CopyButton: View {
    private let content: String
    private let size: CopyButtonSize
    private let style: CopyButtonStyle
    private let iconColor: Color?
    private let backgroundColor: Color?
    private let copiedColor: Color
    private let help: LocalizedStringKey?

    @State private var showingCopied = false

    /// Creates a copy button.
    ///
    /// `iconColor` and `backgroundColor` default to per-style colors when left `nil`.
    public init(
        _ content: String,
        size: CopyButtonSize = .medium,
        style: CopyButtonStyle = .regular,
        iconColor: Color? = nil,
        backgroundColor: Color? = nil,
        copiedColor: Color = .Arke.green,
        help: LocalizedStringKey? = nil
    ) {
        self.content = content
        self.size = size
        self.style = style
        self.iconColor = iconColor
        self.backgroundColor = backgroundColor
        self.copiedColor = copiedColor
        self.help = help
    }

    private var currentIconColor: Color {
        showingCopied ? copiedColor : (iconColor ?? style.defaultIconColor)
    }

    private var currentBackgroundColor: Color {
        showingCopied ? copiedColor : (backgroundColor ?? style.defaultBackgroundColor)
    }

    private var label: some View {
        Image(systemName: showingCopied ? "checkmark" : "doc.on.doc.fill")
            .font(.system(size: size.iconSize))
            .foregroundStyle(currentIconColor)
            .frame(width: size.iconSize, height: size.iconSize)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(showingCopied ? 1.1 : 1.0)
    }

    /// The VoiceOver label: the caller-supplied `help` when present, otherwise a generic default.
    private var accessibilityLabel: Text {
        if let help {
            return Text(help)
        }
        return Text(String(localized: "action_copy_value", bundle: .module))
    }

    private func copy() {
        copyToClipboard(content)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showingCopied = true
        }

        // Announce the copy to VoiceOver so success isn't a silent action.
        AccessibilityNotification.Announcement(
            String(localized: "status_copied_exclaim", bundle: .module)
        ).post()

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation {
                showingCopied = false
            }
        }
    }

    @ViewBuilder
    private var styledButton: some View {
        switch style {
        case .plain:
            Button(action: copy) { label }
                .buttonStyle(.plain)
        case .regular:
            Button(action: copy) { label }
                .buttonStyle(.bordered)
                .tint(currentBackgroundColor)
        case .prominent:
            Button(action: copy) { label }
                .buttonStyle(.borderedProminent)
                .tint(currentBackgroundColor)
        }
    }

    public var body: some View {
        styledButton
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(Text(String(localized: "accessibility_hint_copy_value", bundle: .module)))
            .ifLet(help) { view, help in
                view.help(help)
            }
    }
}

private extension View {
    /// Applies a transform only when an optional value is present.
    @ViewBuilder
    func ifLet<Value, Content: View>(
        _ value: Value?,
        transform: (Self, Value) -> Content
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

#Preview {
    VStack(spacing: 28) {
        VStack(spacing: 12) {
            Text("Sizes")
                .font(.headline)
            HStack(spacing: 16) {
                CopyButton("small", size: .small)
                CopyButton("medium", size: .medium)
                CopyButton("large", size: .large)
            }
        }

        VStack(spacing: 12) {
            Text("Styles")
                .font(.headline)
            HStack(spacing: 16) {
                CopyButton("plain", style: .plain)
                CopyButton("regular", style: .regular)
                CopyButton("prominent", style: .prominent)
            }
        }

        VStack(spacing: 12) {
            Text("Separate icon / background colors")
                .font(.headline)
            HStack(spacing: 16) {
                CopyButton("a", style: .prominent, iconColor: .white, backgroundColor: .blue)
                CopyButton("b", style: .regular, iconColor: .red, backgroundColor: .red)
                CopyButton("c", style: .plain, iconColor: .green)
            }
        }
    }
    .padding(40)
}
