//
//  SendGateTests.swift
//  ArkéTests
//
//  The Send button's gate: refuse up front, with a reason, any send that
//  would pay an unseen fee or that bark would reject. And the send-all cap
//  that keeps the shadow wallet's view of the coins inside bark's.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Send gate")
struct SendGateTests {

    private func gate(
        amount: Int? = 1_000,
        locked: Bool = false,
        minimum: Int = 546,
        available: Int = 100_000,
        fee: FeeDisplayState = .value(500),
        onchain: Bool = true,
        ceiling: Bool = false
    ) -> SendBlocker? {
        SendBlocker.evaluate(
            amountSats: amount, isAmountLocked: locked, minimumSendAmount: minimum,
            availableSats: available, feeState: fee, isOnchain: onchain,
            fastTierAtMainnetCeiling: ceiling
        )
    }

    @Test("A priced fee that fits lets the send through")
    func fittingSendPasses() {
        #expect(gate() == nil)
    }

    @Test("Mainnet estimator at the ceiling pauses onchain sending, whatever else is true")
    func ceilingPausesOnchainOnly() {
        #expect(gate(ceiling: true) == .feeEstimateUnreliable)
        #expect(gate(amount: nil, ceiling: true) == .feeEstimateUnreliable)
        #expect(gate(onchain: false, ceiling: true) == nil)
    }

    @Test("A locked amount needs no entry and is not gated by the minimum")
    func lockedAmountPasses() {
        #expect(gate(amount: nil, locked: true, onchain: false) == nil)
    }

    @Test("No amount is simply off, with no line")
    func noAmountHasNoReason() {
        #expect(gate(amount: nil) == .noAmount)
        #expect(SendBlocker.noAmount.reason == nil)
    }

    @Test("Below the minimum is off; the amount card already explains")
    func belowMinimumHasNoReason() {
        #expect(gate(amount: 300) == .belowMinimum)
        #expect(SendBlocker.belowMinimum.reason == nil)
    }

    @Test("An open onchain quote blocks the send until the fee is known")
    func estimatingBlocksOnchain() {
        #expect(gate(fee: .estimating) == .estimatingFee)
        #expect(gate(fee: .estimating, onchain: false) == nil)
    }

    @Test("A speed the wallet priced out of the balance blocks with a nudge to a slower one")
    func unaffordableTierBlocks() {
        #expect(gate(fee: .unaffordable) == .unaffordableTier)
        #expect(SendBlocker.unaffordableTier.reason != nil)
    }

    @Test("Amount plus the shown fee must fit the balance, approximate fees included")
    func exceedsAvailableCountsTheFee() {
        #expect(gate(amount: 99_600, fee: .value(500)) == .exceedsAvailable)
        #expect(gate(amount: 99_600, fee: .approximate(500)) == .exceedsAvailable)
        #expect(gate(amount: 99_500, fee: .value(500)) == nil)
        #expect(gate(amount: 100_001, fee: .unavailable, onchain: false) == .exceedsAvailable)
    }

    @Test("Send-all offers no more than bark can spend after the fee")
    func sendAllCapsAtBark() {
        // Shadow wallet sees 8,839 sats bark does not (the 2026-10-27 simulator case)
        #expect(OnchainSendAll.cappedAmount(drainAmountSats: 141_960, drainFeeSats: 8_451, barkSpendableSats: 141_572) == 133_121)
        // Views agree: the drain amount stands
        #expect(OnchainSendAll.cappedAmount(drainAmountSats: 90_000, drainFeeSats: 1_000, barkSpendableSats: 91_000) == 90_000)
        // Fee alone exceeds what bark holds: nothing to offer
        #expect(OnchainSendAll.cappedAmount(drainAmountSats: 500, drainFeeSats: 1_000, barkSpendableSats: 900) == nil)
    }
}
