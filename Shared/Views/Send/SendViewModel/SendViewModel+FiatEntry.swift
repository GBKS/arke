//
//  SendViewModel+FiatEntry.swift
//  Arké
//
//  Entering the send amount in the user's bitcoin unit format or in the
//  display currency (Docs/Features/Fiat_Rates.md §7, Phase 4). `amount` —
//  whole sats as a string — stays the source of truth that fees,
//  validation and execution already read. Both fields are typed-text
//  buffers: a keystroke parses the text and writes `amount` once (fiat at
//  that moment's rate); a rates refresh never touches it; swapping units
//  carries the exact sats over. The rules live in AmountEntryState
//  (tested); this file wires them to the view model's fields.
//

import Foundation
import ArkeUI

extension SendViewModel {

    /// Whether the fiat field is the one being typed into
    var isFiatEntry: Bool {
        amountEntry.mode == .fiat
    }

    /// The sats-string parser/formatter pair: the send amount is always whole sats
    private static let parseSats: (String) -> Int? = { Int($0) }
    private static let formatSats: (Int) -> String = { String($0) }

    private func writeAmount(_ sats: Int?) {
        let newAmount = sats.map(Self.formatSats) ?? ""
        if newAmount != amount {
            amount = newAmount
            isSendingMax = false
        }
    }

    // MARK: - Bitcoin field

    /// A bitcoin keystroke: keep the typed text, parse it in the unit
    /// format ("0.5" is half a bitcoin under a decimal format, 50000 sats
    /// under sats), and write the sats into `amount`
    func setBitcoinText(_ text: String, locale: Locale = .autoupdatingCurrent) {
        bitcoinAmountText = text
        let machine = FiatConversion.machineForm(fromTyped: text, locale: locale)
        let sats = machine.isEmpty ? nil : BitcoinFormatter.shared.parseUserInput(machine)
        writeAmount(sats)
    }

    /// `amount` changed from outside the bitcoin field — Max, a request's
    /// fixed amount, a clear, or the unit format itself changed — so the
    /// typed text no longer matches. Re-fill it in the current format.
    func syncBitcoinTextIfNeeded(locale: Locale = .autoupdatingCurrent) {
        guard !isFiatEntry else { return }
        let typedSats = bitcoinAmountText.isEmpty
            ? nil
            : BitcoinFormatter.shared.parseUserInput(FiatConversion.machineForm(fromTyped: bitcoinAmountText, locale: locale))
        let sats = Self.parseSats(amount)
        guard typedSats != sats else { return }
        bitcoinAmountText = sats.map {
            FiatConversion.typedForm(fromMachine: BitcoinFormatter.shared.inputString(forSatoshis: $0), locale: locale)
        } ?? ""
    }

    // MARK: - Fiat field

    /// A fiat keystroke: keep the typed text, recompute sats once at `rate`,
    /// and write them into `amount` so everything downstream updates
    func setFiatText(_ text: String, rate: Decimal, locale: Locale = .autoupdatingCurrent) {
        fiatAmountText = text
        amountEntry.setFiatInput(FiatConversion.machineForm(fromTyped: text, locale: locale), rate: rate)
        writeAmount(amountEntry.amountSats(parseBitcoin: Self.parseSats))
    }

    /// `amount` changed from outside the fiat field while in fiat mode.
    /// Adopt the new sats and back-fill the fiat text from them. A no-op
    /// when the change came from `setFiatText` itself, so there is no
    /// feedback loop.
    func syncFiatEntryIfNeeded(rate: Decimal, currency: String, locale: Locale = .autoupdatingCurrent) {
        guard isFiatEntry else { return }
        let sats = Self.parseSats(amount).flatMap { $0 > 0 ? $0 : nil }
        guard sats != amountEntry.amountSats(parseBitcoin: Self.parseSats) else { return }
        amountEntry.adoptSatsIntoFiat(sats, rate: rate, currency: currency)
        fiatAmountText = FiatConversion.typedForm(fromMachine: amountEntry.fiatInput, locale: locale)
    }

    // MARK: - Swapping

    /// Make fiat the field. The current sats carry over unchanged; the fiat
    /// text is back-filled from them in the locale's typed form.
    func switchToFiatEntry(rate: Decimal, currency: String, locale: Locale = .autoupdatingCurrent) {
        amountEntry.bitcoinInput = amount
        amountEntry.switchToFiat(rate: rate, currency: currency, parseBitcoin: Self.parseSats)
        fiatAmountText = FiatConversion.typedForm(fromMachine: amountEntry.fiatInput, locale: locale)
    }

    /// Make bitcoin the field again, carrying the current sats over and
    /// back-filling the typed text in the unit format
    func switchToBitcoinEntry(locale: Locale = .autoupdatingCurrent) {
        amountEntry.switchToBitcoin(formatBitcoinInput: Self.formatSats, parseBitcoin: Self.parseSats)
        writeAmount(Self.parseSats(amountEntry.bitcoinInput))
        fiatAmountText = ""
        bitcoinAmountText = Self.parseSats(amount).map {
            FiatConversion.typedForm(fromMachine: BitcoinFormatter.shared.inputString(forSatoshis: $0), locale: locale)
        } ?? ""
    }
}
