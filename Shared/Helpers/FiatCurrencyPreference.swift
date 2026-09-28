//
//  FiatCurrencyPreference.swift
//  Arké
//
//  Which currency fiat values are displayed in (Docs/Features/Fiat_Rates.md
//  §4 "Currency selection"). The stored choice wins; otherwise the device
//  locale's currency when the rates cache has it; otherwise USD. "None"
//  is a valid choice that hides fiat everywhere. Pure, so the resolution
//  is unit-tested without UserDefaults.
//

import Foundation

nonisolated enum FiatCurrencyPreference {

    /// Used when nothing is stored and the locale's currency is unavailable
    static let fallback = "USD"

    /// Sentinel stored value for "show bitcoin amounts only" — hides fiat
    /// on every surface. Lower-case so it can never collide with an ISO code.
    static let none = "none"

    /// Resolve the display currency.
    /// - Parameters:
    ///   - stored: The persisted choice (`UserDefaults.fiatCurrencyKey`); empty means none chosen yet
    ///   - available: Codes present in the rates cache
    ///   - locale: Device locale, injectable for tests
    /// - Returns: An ISO 4217 code, or `none`. A stored code missing from
    ///   `available` is still returned — the spec treats it as "no snapshot"
    ///   (fiat hidden), not as a reason to silently switch currency.
    static func resolve(
        stored: String?,
        available: [String],
        locale: Locale = .current
    ) -> String {
        if let stored, !stored.isEmpty {
            return stored
        }
        if let localeCode = locale.currency?.identifier, available.contains(localeCode) {
            return localeCode
        }
        return fallback
    }

    /// Whether a resolved value means "no fiat anywhere"
    static func isNone(_ resolved: String) -> Bool {
        resolved == none
    }

    /// Human-readable currency name in the device language ("US Dollar"),
    /// falling back to the code itself
    static func localizedName(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Picker ordering of the currency rows (the "None" row is separate):
    /// the device locale's currency first when the cache has it, then
    /// everything else by code. A selected code that is missing from the
    /// cache is prepended so its selection stays visible.
    static func pickerOrder(
        available: [String],
        selected: String,
        locale: Locale = .current
    ) -> [String] {
        var ordered = available.sorted()
        if let localeCode = locale.currency?.identifier,
           let index = ordered.firstIndex(of: localeCode) {
            ordered.remove(at: index)
            ordered.insert(localeCode, at: 0)
        }
        if !isNone(selected), !ordered.contains(selected) {
            ordered.insert(selected, at: 0)
        }
        return ordered
    }
}
