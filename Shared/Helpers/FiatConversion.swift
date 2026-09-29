//
//  FiatConversion.swift
//  Arké
//
//  Sats ↔ fiat arithmetic and currency formatting, all in Decimal
//  (Docs/Features/Fiat_Rates.md). Sats are the real amount; fiat is
//  display only. Kept apart from BitcoinFormatter, which works in Double
//  and formats bitcoin units, not money.
//
//  The "input" helpers serve fiat *entry* (Phase 4): the keypad writes a
//  machine-form string — digits with "." as separator — and these turn it
//  into a Decimal, or into the localized text shown while typing.
//

import Foundation

nonisolated enum FiatConversion {

    nonisolated static let satsPerBitcoin = Decimal(100_000_000)

    /// Locale used for the keypad's machine-form strings ("." separator, no grouping)
    private nonisolated static let machineLocale = Locale(identifier: "en_US_POSIX")

    // MARK: - Arithmetic

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

    // MARK: - Formatting

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

    // MARK: - Entry

    /// A currency's minor units — how many fraction digits the keypad may
    /// accept: USD/EUR 2, JPY 0, KWD 3. Read off the system's currency
    /// formatter defaults, so it tracks ISO 4217 without a table here.
    nonisolated static func fractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    /// Parses the keypad's machine-form string ("12", "12.", "12.50") into
    /// a Decimal. Nil for an empty or malformed string.
    nonisolated static func parseInput(_ raw: String) -> Decimal? {
        guard !raw.isEmpty else { return nil }
        let normalized = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        return Decimal(string: normalized, locale: machineLocale)
    }

    /// Formats a machine-form entry as it is typed, in the currency's own
    /// style: grouping, symbol placement and the locale's decimal separator,
    /// keeping exactly the fraction digits typed so far and a trailing
    /// separator when one was just entered. "12." → "$12." (en_US),
    /// "12.5" → "12,5 $" (de_DE). Empty → the currency's zero ("$0.00").
    nonisolated static func formatPartialInput(
        _ raw: String,
        currency code: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard !raw.isEmpty else {
            return formatted(0, currency: code, locale: locale)
        }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let fractionDigits = parts.count > 1 ? parts[1].count : nil
        let value = parseInput(raw) ?? 0

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = fractionDigits ?? 0
        formatter.maximumFractionDigits = fractionDigits ?? 0
        formatter.alwaysShowsDecimalSeparator = fractionDigits == 0
        formatter.roundingMode = .down
        return formatter.string(from: value as NSDecimalNumber) ?? raw
    }

    /// The currency symbol as the locale shows it ("€", "US$", "¥"), for a
    /// prefix beside a text field
    nonisolated static func symbol(for code: String, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// Machine form of text typed on a system decimal pad, whose separator
    /// follows the locale ("12,50" on a German keyboard → "12.50"). Keeps
    /// digits only; accepts the locale's separator or "." as the one
    /// decimal separator; anything else (grouping, letters) is dropped.
    nonisolated static func machineForm(fromTyped text: String, locale: Locale = .autoupdatingCurrent) -> String {
        let separator = locale.decimalSeparator ?? "."
        var result = ""
        var sawSeparator = false
        for character in text.replacingOccurrences(of: separator, with: ".") {
            if character.isASCII, character.isNumber {
                result.append(character)
            } else if character == ".", !sawSeparator {
                result.append(".")
                sawSeparator = true
            }
        }
        return result
    }

    /// The reverse: a machine-form string as the locale's keyboard would
    /// have typed it ("12.50" → "12,50" in Germany), for back-filling a field
    nonisolated static func typedForm(fromMachine raw: String, locale: Locale = .autoupdatingCurrent) -> String {
        raw.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    /// The machine-form string for a fiat amount, trimmed to the currency's
    /// minor units — used to back-fill the fiat buffer when switching input
    /// modes. 85.84188 USD → "85.84"; 13480.25 JPY → "13480".
    nonisolated static func inputString(for amount: Decimal, currency code: String) -> String {
        var rounded = Decimal()
        var source = amount
        NSDecimalRound(&rounded, &source, fractionDigits(for: code), .plain)
        return rounded.formatted(.number.locale(machineLocale).grouping(.never).precision(.fractionLength(0...fractionDigits(for: code))))
    }
}
