//
//  FeeSelectionSheet.swift
//  Arké
//
//  Created by Assistant on 3/25/26.
//  2026-10-27: each tier shows its exact fee when the flow holds a quote
//  for the current send, so the choice is a comparison, not a guess.
//

import SwiftUI
import ArkeUI

/// Sheet for selecting on-chain transaction fee priority
struct FeeSelectionSheet: View {
    @Binding var selectedPriority: FeePriority
    let feeRates: OnchainFeeRates
    /// The quote for the current address and amount, if the flow has one;
    /// the presenter passes nil for a quote that no longer matches
    var quote: OnchainFeeQuote? = nil
    /// A quote request is open
    var isEstimating: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(String(localized: "send_payment_speed_question", defaultValue: "How fast should the payment arrive?"))
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 30)

            // Fee options
            VStack(spacing: 12) {
                ForEach(FeePriority.allCases) { priority in
                    FeeOptionRow(
                        priority: priority,
                        feeRate: feeRates.rate(for: priority),
                        feeSats: quote?.fee(for: priority),
                        isEstimating: isEstimating,
                        isSelected: selectedPriority == priority,
                        onSelect: {
                            selectedPriority = priority
                            onDismiss()
                        }
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: 450)
    }
}
