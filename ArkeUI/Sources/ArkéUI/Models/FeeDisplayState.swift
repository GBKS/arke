//
//  FeeDisplayState.swift
//  ArkéUI
//
//  What a fee row knows about the number it shows. A fee the wallet has
//  actually priced is a different thing from a placeholder the app worked
//  out from a size guess, and the row must never present one as the other.
//

import Foundation

public enum FeeDisplayState: Equatable, Sendable {
    /// Priced by the wallet for exactly these inputs
    case value(Int)
    /// A request is open; nothing trustworthy to show yet
    case estimating
    /// A size-based placeholder shown before (or instead of) a real price
    case approximate(Int)
    /// The wallet priced this tier and the amount plus its fee exceeds the balance
    case unaffordable
    /// No estimate possible, nothing to show
    case unavailable

    /// The number the row shows, exact or approximate; nil otherwise
    public var displayedFee: Int? {
        switch self {
        case .value(let fee), .approximate(let fee):
            return fee
        case .estimating, .unaffordable, .unavailable:
            return nil
        }
    }
}
