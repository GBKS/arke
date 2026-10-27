//
//  SendGate.swift
//  Arké
//
//  Why the Send button is disabled right now, and the one line under it
//  that says so. Explicit gates over hidden waits (DECIDED 2026-10-15): a
//  send that would pay a fee the user has not seen, or that bark would
//  reject, is refused up front with a reason, never attempted and failed.
//  The decision is pure so it can be tested; the view model feeds it.
//

import Foundation
import ArkeUI

enum SendBlocker: Equatable, Sendable {
    /// Nothing typed yet; the button is simply off, no line
    case noAmount
    /// Typed amount under the destination's minimum; the amount card shows the hint
    case belowMinimum
    /// Amount plus the fee shown exceeds the balance this destination spends from
    case exceedsAvailable
    /// An onchain quote request is open; the fee is not known yet
    case estimatingFee
    /// The wallet priced the chosen speed out of the balance
    case unaffordableTier
    /// Mainnet fast tier sits at the sanity ceiling: the estimator is not to be trusted
    case feeEstimateUnreliable

    /// The line under the Send button; nil when the disabled button is
    /// self-explanatory or another control already says why
    var reason: String? {
        switch self {
        case .noAmount, .belowMinimum:
            return nil
        case .exceedsAvailable:
            return String(localized: "send_blocked_exceeds_available", defaultValue: "More than your available balance")
        case .estimatingFee:
            return String(localized: "send_blocked_estimating_fee", defaultValue: "Estimating the fee…")
        case .unaffordableTier:
            return String(localized: "send_blocked_unaffordable_tier", defaultValue: "This speed exceeds your balance. Pick a slower one.")
        case .feeEstimateUnreliable:
            return String(localized: "send_blocked_fee_estimate_unreliable", defaultValue: "The fee estimate is unreliable right now. Onchain sending is paused.")
        }
    }

    /// The decision, checked in order of what the user can least do about.
    /// - Parameters:
    ///   - amountSats: the amount as entered, nil when empty or unparsable
    ///   - isAmountLocked: a payment request fixed the amount (no entry)
    ///   - minimumSendAmount: the destination's minimum, 0 for none
    ///   - availableSats: the balance this destination spends from
    ///   - feeState: what the fee row shows for this destination
    ///   - isOnchain: the destination spends Savings through the shadow estimator
    ///   - fastTierAtMainnetCeiling: the live fast rate equals the mainnet ceiling
    static func evaluate(
        amountSats: Int?,
        isAmountLocked: Bool,
        minimumSendAmount: Int,
        availableSats: Int,
        feeState: FeeDisplayState,
        isOnchain: Bool,
        fastTierAtMainnetCeiling: Bool
    ) -> SendBlocker? {
        if isOnchain && fastTierAtMainnetCeiling {
            return .feeEstimateUnreliable
        }
        if isAmountLocked {
            return nil
        }
        guard let amountSats, amountSats > 0 else {
            return .noAmount
        }
        if minimumSendAmount > 0, amountSats < minimumSendAmount {
            return .belowMinimum
        }
        if isOnchain {
            switch feeState {
            case .estimating:
                return .estimatingFee
            case .unaffordable:
                return .unaffordableTier
            case .value, .approximate, .unavailable:
                break
            }
        }
        let fee = feeState.displayedFee ?? 0
        if amountSats + fee > availableSats {
            return .exceedsAvailable
        }
        return nil
    }
}

/// Send-all for an onchain destination drains the shadow wallet, whose view
/// of the coins can differ from bark's (it finds coins on addresses bark has
/// not revealed, bark excludes coins the shadow wallet cannot see as
/// locked). The amount offered must fit the balance bark will actually
/// spend from, or the Send button is enabled for a send bark rejects.
enum OnchainSendAll {
    /// - Parameters:
    ///   - drainAmountSats: what the shadow wallet would send draining itself
    ///   - drainFeeSats: the fee of that drain
    ///   - barkSpendableSats: bark's spendable onchain balance
    /// - Returns: the amount to offer, or nil when nothing can be sent
    static func cappedAmount(drainAmountSats: Int, drainFeeSats: Int, barkSpendableSats: Int) -> Int? {
        let fitsBark = barkSpendableSats - drainFeeSats
        let amount = min(drainAmountSats, fitsBark)
        return amount > 0 ? amount : nil
    }
}
