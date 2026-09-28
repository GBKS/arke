//
//  FiatConversion.swift
//  Arké
//
//  Sats ↔ fiat arithmetic and currency formatting, all in Decimal
//  (Docs/Features/Fiat_Rates.md). Sats are the real amount; fiat is
//  display only. Kept apart from BitcoinFormatter, which works in Double
//  and formats bitcoin units, not money.
//

import Foundation

nonisolated enum FiatConversion {

    nonisolated static let satsPerBitcoin = Decimal(100_000_000)

    /// `sats × rate ÷ 100_000_000`, exact in Decimal
    nonisolated static func fiatAmount(sats: Int, rate: Decimal) -> Decimal {
        Decimal(sats) * rate / satsPerBitcoin
    }

    /// Whole sats for a typed fiat amount, rounded to the nearest sat.
    /// From here on the sats value is the source of truth — callers must
    /// never recompute it from fiat after a rates refresh. Nil for a
    /// non-positive rate or a negative amount.
    nonisolated static func sats(fiatAmount: Decimal, rate: Decimal) -> Int? {
        guard rate > 0, fiatAmount >= 0 else { return nil }
        var raw = fiatAmount * satsPerBitcoin / rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        guard rounded <= Decimal(Int.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Currency formatting with the code's own fraction digits (JPY 0, most others 2)
    nonisolated static func formatted(
        _ amount: Decimal,
        currency code: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        amount.formatted(.currency(code: code).locale(locale))
    }

    /// Convenience: convert and format in one step
    nonisolated static func formattedFiat(
        sats: Int,
        rate: Decimal,
        currency code: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(fiatAmount(sats: sats, rate: rate), currency: code, locale: locale)
    }
}
