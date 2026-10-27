//
//  FeeDisplayView.swift
//  Arké
//
//  Created by Assistant on 3/24/26.
//  2026-10-27: renders a FeeDisplayState so an approximate placeholder and
//  an open request look different from a fee the wallet has priced.
//

import SwiftUI

/// A reusable view component that displays transaction fee information
/// with optional disclosure indicator for interactive fee selection
public struct FeeDisplayView: View {
    let state: FeeDisplayState
    let showDisclosure: Bool
    let onTap: (() -> Void)?

    public init(
        state: FeeDisplayState,
        showDisclosure: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.state = state
        self.showDisclosure = showDisclosure
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if showDisclosure && onTap != nil {
                Button(action: onTap ?? {}) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            Text(L10n.labelFee)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            feeLabel

            if showDisclosure {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            if showDisclosure {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.arkeSeparatorColor.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(showDisclosure && onTap != nil
            ? Text(String(localized: "accessibility_hint_change_fee", defaultValue: "Opens fee selection", bundle: .module))
            : Text(verbatim: ""))
    }

    @ViewBuilder
    private var feeLabel: some View {
        switch state {
        case .value(let fee):
            Text(BitcoinFormatter.shared.formatAmount(fee))
                .font(.body)
        case .approximate(let fee):
            // The tilde is the whole point: this number is a size guess
            Text(String(localized: "fee_approximate_format",
                        defaultValue: "~\(BitcoinFormatter.shared.formatAmount(fee))",
                        bundle: .module))
                .font(.body)
                .foregroundStyle(.secondary)
        case .estimating:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "fee_state_estimating", defaultValue: "Estimating…", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .unaffordable:
            Text(String(localized: "fee_state_unaffordable", defaultValue: "Exceeds balance", bundle: .module))
                .font(.body)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text(verbatim: "—")
                .font(.body)
        }
    }

    /// Spoken after the combined label, so a sighted tilde has a spoken twin
    private var accessibilityValue: String {
        switch state {
        case .value:
            return ""
        case .approximate:
            return String(localized: "accessibility_value_fee_approximate", defaultValue: "Approximate, not yet priced", bundle: .module)
        case .estimating:
            return String(localized: "accessibility_value_fee_estimating", defaultValue: "Estimating", bundle: .module)
        case .unaffordable:
            return String(localized: "accessibility_value_fee_unaffordable", defaultValue: "Exceeds balance at this speed", bundle: .module)
        case .unavailable:
            return String(localized: "accessibility_value_fee_unavailable", defaultValue: "Not available", bundle: .module)
        }
    }
}

#Preview("States") {
    VStack(spacing: 20) {
        FeeDisplayView(state: .value(7_839))
        FeeDisplayView(state: .approximate(7_750))
        FeeDisplayView(state: .estimating)
        FeeDisplayView(state: .unaffordable)
        FeeDisplayView(state: .unavailable)
    }
    .padding()
    .frame(width: 400)
}

#Preview("With Disclosure") {
    VStack(spacing: 20) {
        FeeDisplayView(
            state: .value(250),
            showDisclosure: true,
            onTap: { print("Fee tapped") }
        )

        FeeDisplayView(
            state: .approximate(250),
            showDisclosure: true,
            onTap: { print("Fee tapped") }
        )

        FeeDisplayView(
            state: .estimating,
            showDisclosure: true,
            onTap: { print("Fee tapped") }
        )
    }
    .padding()
    .frame(width: 400)
}

#Preview("In Context") {
    VStack(alignment: .leading, spacing: 10) {
        Text("Payment Details")
            .font(.title2)
            .fontWeight(.medium)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Available")
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                Text("₿ 1,000")
                    .font(.body)
            }

            HStack(spacing: 8) {
                Text("Minimum")
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                Text("₿ 330")
                    .font(.body)
            }

            FeeDisplayView(
                state: .value(250),
                showDisclosure: true,
                onTap: { print("Fee tapped") }
            )
        }
    }
    .padding()
    .frame(width: 400)
}
