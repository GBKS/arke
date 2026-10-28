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
        ceiling: Bool = false,
        pricedFeeRequired: Bool = false
    ) -> SendBlocker? {
        SendBlocker.evaluate(
            amountSats: amount, isAmountLocked: locked, minimumSendAmount: minimum,
            availableSats: available, feeState: fee, isOnchain: onchain,
            fastTierAtMainnetCeiling: ceiling, requiresPricedFee: pricedFeeRequired
        )
    }

    @Test("A priced fee that fits lets the send through")
    func fittingSendPasses() {
        #expect(gate() == nil)
    }

    @Test("Paid from Payments: bark's fee is required, so unavailable and estimating both block (DECIDED 2026-10-27)")
    func paymentsSourceNeedsAPricedFee() {
        // Not the BDK path: no tier cases, no ceiling case
        #expect(gate(fee: .unavailable, onchain: false, pricedFeeRequired: true) == .feeUnavailable)
        #expect(gate(fee: .estimating, onchain: false, pricedFeeRequired: true) == .estimatingFee)
        #expect(gate(fee: .value(400), onchain: false, ceiling: true, pricedFeeRequired: true) == nil)
        #expect(gate(amount: 99_700, fee: .value(400), onchain: false, pricedFeeRequired: true) == .exceedsAvailable)
        // A locked amount is refused the same way
        #expect(gate(amount: 1_000, locked: true, fee: .unavailable, onchain: false, pricedFeeRequired: true) == .feeUnavailable)
        // Lightning keeps passing without a fee
        #expect(gate(fee: .unavailable, onchain: false) == nil)
    }

    @Test("Mainnet estimator at the ceiling pauses onchain sending, whatever else is true")
    func ceilingPausesOnchainOnly() {
        #expect(gate(ceiling: true) == .feeEstimateUnreliable)
        #expect(gate(amount: nil, ceiling: true) == .feeEstimateUnreliable)
        #expect(gate(onchain: false, ceiling: true) == nil)
    }

    @Test("A locked amount skips the minimum but an invoice above the balance is still refused")
    func lockedAmountPassesUnlessOverBalance() {
        #expect(gate(amount: nil, locked: true, onchain: false) == nil)
        #expect(gate(amount: 300, locked: true, onchain: false) == nil)
        #expect(gate(amount: 100_001, locked: true, fee: .unavailable, onchain: false) == .exceedsAvailable)
        #expect(gate(amount: 99_900, locked: true, fee: .value(200), onchain: false) == .exceedsAvailable)
    }

    @Test("A capped send-all shrinks to fit the re-quoted fee, and stands once it fits")
    func sendAllRefitsToTheRequotedFee() {
        // 133,121 + 8,451 == 141,572 fits exactly; one extra vbyte of fee does not
        #expect(OnchainSendAll.refit(amountSats: 133_121, requotedFeeSats: 8_451, barkSpendableSats: 141_572) == 133_121)
        #expect(OnchainSendAll.refit(amountSats: 133_121, requotedFeeSats: 8_600, barkSpendableSats: 141_572) == 132_972)
        #expect(OnchainSendAll.refit(amountSats: 500, requotedFeeSats: 1_000, barkSpendableSats: 900) == nil)
    }

    @Test("No amount is simply off")
    func noAmountIsOff() {
        #expect(gate(amount: nil) == .noAmount)
    }

    @Test("Below the minimum is off; the amount card explains after blur")
    func belowMinimumIsOff() {
        #expect(gate(amount: 300) == .belowMinimum)
    }

    @Test("An open onchain quote blocks the send until the fee is known")
    func estimatingBlocksOnchain() {
        #expect(gate(fee: .estimating) == .estimatingFee)
        #expect(gate(fee: .estimating, onchain: false) == nil)
    }

    @Test("A speed the wallet priced out of the balance blocks; the fee row says so")
    func unaffordableTierBlocks() {
        #expect(gate(fee: .unaffordable) == .unaffordableTier)
    }

    @Test("A fee row saying the estimate is unreliable blocks an onchain send")
    func unreliableFeeStateBlocks() {
        #expect(gate(fee: .unreliable) == .feeEstimateUnreliable)
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
