//
//  CustomNumericKeypad.swift
//  Arké
//
//  Created by Christoph on 5/23/26.
//

import SwiftUI
#if os(iOS)

/// Theme styles for the numeric keypad
public enum NumericKeypadTheme {
    case light
    case dark
    case textured(imageName: String)

    var textColor: Color {
        switch self {
        case .light:
            return .primary
        case .dark, .textured:
            return .white
        }
    }
}

/// Custom numeric keypad for quick amount input in TiltShareOverlay
///
/// The bound `amount` is always the machine form — digits with "." as the
/// decimal separator — so callers parse it with one code path. The key
/// itself shows the device locale's separator ("," on a German device).
/// `decimalPlaces` is how many fraction digits may follow the separator:
/// 8 for bitcoin, a currency's minor units for fiat (2 for USD, 0 for
/// JPY, which hides the key), nil for whole numbers only.
public struct CustomNumericKeypad_iOS: View {
    @Binding var amount: String
    let onConfirm: () -> Void
    var theme: NumericKeypadTheme = .dark
    var decimalPlaces: Int?
    var validateInput: ((String) -> Bool)?
    var allowEmptyConfirm: Bool = false

    /// Longest entry accepted, not counting the separator
    public static let maxDigits = 10

    /// Primary initializer
    /// - Parameter decimalPlaces: Fraction digits allowed after the separator;
    ///   nil or 0 hides the separator key
    public init(
        amount: Binding<String>,
        onConfirm: @escaping () -> Void,
        theme: NumericKeypadTheme = .dark,
        decimalPlaces: Int?,
        validateInput: ((String) -> Bool)? = nil,
        allowEmptyConfirm: Bool = false
    ) {
        self._amount = amount
        self.onConfirm = onConfirm
        self.theme = theme
        self.decimalPlaces = decimalPlaces
        self.validateInput = validateInput
        self.allowEmptyConfirm = allowEmptyConfirm
    }

    /// Bitcoin-oriented initializer: `showPeriod` allows 8 decimal places
    public init(
        amount: Binding<String>,
        onConfirm: @escaping () -> Void,
        theme: NumericKeypadTheme = .dark,
        showPeriod: Bool = false,
        validateInput: ((String) -> Bool)? = nil,
        allowEmptyConfirm: Bool = false
    ) {
        self.init(
            amount: amount,
            onConfirm: onConfirm,
            theme: theme,
            decimalPlaces: showPeriod ? 8 : nil,
            validateInput: validateInput,
            allowEmptyConfirm: allowEmptyConfirm
        )
    }

    // Legacy init for backwards compatibility
    public init(
        amount: Binding<String>,
        onConfirm: @escaping () -> Void,
        textColor: Color,
        showPeriod: Bool = false,
        validateInput: ((String) -> Bool)? = nil,
        allowEmptyConfirm: Bool = false
    ) {
        self.init(
            amount: amount,
            onConfirm: onConfirm,
            theme: textColor == .white ? .dark : .light,
            decimalPlaces: showPeriod ? 8 : nil,
            validateInput: validateInput,
            allowEmptyConfirm: allowEmptyConfirm
        )
    }

    /// Whether the separator key is shown at all
    private var showPeriod: Bool {
        (decimalPlaces ?? 0) > 0
    }

    /// What the separator key displays — the locale's glyph, never the
    /// machine-form "." unless that is the locale's glyph
    private var separatorGlyph: String {
        Locale.autoupdatingCurrent.decimalSeparator ?? "."
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    public var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            // Row 1: 1, 2, 3
            keypadButton("1")
            keypadButton("2")
            keypadButton("3")

            // Row 2: 4, 5, 6
            keypadButton("4")
            keypadButton("5")
            keypadButton("6")

            // Row 3: 7, 8, 9
            keypadButton("7")
            keypadButton("8")
            keypadButton("9")

            // Row 4: separator (optional) + backspace, 0, confirm
            if showPeriod {
                HStack(spacing: 12) {
                    backspaceButton()
                    periodButton()
                }
                .frame(maxWidth: .infinity)
            } else {
                backspaceButton()
            }
            keypadButton("0")
            confirmButton()
        }
        .applyTheme(theme)
    }
    
    // MARK: - Button Views
    
    private func keypadButton(_ digit: String) -> some View {
        Button {
            appendDigit(digit)
        } label: {
            Text(digit)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(2, contentMode: .fill)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThinMaterial)
                        .overlay(
                            Color.black.opacity(0.3)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func periodButton() -> some View {
        Button {
            appendPeriod()
        } label: {
            Text(verbatim: separatorGlyph)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(ConditionalAspectRatio(apply: !showPeriod, ratio: 2))
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThinMaterial)
                        .overlay(
                            Color.black.opacity(0.3)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(amount.contains("."))
        .opacity(amount.contains(".") ? 0.5 : 1.0)
        .accessibilityLabel(Text(String(localized: "accessibility_decimal_separator", defaultValue: "Decimal separator", bundle: .module)))
    }

    private func backspaceButton() -> some View {
        Button {
            deleteLastDigit()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(ConditionalAspectRatio(apply: !showPeriod, ratio: 2))
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThinMaterial)
                        .overlay(
                            Color.black.opacity(0.3)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(amount.isEmpty)
        .opacity(amount.isEmpty ? 0.5 : 1.0)
    }

    private func confirmButton() -> some View {
        Button {
            confirmAmount()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(2, contentMode: .fill)
                .background {
                    if amount.isEmpty && !allowEmptyConfirm {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Material.ultraThinMaterial)
                            .overlay(
                                Color.black.opacity(0.3)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.Arke.gold.opacity(0.8))
                    }
                }
        }
        .disabled(amount.isEmpty && !allowEmptyConfirm)
    }
    
    // MARK: - Actions
    
    private func appendDigit(_ digit: String) {
        // Cap the digit count (not counting the separator)
        let digitCount = amount.replacingOccurrences(of: ".", with: "").count
        if digitCount >= Self.maxDigits {
            return
        }

        // Cap the fraction digits at what the unit allows
        if let decimalPlaces, amount.contains(".") {
            let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1 && parts[1].count >= decimalPlaces {
                return
            }
        }

        // Prevent leading zeros (except "0.")
        if amount == "0" && digit == "0" {
            return
        }

        // Build the new amount
        let newAmount: String
        if amount == "0" && digit != "0" {
            newAmount = digit
        } else {
            newAmount = amount + digit
        }

        // Validate the new amount if validator is provided
        if let validateInput = validateInput, !validateInput(newAmount) {
            return
        }

        amount = newAmount

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func appendPeriod() {
        // Don't allow a separator if one already exists, or none is allowed
        guard showPeriod, !amount.contains(".") else {
            return
        }
        
        // If empty or just "0", prepend "0."
        if amount.isEmpty {
            amount = "0."
        } else {
            amount += "."
        }
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func deleteLastDigit() {
        guard !amount.isEmpty else { return }
        amount.removeLast()
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func confirmAmount() {
        guard !amount.isEmpty || allowEmptyConfirm else { return }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        onConfirm()
    }
}

// MARK: - View Modifiers

private struct ConditionalAspectRatio: ViewModifier {
    let apply: Bool
    let ratio: CGFloat

    func body(content: Content) -> some View {
        if apply {
            content.aspectRatio(ratio, contentMode: .fill)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func applyTheme(_ theme: NumericKeypadTheme) -> some View {
        switch theme {
        case .light, .dark:
            // No additional styling for light/dark themes
            self
        case .textured(let imageName):
            self
                .padding(15)
                .background {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        }
    }
}

// MARK: - Preview

#Preview("Without Period") {
    @Previewable @State var amount = "1000"
    
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Text(amount.isEmpty ? "Enter amount" : "\(amount) sats")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding()
            
            Spacer()
            
            CustomNumericKeypad_iOS(amount: $amount) {
                print("Confirmed amount: \(amount)")
            }
            .frame(height: 300)
        }
    }
}
#Preview("With Period") {
    @Previewable @State var amount = "10.5"
    
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Text(amount.isEmpty ? "Enter amount" : "\(amount) BTC")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding()
            
            Spacer()
            
            CustomNumericKeypad_iOS(amount: $amount, onConfirm: {
                print("Confirmed amount: \(amount)")
            }, showPeriod: true)
            .frame(height: 300)
        }
    }
}
#Preview("Two Decimal Places") {
    @Previewable @State var amount = "12.5"

    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            Text(amount.isEmpty ? "Enter amount" : "$\(amount)")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding()

            Spacer()

            CustomNumericKeypad_iOS(amount: $amount, onConfirm: {
                print("Confirmed amount: \(amount)")
            }, decimalPlaces: 2)
            .frame(height: 300)
        }
    }
}
#endif
