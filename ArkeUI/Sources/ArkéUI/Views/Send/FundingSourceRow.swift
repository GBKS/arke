//
//  FundingSourceRow.swift
//  ArkéUI
//
//  One row of the "Pay from" picker: a balance the payment can leave from.
//  The balance is the title; the rail ("Lightning", "onchain") and the
//  address are captions the caller passes only when two rows would
//  otherwise read the same. No contact, no format name: the form above the
//  picker already shows who is being paid (DECIDED 2026-10-28).
//

import SwiftUI

public struct FundingSourceRow: View {
    /// "Payments" or "Savings"
    let balanceName: String
    /// The balance available to this row, nil when unknown
    let availableSats: Int?
    /// The rail, when the caller needs it to tell rows apart
    let railCaption: String?
    /// The short address, when two rows share balance and rail
    let addressCaption: String?
    /// The fee for the typed amount; nil when none is known yet
    let estimatedFee: Int?
    let isSelected: Bool
    let viable: Bool
    /// Why the row cannot pay; shown in place of the fee when not viable
    let viabilityReason: String
    let onTap: () -> Void

    public init(
        balanceName: String,
        availableSats: Int?,
        railCaption: String? = nil,
        addressCaption: String? = nil,
        estimatedFee: Int?,
        isSelected: Bool,
        viable: Bool,
        viabilityReason: String,
        onTap: @escaping () -> Void
    ) {
        self.balanceName = balanceName
        self.availableSats = availableSats
        self.railCaption = railCaption
        self.addressCaption = addressCaption
        self.estimatedFee = estimatedFee
        self.isSelected = isSelected
        self.viable = viable
        self.viabilityReason = viabilityReason
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(!viable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(balanceName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(viable ? .primary : .secondary)
                    if let railCaption {
                        Text(railCaption)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                if let availableSats {
                    Text(String(localized: "funding_source_available %@", defaultValue: "\(BitcoinFormatter.shared.formatAmount(availableSats)) available", bundle: .module))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                if let addressCaption {
                    Text(addressCaption)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if !viable {
                    Text(viabilityReason)
                        .font(.body)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.trailing)
                } else if let fee = estimatedFee {
                    Text(L10n.labelFee)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(fee > 0 ? "~\(BitcoinFormatter.shared.formatAmount(fee))" : String(localized: "label_free", defaultValue: "Free", bundle: .module))
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background {
            if isSelected && viable {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.Arke.gold.opacity(0.05))
            } else if !viable {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.05))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        if !viable {
            return Color.arkeSeparatorColor.opacity(0.5)
        }
        return isSelected ? .Arke.gold : Color.arkeSeparatorColor
    }

    private var accessibilityLabel: String {
        var parts = [balanceName]
        if let railCaption { parts.append(railCaption) }
        if let availableSats {
            parts.append(String(localized: "funding_source_available %@", defaultValue: "\(BitcoinFormatter.shared.formatAmount(availableSats)) available", bundle: .module))
        }
        if !viable {
            parts.append(viabilityReason)
        } else if let fee = estimatedFee {
            parts.append(fee > 0 ? "\(L10n.labelFee) \(BitcoinFormatter.shared.formatAmount(fee))" : String(localized: "label_free", defaultValue: "Free", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Two balances, Savings short") {
    VStack(spacing: 10) {
        FundingSourceRow(balanceName: "Savings", availableSats: 12_000, estimatedFee: nil, isSelected: false, viable: false, viabilityReason: "Need ₿ 3,000 more", onTap: {})
        FundingSourceRow(balanceName: "Payments", availableSats: 250_000, estimatedFee: 420, isSelected: true, viable: true, viabilityReason: "", onTap: {})
    }
    .padding()
}

#Preview("Payments on two rails") {
    VStack(spacing: 10) {
        FundingSourceRow(balanceName: "Payments", availableSats: 250_000, railCaption: "Lightning", estimatedFee: 12, isSelected: true, viable: true, viabilityReason: "", onTap: {})
        FundingSourceRow(balanceName: "Payments", availableSats: 250_000, railCaption: "onchain", estimatedFee: 420, isSelected: false, viable: true, viabilityReason: "", onTap: {})
        FundingSourceRow(balanceName: "Savings", availableSats: 90_000, estimatedFee: 0, isSelected: false, viable: true, viabilityReason: "", onTap: {})
    }
    .padding()
}
