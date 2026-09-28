//
//  FiatRatesSectionView.swift
//  Arké
//
//  X-Ray section showing the state of the exchange-rate cache
//  (RatesService): how many currencies, how old the file is, when we
//  last checked and how that went. The only visible surface of the
//  fiat-rates Phase 1, so "loads properly" can be verified on device
//  without touching the main UI (Docs/Features/Fiat_Rates.md).
//

import SwiftUI
import ArkeUI

struct FiatRatesSectionView: View {
    var reloadTrigger: Int = 0
    @Environment(\.ratesService) private var ratesService

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(localized: "data_fiat_rates", defaultValue: "Exchange Rates"))
                    .font(.system(size: 24, design: .serif))

                Spacer()
            }

            if ratesService.cache.rates.isEmpty {
                VStack {
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_no_fiat_rates", defaultValue: "No exchange rates cached yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let outcomeText {
                        Text(outcomeText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledValueRow(
                        String(localized: "data_fiat_rates_currencies", defaultValue: "Currencies"),
                        value: "\(ratesService.cache.rates.count)"
                    )

                    if let usd = ratesService.rate(for: "USD") {
                        LabeledValueRow(
                            String(localized: "data_fiat_rates_usd", defaultValue: "1 BTC in USD"),
                            value: FiatConversion.formatted(usd.value, currency: "USD")
                        )
                    }

                    if let newest = ratesService.cache.newestUpdatedAt {
                        LabeledValueRow(
                            String(localized: "data_fiat_rates_file_time", defaultValue: "File time"),
                            value: newest.formatted(date: .abbreviated, time: .shortened),
                            valueColor: freshnessColor
                        )
                    }

                    if let lastChecked = ratesService.lastChecked {
                        LabeledValueRow(
                            String(localized: "data_fiat_rates_last_checked", defaultValue: "Last checked"),
                            value: lastChecked.formatted(date: .omitted, time: .standard)
                        )
                    }

                    if let outcomeText {
                        LabeledValueRow(
                            String(localized: "data_fiat_rates_last_result", defaultValue: "Last result"),
                            value: outcomeText
                        )
                    }

                    if let etag = ratesService.cache.etag {
                        LabeledValueRow("ETag", value: etag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            // Explicit reload bypasses the 60s gate; first appearance respects it
            if reloadTrigger > 0 {
                await ratesService.refresh()
            } else {
                await ratesService.refreshIfDue()
            }
        }
    }

    /// Colour the file time by the USD snapshot's freshness (every code in
    /// one file shares a timestamp, so USD stands in for the file)
    private var freshnessColor: Color? {
        switch ratesService.freshness(for: "USD") {
        case .fresh: return nil
        case .stale: return .orange
        case .unavailable: return .red
        }
    }

    private var outcomeText: String? {
        guard let outcome = ratesService.lastOutcome else { return nil }
        switch outcome {
        case .updated(let count):
            return String(localized: "data_fiat_rates_outcome_updated", defaultValue: "Updated (\(count) currencies)")
        case .notModified:
            return String(localized: "data_fiat_rates_outcome_not_modified", defaultValue: "Not modified")
        case .rejected(let reason):
            return String(localized: "data_fiat_rates_outcome_rejected", defaultValue: "Rejected: \(reason)")
        case .decodeFailed:
            return String(localized: "data_fiat_rates_outcome_decode_failed", defaultValue: "File did not decode")
        case .httpStatus(let status):
            return String(localized: "data_fiat_rates_outcome_http", defaultValue: "HTTP \(status)")
        case .networkError(let message):
            return String(localized: "data_fiat_rates_outcome_network", defaultValue: "Network error: \(message)")
        }
    }
}
