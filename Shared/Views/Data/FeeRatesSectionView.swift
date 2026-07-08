//
//  FeeRatesSectionView.swift
//  Arké
//
//  Created by Christoph on 7/8/26.
//
//  X-Ray section showing the current onchain fee rate tiers from
//  FeeRateService (the same rates used for exit cost estimates and
//  the Send flow fee picker).
//

import SwiftUI
import ArkeUI

struct FeeRatesSectionView: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @State private var feeRates: OnchainFeeRates?
    @State private var isLoadingFeeRates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(localized: "data_fee_rates", defaultValue: "Fee Rates"))
                    .font(.system(size: 24, design: .serif))

                Spacer()
            }

            if isLoadingFeeRates && feeRates == nil {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if let feeRates {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(FeePriority.allCases) { priority in
                        LabeledValueRow(priority.displayName, value: "\(feeRates.rate(for: priority)) sat/vB")
                    }

                    Group {
                        if let lastUpdated = walletManager.feeRateService?.lastUpdated {
                            Text(String(localized: "data_fee_rates_updated", defaultValue: "Updated: \(lastUpdated.formatted(date: .omitted, time: .standard))"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "data_fee_rates_fallback", defaultValue: "Fallback defaults (no Esplora data yet)"))
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_no_fee_rates", defaultValue: "No fee rate data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await loadFeeRates()
        }
    }

    private func loadFeeRates() async {
        isLoadingFeeRates = true

        // Force a fresh fetch on explicit reload; never throws, falls back
        // to last-known-good or default rates
        feeRates = await walletManager.currentFeeRates(maxAge: reloadTrigger > 0 ? 0 : 300)

        isLoadingFeeRates = false
    }
}
