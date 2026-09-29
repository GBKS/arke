//
//  FiatAmountText.swift
//  Arké
//
//  The one way fiat appears next to a sats amount (Docs/Features/Fiat_Rates.md
//  §4 "Staleness"). Resolves the display currency, looks up its snapshot,
//  and renders "≈ $83.38" when fresh, a dimmed "≈ $83.38 · 2 hr. ago" when
//  stale, and nothing at all when the rate is unavailable (missing, a day
//  old, or the currency set to "None"). Callers style it with the usual
//  font/colour modifiers.
//
//  `FiatAmountText.spoken(...)` gives the same decision as a plain string
//  in VoiceOver phrasing ("approximately $83.38"), for accessibility
//  values on containers that summarise a whole card.
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

    /// Render nothing for a zero amount — for static balances, where
    /// "≈ $0.00" adds noise without information
    var hidesZero: Bool = false

    @Environment(\.ratesService) private var ratesService
    @AppStorage(UserDefaults.fiatCurrencyKey) private var storedCurrency: String = ""

    var body: some View {
        // Re-evaluate freshness once a minute so a rate can cross into
        // "stale" or "unavailable" while the screen sits open
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let display = Self.display(
                sats: sats,
                ratesService: ratesService,
                storedCurrency: storedCurrency,
                showsStaleAge: showsStaleAge,
                hidesZero: hidesZero,
                now: context.date
            ) {
                Text(display.text)
                    .opacity(display.isStale ? 0.6 : 1)
                    .contentTransition(.numericText())
                    // "≈" would be read as a symbol; say it in words
                    .accessibilityLabel(display.spoken)
            }
        }
    }

    // MARK: - Shared decision

    struct Display {
        /// On-screen form, e.g. "≈ $83.38" or "≈ $83.38 · 2 hr. ago"
        let text: String
        /// VoiceOver form, e.g. "approximately $83.38" or "approximately $83.38, as of 2 hours ago"
        let spoken: String
        let isStale: Bool
    }

    /// The single place that decides whether and how a fiat value shows.
    /// Nil means "show nothing": zero (when hidden), currency "None", no
    /// snapshot, or a snapshot a day old.
    @MainActor
    static func display(
        sats: Int,
        ratesService: RatesService,
        storedCurrency: String,
        showsStaleAge: Bool = true,
        hidesZero: Bool = false,
        now: Date = Date()
    ) -> Display? {
        if hidesZero && sats == 0 { return nil }

        let currency = FiatCurrencyPreference.resolve(
            stored: storedCurrency,
            available: ratesService.availableCurrencies
        )
        // "None" in settings hides fiat everywhere
        guard !FiatCurrencyPreference.isNone(currency),
              let snapshot = ratesService.rate(for: currency) else { return nil }

        let amount = FiatConversion.formattedFiat(sats: sats, rate: snapshot.value, currency: currency)
        let approx = String(localized: "fiat_approx", defaultValue: "≈ \(amount)")
        let spokenApprox = String(localized: "fiat_approx_spoken", defaultValue: "approximately \(amount)")

        switch RateFreshness(snapshot: snapshot, now: now) {
        case .unavailable:
            return nil
        case .fresh:
            return Display(text: approx, spoken: spokenApprox, isStale: false)
        case .stale:
            guard showsStaleAge else {
                return Display(text: approx, spoken: spokenApprox, isStale: true)
            }
            let age = snapshot.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
            let spokenAge = snapshot.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
            return Display(
                text: String(localized: "fiat_approx_stale", defaultValue: "≈ \(amount) · \(age)"),
                spoken: String(localized: "fiat_approx_stale_spoken", defaultValue: "approximately \(amount), as of \(spokenAge)"),
                isStale: true
            )
        }
    }

    /// VoiceOver phrasing for a container's accessibility value, or nil when
    /// no fiat would show
    @MainActor
    static func spoken(
        sats: Int,
        ratesService: RatesService,
        storedCurrency: String,
        hidesZero: Bool = false
    ) -> String? {
        display(sats: sats, ratesService: ratesService, storedCurrency: storedCurrency, hidesZero: hidesZero)?.spoken
    }
}
