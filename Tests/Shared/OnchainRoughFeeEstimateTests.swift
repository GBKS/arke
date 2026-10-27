//
//  OnchainRoughFeeEstimateTests.swift
//  ArkéTests
//
//  The rough onchain fee is a placeholder shown until BDK's exact estimate
//  lands. Its one job is not to undershoot the simplest real send, so the
//  user never watches the number go up when the estimate arrives.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Onchain rough fee estimate")
struct OnchainRoughFeeEstimateTests {

    /// Virtual size of a one-input, two-output Taproot transaction, which is
    /// the smallest send bark's BIP86 wallet builds (the 2026-10-27 signet
    /// estimate was 7,839 sats at 50 sat/vB, i.e. 157 vB).
    private let simplestTaprootSendVBytes: UInt64 = 154

    private func destination(_ format: AddressFormat) -> PaymentDestination {
        PaymentDestination(format: format, network: .signet, address: "tb1p-test")
    }

    @Test("Covers the simplest Taproot send at the same rate")
    func coversSimplestTaprootSend() {
        let rate: UInt64 = 50
        let rough = PaymentDestinationSelector.estimateOnchainFee(
            for: destination(.bitcoin), amount: 1_000, feeRate: rate
        )
        #expect(rough >= Int(rate * simplestTaprootSendVBytes))
    }

    @Test("Silent-payment destinations get the same floor, they pay to a Taproot output too")
    func silentPaymentsShareTheFloor() {
        let rate: UInt64 = 7
        let bitcoin = PaymentDestinationSelector.estimateOnchainFee(
            for: destination(.bitcoin), amount: nil, feeRate: rate
        )
        let silent = PaymentDestinationSelector.estimateOnchainFee(
            for: destination(.silentPayments), amount: nil, feeRate: rate
        )
        #expect(silent >= Int(rate * simplestTaprootSendVBytes))
        #expect(silent == bitcoin)
    }

    @Test("Scales with the rate, so the placeholder differs per tier")
    func scalesWithRate() {
        let slow = PaymentDestinationSelector.estimateOnchainFee(
            for: destination(.bitcoin), amount: nil, feeRate: 2
        )
        let fast = PaymentDestinationSelector.estimateOnchainFee(
            for: destination(.bitcoin), amount: nil, feeRate: 10
        )
        #expect(fast == slow * 5)
    }
}
