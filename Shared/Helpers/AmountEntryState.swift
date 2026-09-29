//
//  AmountEntryState.swift
//  Arké
//
//  The rules for entering an amount in either bitcoin or fiat
//  (Docs/Features/Fiat_Rates.md §7, Phase 4). Pure and nonisolated so the
//  swap/back-fill/recompute behaviour is unit-tested without views.
//
//  Sats are the source of truth. In bitcoin mode they are parsed from the
//  bitcoin buffer; in fiat mode they were captured at the last fiat
//  keystroke, at that moment's rate, and a later rates refresh must never
//  move them. The buffers are the keypad's machine form ("." separator).
//

import Foundation

nonisolated struct AmountEntryState: Equatable, Sendable {

    enum Mode: Equatable, Sendable {
        case bitcoin
        case fiat
    }

    var mode: Mode = .bitcoin

    /// Typed bitcoin amount in the unit format's machine form
    /// ("0.5" under a decimal format, "50000" under sats)
    var bitcoinInput = ""

    /// Typed fiat amount, machine form ("12.50")
    var fiatInput = ""

    /// Sats captured at the last fiat keystroke or swap — the truth in fiat mode
    private(set) var fiatSats: Int?

    /// Whether the active buffer is empty
    var isEmpty: Bool {
        switch mode {
        case .bitcoin: return bitcoinInput.isEmpty
        case .fiat: return fiatInput.isEmpty
        }
    }

    /// The amount in whole sats, or nil when nothing positive is entered
    /// - Parameter parseBitcoin: The unit-format parser (BitcoinFormatter.parseUserInput)
    func amountSats(parseBitcoin: (String) -> Int?) -> Int? {
        switch mode {
        case .bitcoin:
            return parseBitcoin(bitcoinInput).flatMap { $0 > 0 ? $0 : nil }
        case .fiat:
            return fiatSats
        }
    }

    // MARK: - Editing

    /// A fiat keystroke: store the text and recompute sats once, now
    mutating func setFiatInput(_ raw: String, rate: Decimal) {
        fiatInput = raw
        fiatSats = FiatConversion.parseInput(raw)
            .flatMap { FiatConversion.sats(fiatAmount: $0, rate: rate) }
            .flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: - Swapping

    /// Make fiat the field. The current sats carry over unchanged; the
    /// fiat buffer is back-filled from them, trimmed to the currency's
    /// minor units.
    mutating func switchToFiat(rate: Decimal, currency: String, parseBitcoin: (String) -> Int?) {
        let sats = amountSats(parseBitcoin: parseBitcoin)
        fiatSats = sats
        fiatInput = sats.map {
            FiatConversion.inputString(for: FiatConversion.fiatAmount(sats: $0, rate: rate), currency: currency)
        } ?? ""
        mode = .fiat
    }

    /// Make bitcoin the field. The current sats carry over; the bitcoin
    /// buffer is back-filled in the unit format's machine form.
    /// - Parameter formatBitcoinInput: BitcoinFormatter.inputString(forSatoshis:)
    mutating func switchToBitcoin(formatBitcoinInput: (Int) -> String, parseBitcoin: (String) -> Int?) {
        let sats = amountSats(parseBitcoin: parseBitcoin)
        bitcoinInput = sats.map(formatBitcoinInput) ?? ""
        mode = .bitcoin
    }

    /// Clear everything and return to bitcoin mode
    mutating func reset() {
        self = AmountEntryState()
    }
}
