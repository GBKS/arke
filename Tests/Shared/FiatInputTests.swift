//
//  FiatInputTests.swift
//  ArkéTests
//
//  Fiat entry helpers (Docs/Features/Fiat_Rates.md, Phase 4): minor units
//  per currency, machine-form parsing, and the localized partial-input
//  formatting shown while typing.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Fiat Input")
struct FiatInputTests {

    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    /// NumberFormatter pads with non-breaking spaces; compare on plain ones
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test("Minor units follow ISO 4217: USD 2, EUR 2, JPY 0, KWD 3")
    func fractionDigits() {
        #expect(FiatConversion.fractionDigits(for: "USD") == 2)
        #expect(FiatConversion.fractionDigits(for: "EUR") == 2)
        #expect(FiatConversion.fractionDigits(for: "JPY") == 0)
        #expect(FiatConversion.fractionDigits(for: "KWD") == 3)
    }

    @Test("Machine-form parsing accepts a trailing separator and rejects empty input")
    func parseInput() {
        #expect(FiatConversion.parseInput("12") == Decimal(12))
        #expect(FiatConversion.parseInput("12.") == Decimal(12))
        #expect(FiatConversion.parseInput("12.50") == Decimal(string: "12.50"))
        #expect(FiatConversion.parseInput("0.5") == Decimal(string: "0.5"))
        #expect(FiatConversion.parseInput("") == nil)
    }

    @Test("Partial input keeps exactly the digits typed, en_US")
    func partialInputEnUS() {
        #expect(FiatConversion.formatPartialInput("", currency: "USD", locale: enUS) == "$0.00")
        #expect(FiatConversion.formatPartialInput("12", currency: "USD", locale: enUS) == "$12")
        #expect(FiatConversion.formatPartialInput("12.", currency: "USD", locale: enUS) == "$12.")
        #expect(FiatConversion.formatPartialInput("12.5", currency: "USD", locale: enUS) == "$12.5")
        #expect(FiatConversion.formatPartialInput("12.50", currency: "USD", locale: enUS) == "$12.50")
        #expect(FiatConversion.formatPartialInput("1234567", currency: "USD", locale: enUS) == "$1,234,567")
        #expect(FiatConversion.formatPartialInput("1300", currency: "JPY", locale: enUS) == "¥1,300")
    }

    @Test("Partial input uses the locale's separator and symbol placement, de_DE")
    func partialInputDeDE() {
        #expect(plain(FiatConversion.formatPartialInput("12.5", currency: "USD", locale: deDE)) == "12,5 $")
        #expect(plain(FiatConversion.formatPartialInput("12.", currency: "EUR", locale: deDE)) == "12, €")
        #expect(plain(FiatConversion.formatPartialInput("1234567", currency: "EUR", locale: deDE)) == "1.234.567 €")
    }

    @Test("Back-filling the fiat buffer trims to the currency's minor units")
    func inputStringBackfill() {
        #expect(FiatConversion.inputString(for: Decimal(string: "85.84188")!, currency: "USD") == "85.84")
        #expect(FiatConversion.inputString(for: Decimal(string: "13480.2545")!, currency: "JPY") == "13480")
        #expect(FiatConversion.inputString(for: Decimal(10), currency: "USD") == "10")
        #expect(FiatConversion.inputString(for: Decimal(string: "0.5")!, currency: "EUR") == "0.5")
    }

    @Test("Sats round-trip through fiat entry: $10 → 11,649 sats → $10.00")
    func roundTrip() {
        let rate = Decimal(string: "85841.88")!
        let sats = FiatConversion.sats(fiatAmount: 10, rate: rate)
        #expect(sats == 11_649)
        let back = FiatConversion.fiatAmount(sats: 11_649, rate: rate)
        #expect(FiatConversion.inputString(for: back, currency: "USD") == "10")
    }
}
