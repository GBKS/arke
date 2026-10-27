//
//  OnchainFeeQuote.swift
//  Arké
//
//  One BDK quote for an onchain send: the exact fee at every priority tier
//  for one address and amount, at the rates in force when it was made.
//  Everything the fee depends on is part of the quote, so a quote either
//  matches the current inputs exactly or does not count at all; there is
//  no partially stale quote.
//

import Foundation
import ArkeUI

struct OnchainFeeQuote: Equatable, Sendable {
    let address: String
    let amountSats: Int
    let rates: OnchainFeeRates
    let fees: [FeePriority: Int]

    /// True when this quote was made for exactly these inputs
    func matches(address: String, amountSats: Int, rates: OnchainFeeRates) -> Bool {
        self.address == address && self.amountSats == amountSats && self.rates == rates
    }

    func fee(for priority: FeePriority) -> Int? {
        fees[priority]
    }

    /// What the fee row shows for an onchain destination.
    ///
    /// A matching quote wins and switches tiers without a new request. With
    /// no matching quote the row says so: "estimating" while the newest
    /// request is open, otherwise the approximate placeholder, marked as
    /// such. The placeholder is never shown while a request is open, and a
    /// quote for other inputs is never shown at all.
    static func displayState(
        quote: OnchainFeeQuote?,
        address: String,
        amountSats: Int?,
        rates: OnchainFeeRates,
        priority: FeePriority,
        isEstimating: Bool,
        roughFee: Int
    ) -> FeeDisplayState {
        if let amountSats, let quote,
           quote.matches(address: address, amountSats: amountSats, rates: rates),
           let fee = quote.fee(for: priority) {
            return .value(fee)
        }
        if isEstimating {
            return .estimating
        }
        return .approximate(roughFee)
    }
}
