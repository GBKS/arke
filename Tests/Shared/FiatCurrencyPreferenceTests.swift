//
//  FiatCurrencyPreferenceTests.swift
//  ArkéTests
//
//  Display-currency resolution and picker ordering
//  (Docs/Features/Fiat_Rates.md §4 "Currency selection").
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Fiat Currency Preference")
struct FiatCurrencyPreferenceTests {

    private let available = ["EUR", "GBP", "JPY", "USD"]

    @Test("A stored choice wins, even when the cache lacks it")
    func storedChoiceWins() {
        #expect(FiatCurrencyPreference.resolve(stored: "EUR", available: available, locale: Locale(identifier: "en_US")) == "EUR")
        #expect(FiatCurrencyPreference.resolve(stored: "CHF", available: available, locale: Locale(identifier: "en_US")) == "CHF")
    }

    @Test("Nothing stored → the locale's currency when the cache has it")
    func localeCurrencyWhenAvailable() {
        #expect(FiatCurrencyPreference.resolve(stored: "", available: available, locale: Locale(identifier: "de_DE")) == "EUR")
        #expect(FiatCurrencyPreference.resolve(stored: nil, available: available, locale: Locale(identifier: "ja_JP")) == "JPY")
    }

    @Test("Locale currency missing from the cache, or no locale currency → USD")
    func fallsBackToUSD() {
        #expect(FiatCurrencyPreference.resolve(stored: "", available: available, locale: Locale(identifier: "de_CH")) == "USD")
        #expect(FiatCurrencyPreference.resolve(stored: "", available: [], locale: Locale(identifier: "de_DE")) == "USD")
        #expect(FiatCurrencyPreference.resolve(stored: "", available: available, locale: Locale(identifier: "en")) == "USD")
    }

    @Test("\"None\" is a stored choice like any other, and is never prepended to the picker")
    func noneChoice() {
        let resolved = FiatCurrencyPreference.resolve(stored: FiatCurrencyPreference.none, available: available, locale: Locale(identifier: "de_DE"))
        #expect(resolved == "none")
        #expect(FiatCurrencyPreference.isNone(resolved))
        #expect(!FiatCurrencyPreference.isNone("USD"))
        #expect(FiatCurrencyPreference.pickerOrder(available: available, selected: FiatCurrencyPreference.none, locale: Locale(identifier: "en_US")) == ["USD", "EUR", "GBP", "JPY"])
    }

    @Test("Picker order: locale currency first, then by code; a missing selection is prepended")
    func pickerOrder() {
        #expect(FiatCurrencyPreference.pickerOrder(available: available, selected: "USD", locale: Locale(identifier: "de_DE")) == ["EUR", "GBP", "JPY", "USD"])
        #expect(FiatCurrencyPreference.pickerOrder(available: available, selected: "GBP", locale: Locale(identifier: "ja_JP")) == ["JPY", "EUR", "GBP", "USD"])
        #expect(FiatCurrencyPreference.pickerOrder(available: available, selected: "CHF", locale: Locale(identifier: "en_US")) == ["CHF", "USD", "EUR", "GBP", "JPY"])
        #expect(FiatCurrencyPreference.pickerOrder(available: [], selected: "USD", locale: Locale(identifier: "en_US")) == ["USD"])
    }

    @Test("Localized names come from the locale, code as fallback")
    func localizedNames() {
        #expect(FiatCurrencyPreference.localizedName(for: "USD", locale: Locale(identifier: "en_US")) == "US Dollar")
        #expect(FiatCurrencyPreference.localizedName(for: "EUR", locale: Locale(identifier: "de_DE")) == "Euro")
    }
}
