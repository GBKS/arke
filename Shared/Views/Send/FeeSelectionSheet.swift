//
//  FeeSelectionSheet.swift
//  Arké
//
//  Created by Assistant on 3/25/26.
//  2026-10-27: one row per distinct rate (FeeTierGroup), each showing its
//  exact fee when the flow holds a quote for the current send, so the
//  choice is a comparison between real alternatives.
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

    private var groups: [FeeTierGroup] {
        FeeTierGroup.groups(from: feeRates)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(String(localized: "send_payment_speed_question", defaultValue: "How fast should the payment arrive?"))
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 30)

            // One option per distinct rate, labelled by its fastest tier
            VStack(spacing: 12) {
                ForEach(groups) { group in
                    FeeOptionRow(
                        priority: group.representative,
                        feeSats: quote?.fee(for: group.representative),
                        isUnaffordable: quote?.isUnaffordable(group.representative) ?? false,
                        isEstimating: isEstimating,
                        isSelected: group.contains(selectedPriority),
                        onSelect: {
                            selectedPriority = group.representative
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
