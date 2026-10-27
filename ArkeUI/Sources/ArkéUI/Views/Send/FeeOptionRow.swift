//
//  FeeOptionRow.swift
//  ArkéUI
//
//  Created by Christoph on 3/25/26.
//  Moved into ArkéUI as a pure, previewable presentation view.
//  2026-10-27: shows the exact fee this tier would cost when the send flow
//  has a quote, so the tiers can be compared before one is picked. A tier
//  the wallet priced out of the balance says so and cannot be picked. No
//  sat/vB: users compare sats, and the rate lives in X-Ray (DECIDED).
//

import SwiftUI

public struct FeeOptionRow: View {
    let priority: FeePriority
    let feeSats: Int?
    let isUnaffordable: Bool
    let isEstimating: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    /// - Parameters:
    ///   - feeSats: The exact fee for the current send at this tier, when
    ///     the flow has quoted it; nil shows the tier alone
    ///   - isUnaffordable: The wallet priced this tier and the amount plus
    ///     its fee exceeds the balance; the row is disabled
    ///   - isEstimating: A quote request is open; shows a spinner where the
    ///     fee will appear
    public init(
        priority: FeePriority,
        feeSats: Int? = nil,
        isUnaffordable: Bool = false,
        isEstimating: Bool = false,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.priority = priority
        self.feeSats = feeSats
        self.isUnaffordable = isUnaffordable
        self.isEstimating = isEstimating
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(priority.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(priority.estimatedConfirmationTime)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                if let feeSats {
                    Text(BitcoinFormatter.shared.formatAmount(feeSats))
                        .font(.body)
                        .monospacedDigit()
                        .lineLimit(1)
                } else if isUnaffordable {
                    Text(String(localized: "fee_state_unaffordable", defaultValue: "Exceeds balance", bundle: .module))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if isEstimating {
                    ProgressView()
                        .controlSize(.small)
                }

                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.Arke.gold : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.Arke.gold)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(16)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.Arke.gold.opacity(0.1))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.Arke.gold.opacity(0.5) : Color.arkeSeparatorColor.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .opacity(isUnaffordable && !isSelected ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isUnaffordable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if feeSats == nil && isUnaffordable {
            return Text(String(localized: "accessibility_value_fee_unaffordable", defaultValue: "Exceeds balance at this speed", bundle: .module))
        }
        if feeSats == nil && isEstimating {
            return Text(String(localized: "accessibility_value_fee_estimating", defaultValue: "Estimating", bundle: .module))
        }
        return Text(verbatim: "")
    }
}

#Preview("With quote") {
    VStack(spacing: 12) {
        FeeOptionRow(priority: .fast, isUnaffordable: true, isSelected: false, onSelect: {})
        FeeOptionRow(priority: .medium, feeSats: 3_136, isSelected: true, onSelect: {})
        FeeOptionRow(priority: .slow, feeSats: 784, isSelected: false, onSelect: {})
    }
    .padding()
    .frame(width: 360)
}

#Preview("Estimating / no amount") {
    VStack(spacing: 12) {
        FeeOptionRow(priority: .fast, isEstimating: true, isSelected: true, onSelect: {})
        FeeOptionRow(priority: .medium, isSelected: false, onSelect: {})
        FeeOptionRow(priority: .slow, isSelected: false, onSelect: {})
    }
    .padding()
    .frame(width: 360)
}
