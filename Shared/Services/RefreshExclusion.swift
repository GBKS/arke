//
//  RefreshExclusion.swift
//  Arke
//
//  Pure exclusion logic shared by the auto-refresh check and manual refresh.
//  Guard B: VTXOs with an in-progress unilateral exit (refreshing one spends
//  it and self-cancels the exit). Guard C: VTXOs already part of an in-flight
//  refresh (a duplicate delegated request makes the server drop the older
//  one, leaving orphaned local state — see Refresh_Deduplication.md).
//  Extracted as a pure function for unit testing.
//

import Foundation
import Bark

enum RefreshExclusion {

    /// Blocks-until-expiry at or below which the being-refreshed exclusion
    /// (Guard C) is ignored: a stuck pending refresh entry — a sync failure,
    /// or a server-replaced duplicate, which doesn't self-heal on our bark
    /// release — must never block a renewal this close to expiry. Worst case
    /// is a benign duplicate the server resolves by replacement; the
    /// alternative is losing the VTXO to expiry. Matches the app's
    /// `vtxoRefreshExpiryThreshold` (BarkWalletFFI+Configuration.swift).
    static let hardExpiryThresholdBlocks = 144

    /// Filter VTXOs that may be handed to a refresh call.
    ///
    /// - Parameters:
    ///   - vtxos: Candidate VTXOs (already spendable per the SDK).
    ///   - exitingIds: IDs with an in-progress unilateral exit (Guard B).
    ///   - beingRefreshedIds: IDs already part of an in-flight refresh
    ///     (Guard C) — pending refresh movement inputs ∪ issued pending
    ///     round inputs.
    ///   - currentBlockHeight: For the near-expiry safety valve. When nil,
    ///     the valve cannot be evaluated and Guard C excludes unconditionally
    ///     (exit exclusion is unaffected).
    static func filter(
        _ vtxos: [Vtxo],
        exitingIds: Set<String>,
        beingRefreshedIds: Set<String>,
        currentBlockHeight: Int?
    ) -> [Vtxo] {
        vtxos.filter { vtxo in
            if exitingIds.contains(vtxo.id) {
                return false
            }
            guard beingRefreshedIds.contains(vtxo.id) else {
                return true
            }
            // Safety valve: inside the hard expiry threshold, refresh even
            // if an in-flight entry claims this VTXO.
            guard let height = currentBlockHeight else {
                return false
            }
            return Int(vtxo.expiryHeight) - height <= hardExpiryThresholdBlocks
        }
    }
}
