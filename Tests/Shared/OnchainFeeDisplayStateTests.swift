//
//  OnchainFeeDisplayStateTests.swift
//  ArkéTests
//
//  The fee row's decision for onchain sends: a priced fee is shown only
//  when the quote was made for exactly the current inputs; a tier the
//  wallet priced out of the balance says so; otherwise the row says it is
//  estimating or marks the placeholder as approximate.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Onchain fee display state")
struct OnchainFeeDisplayStateTests {

    private let rates = OnchainFeeRates(fast: 50, medium: 20, slow: 5)
    private let address = "tb1p-current"
    private let rough = 3_100

    private func quote(
        address: String? = nil,
        amount: Int = 1_000,
        rates: OnchainFeeRates? = nil,
        tiers: [FeePriority: OnchainTierQuote] = [.fast: .fee(7_839), .medium: .fee(3_136), .slow: .fee(784)]
    ) -> OnchainFeeQuote {
        OnchainFeeQuote(
            address: address ?? self.address,
            amountSats: amount,
            rates: rates ?? self.rates,
            tiers: tiers
        )
    }

    private func state(
        quote: OnchainFeeQuote?,
        amount: Int? = 1_000,
        priority: FeePriority = .medium,
        isEstimating: Bool = false
    ) -> FeeDisplayState {
        OnchainFeeQuote.displayState(
            quote: quote, address: address, amountSats: amount, rates: rates,
            priority: priority, isEstimating: isEstimating, roughFee: rough
        )
    }

    @Test("A quote for exactly these inputs shows the priced fee")
    func matchingQuoteIsShown() {
        #expect(state(quote: quote()) == .value(3_136))
    }

    @Test("Switching the tier reads the same quote, no new request needed")
    func tierSwitchReadsTheQuote() {
        let q = quote()
        #expect(state(quote: q, priority: .fast) == .value(7_839))
        #expect(state(quote: q, priority: .slow) == .value(784))
    }

    @Test("A tier the wallet priced out of the balance says so, it is not 'not yet priced'")
    func unaffordableTierSaysSo() {
        // After "Max" at medium: medium fits exactly, fast does not
        let q = quote(tiers: [.fast: .unaffordable, .medium: .fee(3_136), .slow: .fee(784)])
        #expect(state(quote: q, priority: .fast) == .unaffordable)
        #expect(state(quote: q, priority: .fast, isEstimating: true) == .unaffordable)
        #expect(state(quote: q, priority: .medium) == .value(3_136))
        #expect(q.fee(for: .fast) == nil)
        #expect(q.isUnaffordable(.fast))
    }

    @Test("A quote for another amount never stands in, even for a moment")
    func otherAmountIsNotShown() {
        #expect(state(quote: quote(amount: 999), isEstimating: true) == .estimating)
        #expect(state(quote: quote(amount: 999)) == .approximate(rough))
    }

    @Test("A quote for another address never stands in")
    func otherAddressIsNotShown() {
        #expect(state(quote: quote(address: "tb1p-previous")) == .approximate(rough))
    }

    @Test("A quote made at other rates is stale")
    func otherRatesAreStale() {
        let old = OnchainFeeRates(fast: 60, medium: 25, slow: 6)
        #expect(state(quote: quote(rates: old)) == .approximate(rough))
    }

    @Test("Without an amount the row shows the approximate placeholder, not a priced fee")
    func noAmountIsApproximate() {
        #expect(state(quote: quote(), amount: nil) == .approximate(rough))
    }

    @Test("While the newest request is open the placeholder is hidden")
    func estimatingHidesThePlaceholder() {
        #expect(state(quote: nil, isEstimating: true) == .estimating)
    }

    @Test("A failed or absent quote shows the placeholder marked approximate")
    func noQuoteIsApproximate() {
        #expect(state(quote: nil) == .approximate(rough))
    }
}
