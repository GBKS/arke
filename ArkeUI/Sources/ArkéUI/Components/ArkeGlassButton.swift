//
//  ArkeGlassButton.swift
//  ArkeUI
//

import SwiftUI

public enum ArkeGlassButtonVariant {
    /// Gold glass capsule with gold4 label — the primary action.
    case prominent
    /// Clear glass capsule with primary-colored label — secondary actions like Cancel.
    case secondary
}

/// A full-width Liquid Glass button with the Arke brand styling baked in:
/// large control size, gold tint, title2 semibold label, and an optional
/// loading state that swaps the label for a spinner.
public struct ArkeGlassButton<Label: View>: View {
    let variant: ArkeGlassButtonVariant
    let controlSize: ControlSize
    let isLoading: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    public init(
        variant: ArkeGlassButtonVariant = .prominent,
        controlSize: ControlSize = .large,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.controlSize = controlSize
        self.isLoading = isLoading
        self.action = action
        self.label = label
    }

    public var body: some View {
        switch variant {
        case .prominent:
            core.buttonStyle(.glassProminent)
        case .secondary:
            core.buttonStyle(.glass)
        }
    }

    private var core: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    label()
                        .font(.system(.title2, weight: .semibold))
                        .foregroundStyle(variant == .prominent ? Color.Arke.gold4 : Color.primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(controlSize)
        .tint(Color.Arke.gold)
    }
}

extension ArkeGlassButton where Label == Text {
    public init(
        _ title: String,
        variant: ArkeGlassButtonVariant = .prominent,
        controlSize: ControlSize = .large,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(variant: variant, controlSize: controlSize, isLoading: isLoading, action: action) {
            Text(title)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ArkeGlassButton("Make Primary") { }

        ArkeGlassButton("Cancel", variant: .secondary) { }

        ArkeGlassButton("Processing", isLoading: true) { }
            .disabled(true)

        ArkeGlassButton(action: { }) {
            SwiftUI.Label("View Test Guide", systemImage: "book.pages")
        }

        ArkeGlassButton("Regular Size", controlSize: .regular) { }
    }
    .padding()
}
