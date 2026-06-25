//
//  FeeSelectionSheet.swift
//  Arké
//
//  Created by Assistant on 3/25/26.
//

import SwiftUI
import ArkeUI

/// Sheet for selecting on-chain transaction fee priority
struct FeeSelectionSheet: View {
    @Binding var selectedPriority: FeePriority
    let feeRates: OnchainFeeRates
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("How fast should the payment arrive?")
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 30)
            
            /*
            // Description
            Text("Choose how quickly you want your transaction to be confirmed")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            */
            
            // Fee options
            VStack(spacing: 12) {
                ForEach(FeePriority.allCases) { priority in
                    FeeOptionRow(
                        priority: priority,
                        feeRate: feeRates.rate(for: priority),
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
            
            /*
            // Done button
            Button {
                onDismiss()
            } label: {
                Text("button_done")
                    .font(.title3)
                    .foregroundStyle(Color.Arke.gold3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            */
        }
        .frame(maxWidth: 450)
    }
}
