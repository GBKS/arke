//
//  FeeTierGroup.swift
//  ArkéUI
//
//  Tiers that share a rate are one choice, not three. On a quiet mainnet
//  mempool the 1-, 3- and 6-block estimates are all 1 sat/vB, and on signet
//  the sanity cap flattens them; three rows with three durations would
//  then promise differences that do not exist. A group is named and timed
//  by its fastest member, because that rate meets the shortest target in
//  the group. (DECIDED 2026-10-27.)
//

import Foundation

public struct FeeTierGroup: Equatable, Sendable, Identifiable {
    /// The fastest tier in the group; its name and duration label the row
    public let representative: FeePriority
    /// Every tier priced at this rate, fastest first
    public let members: [FeePriority]
    public let rateSatPerVb: UInt64

    public var id: FeePriority { representative }

    public func contains(_ priority: FeePriority) -> Bool {
        members.contains(priority)
    }

    /// Groups the tiers by equal rate, fastest first. `OnchainFeeRates` is
    /// already clamped fast ≥ medium ≥ slow, so equal rates are always
    /// adjacent; a non-monotonic input still groups correctly, by value.
    public static func groups(from rates: OnchainFeeRates) -> [FeeTierGroup] {
        var groups: [FeeTierGroup] = []
        for priority in FeePriority.allCases {
            let rate = rates.rate(for: priority)
            if let index = groups.firstIndex(where: { $0.rateSatPerVb == rate }) {
                let existing = groups[index]
                groups[index] = FeeTierGroup(
                    representative: existing.representative,
                    members: existing.members + [priority],
                    rateSatPerVb: rate
                )
            } else {
                groups.append(FeeTierGroup(representative: priority, members: [priority], rateSatPerVb: rate))
            }
        }
        return groups
    }

    /// The group a tier belongs to under these rates
    public static func group(containing priority: FeePriority, in rates: OnchainFeeRates) -> FeeTierGroup? {
        groups(from: rates).first { $0.contains(priority) }
    }
}
