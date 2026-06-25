//
//  OnchainBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

public struct BalanceRowView: View {
    let label: String
    let amount: Int

    public init(label: String, amount: Int) {
        self.label = label
        self.amount = amount
    }

    public var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(BitcoinFormatter.shared.formatAmount(amount))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(amount > 0 ? .primary : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(BitcoinFormatter.shared.formatAmount(amount))
    }
}

#Preview {
    VStack(spacing: 8) {
        BalanceRowView(label: "Available", amount: 1500000)
        BalanceRowView(label: "Pending", amount: 250000)
        BalanceRowView(label: "Locked", amount: 0)
    }
    .padding()
}
