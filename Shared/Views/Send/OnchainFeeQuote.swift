//
//  OnchainFeeQuote.swift
//  Arké
//
//  One BDK quote for an onchain send: a result for every priority tier for
//  one address and amount, at the rates in force when it was made.
//  Everything the fee depends on is part of the quote, and every tier has
//  a result (a fee, or "this tier does not fit the balance"), so a quote
//  either matches the current inputs completely or does not count at all.
//  Review finding F2 (2026-10-27): after "Max" at one tier the faster
//  tiers cannot be built, and a quote with holes would have shown the
//  approximate placeholder for a tier BDK had already priced out.
//

import Foundation
import ArkeUI

/// What BDK said about one tier
enum OnchainTierQuote: Equatable, Sendable {
    /// Exact fee in satoshis
    case fee(Int)
    /// The amount plus this tier's fee exceeds the spendable onchain balance
    case unaffordable
}

struct OnchainFeeQuote: Equatable, Sendable {
    let address: String
    let amountSats: Int
    let rates: OnchainFeeRates
    let tiers: [FeePriority: OnchainTierQuote]

    /// True when this quote was made for exactly these inputs
    func matches(address: String, amountSats: Int, rates: OnchainFeeRates) -> Bool {
        self.address == address && self.amountSats == amountSats && self.rates == rates
    }

    /// The exact fee at a tier; nil when the tier does not fit the balance
    func fee(for priority: FeePriority) -> Int? {
        if case .fee(let fee)? = tiers[priority] {
            return fee
        }
        return nil
    }

    func isUnaffordable(_ priority: FeePriority) -> Bool {
        tiers[priority] == .unaffordable
    }

    /// What the fee row shows for an onchain destination.
    ///
    /// A matching quote wins and switches tiers without a new request: a
    /// priced tier shows its fee, a tier that does not fit says so. With no
    /// matching quote the row says what it knows: "estimating" while the
    /// newest request is open, otherwise the approximate placeholder,
    /// marked as such. The placeholder is never shown while a request is
    /// open, and a quote for other inputs is never shown at all.
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
           quote.matches(address: address, amountSats: amountSats, rates: rates) {
            switch quote.tiers[priority] {
            case .fee(let fee)?:
                return .value(fee)
            case .unaffordable?:
                return .unaffordable
            case nil:
                break
            }
        }
        if isEstimating {
            return .estimating
        }
        return .approximate(roughFee)
    }
}
