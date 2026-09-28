//
//  FiatAmountText.swift
//  Arké
//
//  The one way fiat appears next to a sats amount (Docs/Features/Fiat_Rates.md
//  §4 "Staleness"). Resolves the display currency, looks up its snapshot,
//  and renders "≈ $83.38" when fresh, a dimmed "≈ $83.38 · 2 hr. ago" when
//  stale, and nothing at all when the rate is unavailable (missing, or a
//  day old). Callers style it with the usual font/colour modifiers.
//
//  Sats are the real amount. This view only ever reads; it never feeds a
//  value back into anything that is sent.
//

import SwiftUI
import ArkeUI

struct FiatAmountText: View {
    let sats: Int

    /// Append the file age when the rate is stale (15 min – 24 h old)
    var showsStaleAge: Bool = true

    @Environment(\.ratesService) private var ratesService
    @AppStorage(UserDefaults.fiatCurrencyKey) private var storedCurrency: String = ""

    var body: some View {
        // Re-evaluate freshness once a minute so a rate can cross into
        // "stale" or "unavailable" while the screen sits open
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let display = display(now: context.date) {
                Text(display.text)
                    .opacity(display.isStale ? 0.6 : 1)
                    .contentTransition(.numericText())
            }
        }
    }

    private func display(now: Date) -> (text: String, isStale: Bool)? {
        let currency = FiatCurrencyPreference.resolve(
            stored: storedCurrency,
            available: ratesService.availableCurrencies
        )
        guard let snapshot = ratesService.rate(for: currency) else { return nil }

        let amount = FiatConversion.formattedFiat(sats: sats, rate: snapshot.value, currency: currency)

        switch RateFreshness(snapshot: snapshot, now: now) {
        case .unavailable:
            return nil
        case .fresh:
            return (String(localized: "fiat_approx", defaultValue: "≈ \(amount)"), false)
        case .stale:
            guard showsStaleAge else {
                return (String(localized: "fiat_approx", defaultValue: "≈ \(amount)"), true)
            }
            let age = snapshot.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
            return (String(localized: "fiat_approx_stale", defaultValue: "≈ \(amount) · \(age)"), true)
        }
    }
}
