//
//  AmountEntryStateTests.swift
//  ArkéTests
//
//  Swap, back-fill and recompute rules for bitcoin/fiat amount entry
//  (Docs/Features/Fiat_Rates.md §7, Phase 4). The bitcoin parser/formatter
//  are injected as a sats-format pair so the tests do not depend on the
//  user's unit setting.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Amount Entry State")
struct AmountEntryStateTests {

    private let rate = Decimal(string: "85841.88")!
    private let parseSats: (String) -> Int? = { Int($0) }
    private let formatSats: (Int) -> String = { String($0) }

    @Test("Bitcoin mode parses the bitcoin buffer; empty or zero is nil")
    func bitcoinMode() {
        var state = AmountEntryState()
        #expect(state.amountSats(parseBitcoin: parseSats) == nil)
        state.bitcoinInput = "0"
        #expect(state.amountSats(parseBitcoin: parseSats) == nil)
        state.bitcoinInput = "11649"
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_649)
        #expect(!state.isEmpty)
    }

    @Test("A fiat keystroke recomputes sats once at that moment's rate")
    func fiatKeystroke() {
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("10", rate: rate)
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_649)
        state.setFiatInput("10.", rate: rate)
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_649)
        state.setFiatInput("", rate: rate)
        #expect(state.amountSats(parseBitcoin: parseSats) == nil)
        #expect(state.isEmpty)
    }

    @Test("A rates refresh never moves the sats captured in fiat mode")
    func ratesRefreshDoesNotRecompute() {
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("10", rate: rate)
        let captured = state.amountSats(parseBitcoin: parseSats)
        // The view would now hold a new rate; nothing was typed, so nothing changes
        #expect(state.amountSats(parseBitcoin: parseSats) == captured)
        // Only the next keystroke uses the new rate
        state.setFiatInput("10", rate: Decimal(90_000))
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_111)
    }

    @Test("Switching to fiat carries the exact sats over and back-fills the fiat buffer")
    func switchToFiat() {
        var state = AmountEntryState()
        state.bitcoinInput = "11649"
        state.switchToFiat(rate: rate, currency: "USD", parseBitcoin: parseSats)
        #expect(state.mode == .fiat)
        #expect(state.fiatInput == "10")
        // Exact sats survive even though the buffer shows a rounded $10
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_649)
    }

    @Test("Switching to bitcoin back-fills the bitcoin buffer from sats")
    func switchToBitcoin() {
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("10", rate: rate)
        state.switchToBitcoin(formatBitcoinInput: formatSats, parseBitcoin: parseSats)
        #expect(state.mode == .bitcoin)
        #expect(state.bitcoinInput == "11649")
        #expect(state.amountSats(parseBitcoin: parseSats) == 11_649)
    }

    @Test("Sats decided elsewhere (Max) are adopted in fiat mode, and the swap back carries them")
    func adoptSatsWhileInFiatMode() {
        // Type 5 € → 6,818 sats at 73,337.88 €/BTC
        let eurRate = Decimal(string: "73337.88")!
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("5", rate: eurRate)
        #expect(state.amountSats(parseBitcoin: parseSats) == 6_818)

        // Max writes 52,480 sats from outside the field
        state.adoptSatsIntoFiat(52_480, rate: eurRate, currency: "EUR")
        #expect(state.amountSats(parseBitcoin: parseSats) == 52_480)
        #expect(state.fiatInput == "38.49")

        // Swapping back to bitcoin carries the adopted sats, not the stale 6,818
        state.switchToBitcoin(formatBitcoinInput: formatSats, parseBitcoin: parseSats)
        #expect(state.bitcoinInput == "52480")

        // Clearing from outside empties the fiat side too
        state.mode = .fiat
        state.adoptSatsIntoFiat(nil, rate: eurRate, currency: "EUR")
        #expect(state.fiatInput == "")
        #expect(state.amountSats(parseBitcoin: parseSats) == nil)
    }

    @Test("Switching to fiat reads the bitcoin buffer, even if fiat state is stale")
    func switchToFiatReadsBitcoinBuffer() {
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("5", rate: rate)          // stale fiat side
        state.mode = .bitcoin
        state.bitcoinInput = "20000"
        state.switchToFiat(rate: rate, currency: "USD", parseBitcoin: parseSats)
        #expect(state.amountSats(parseBitcoin: parseSats) == 20_000)
        #expect(state.fiatInput == "17.17")
    }

    @Test("Swapping with nothing entered leaves both buffers empty")
    func swapEmpty() {
        var state = AmountEntryState()
        state.switchToFiat(rate: rate, currency: "USD", parseBitcoin: parseSats)
        #expect(state.fiatInput == "")
        #expect(state.amountSats(parseBitcoin: parseSats) == nil)
        state.switchToBitcoin(formatBitcoinInput: formatSats, parseBitcoin: parseSats)
        #expect(state.bitcoinInput == "")
    }

    @Test("JPY back-fill has no fraction digits")
    func jpyBackfill() {
        var state = AmountEntryState()
        state.bitcoinInput = "100000"
        state.switchToFiat(rate: Decimal(string: "13480254.5")!, currency: "JPY", parseBitcoin: parseSats)
        #expect(state.fiatInput == "13480")
    }

    @Test("Reset clears everything and returns to bitcoin mode")
    func reset() {
        var state = AmountEntryState()
        state.mode = .fiat
        state.setFiatInput("5", rate: rate)
        state.reset()
        #expect(state == AmountEntryState())
    }
}
