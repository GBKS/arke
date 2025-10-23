//
//  OnchainBalanceView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct BalanceRowView: View {
    let label: String
    let amount: Int
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(BitcoinFormatter.formatAmount(amount))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(amount > 0 ? .primary : .secondary)
        }
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
