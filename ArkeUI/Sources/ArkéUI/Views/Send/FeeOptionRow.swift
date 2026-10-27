//
//  FeeOptionRow.swift
//  ArkéUI
//
//  Created by Christoph on 3/25/26.
//  Moved into ArkéUI as a pure, previewable presentation view.
//  2026-10-27: shows the rate and, when the send flow has a quote, the
//  exact fee this tier would cost, so the tiers can be compared before
//  one is picked.
//

import SwiftUI

public struct FeeOptionRow: View {
    let priority: FeePriority
    let feeRate: UInt64
    let feeSats: Int?
    let isEstimating: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    /// - Parameters:
    ///   - feeRate: The tier's rate in sat/vB, always known
    ///   - feeSats: The exact fee for the current send at this tier, when
    ///     the flow has quoted it; nil shows the rate alone
    ///   - isEstimating: A quote request is open; shows a spinner where the
    ///     fee will appear
    public init(
        priority: FeePriority,
        feeRate: UInt64,
        feeSats: Int? = nil,
        isEstimating: Bool = false,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.priority = priority
        self.feeRate = feeRate
        self.feeSats = feeSats
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

                    HStack(spacing: 8) {
                        Text(priority.estimatedConfirmationTime)
                        Text(verbatim: "·")
                        Text(String(localized: "fee_rate_sat_per_vb", defaultValue: "\(feeRate) sat/vB", bundle: .module))
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if let feeSats {
                    Text(BitcoinFormatter.shared.formatAmount(feeSats))
                        .font(.body)
                        .monospacedDigit()
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(feeSats == nil && isEstimating
            ? Text(String(localized: "accessibility_value_fee_estimating", defaultValue: "Estimating", bundle: .module))
            : Text(verbatim: ""))
    }
}

#Preview("With quote") {
    VStack(spacing: 12) {
        FeeOptionRow(priority: .fast, feeRate: 50, feeSats: 7_839, isSelected: false, onSelect: {})
        FeeOptionRow(priority: .medium, feeRate: 20, feeSats: 3_136, isSelected: true, onSelect: {})
        FeeOptionRow(priority: .slow, feeRate: 5, feeSats: 784, isSelected: false, onSelect: {})
    }
    .padding()
}

#Preview("Estimating / rates only") {
    VStack(spacing: 12) {
        FeeOptionRow(priority: .fast, feeRate: 10, isEstimating: true, isSelected: true, onSelect: {})
        FeeOptionRow(priority: .medium, feeRate: 5, isSelected: false, onSelect: {})
        FeeOptionRow(priority: .slow, feeRate: 2, isSelected: false, onSelect: {})
    }
    .padding()
}
