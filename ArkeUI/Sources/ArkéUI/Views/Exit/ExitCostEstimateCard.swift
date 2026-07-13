//
//  ExitCostEstimateCard.swift
//  Arke
//
//  Created by Christoph on 4/8/26.
//

import SwiftUI

public struct ExitCostEstimateCard: View {
    let spendableBalance: UInt64
    let estimate: ExitCostEstimate
    let onchainBalance: UInt64
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            /*
            HStack {
                Image(systemName: estimate.canAfford ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(estimate.canAfford ? .green : .orange)
                Text("Fee Estimate")
                    .font(.headline)
                Spacer()
            }
            */
            
            VStack(spacing: 8) {
                /*
                 ExitCostRow(
                    label: "Network fee rate",
                    value: "\(estimate.feeRate) sat/vB"
                )
                */

                ExitCostRow(
                    label: String(localized: "balance_amount_to_recover", bundle: .module),
                    value: BitcoinFormatter.shared.formatAmount(Int(spendableBalance))
                )

                Divider()

                // Show fee range if available, otherwise single estimate
                ExitCostRow(
                    label: String(localized: "balance_estimated_fee", bundle: .module),
                    value: estimate.isRange
                        ? "\(BitcoinFormatter.shared.formatAmount(Int(estimate.lowCost))) – \(BitcoinFormatter.shared.formatAmount(Int(estimate.highCost)))"
                        : BitcoinFormatter.shared.formatAmount(Int(estimate.totalCost))
                )
                
                Divider()

                // Show transaction count
                ExitCostRow(
                    label: String(localized: "fee_transactions", bundle: .module),
                    value: "\(estimate.transactionRange)"
                )

                /*
                ExitCostRow(
                    label: "Your savings balance",
                    value: BitcoinFormatter.shared.formatAmount(Int(onchainBalance)),
                    color: estimate.canAfford ? .green : .orange
                )
                */

                /*
                if !estimate.canAfford {
                    ExitCostRow(
                        label: "Missing savings funds",
                        value: BitcoinFormatter.shared.formatAmount(Int(estimate.shortfall)),
                        color: .red
                    )
                }
                */
            }
            
            if !estimate.canAfford {                
                Divider()
                
                Label {
                    Text("balance_increase_savings_for_fee", bundle: .module)
                } icon: {
                    Image(systemName: "tornado")
                        .accessibilityHidden(true)
                }
                .font(.body)
                .foregroundStyle(Color.Arke.purple)
                .fontWeight(.medium)
                .padding(.top, 4)
            } else {
                /*
                Text("✓ You have sufficient savings balance.")
                    .font(.body)
                    .foregroundColor(.green)
                    .padding(.top, 4)
                 */
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Previews

#Preview("Can Afford") {
    ExitCostEstimateCard(
        spendableBalance: 100000,
        estimate: ExitCostEstimate(
            lowCost: 12000,
            totalCost: 15000,
            highCost: 18000,
            minTransactions: 4,
            maxTransactions: 7,
            feeRate: 8,
            canAfford: true,
            onchainBalance: 50000
        ),
        onchainBalance: 50000
    )
    .padding()
}

#Preview("Cannot Afford") {
    ExitCostEstimateCard(
        spendableBalance: 100000,
        estimate: ExitCostEstimate(
            lowCost: 12000,
            totalCost: 15000,
            highCost: 18000,
            minTransactions: 4,
            maxTransactions: 7,
            feeRate: 8,
            canAfford: false,
            onchainBalance: 5000
        ),
        onchainBalance: 5000
    )
    .padding()
}

#Preview("Single Estimate") {
    ExitCostEstimateCard(
        spendableBalance: 100000,
        estimate: ExitCostEstimate(
            lowCost: 15000,
            totalCost: 15000,
            highCost: 15000,
            minTransactions: 4,
            maxTransactions: 4,
            feeRate: 8,
            canAfford: true,
            onchainBalance: 50000
        ),
        onchainBalance: 50000
    )
    .padding()
}
