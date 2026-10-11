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
    /// alternative is losing the VTXO to expiry.
    ///
    /// This mirrors bark's own `vtxo_refresh_expiry_threshold`, which we do
    /// **not** pin — `BarkWalletFFI+Configuration.swift` passes `nil` ("use
    /// defaults"), so the live value is bark's default and could move on a
    /// bindings bump. The authoritative runtime accessor is
    /// `ArkConfigModel.vtxoRefreshThresholdBlocks` (same 144 fallback), read
    /// back via `getConfig()`; `RefreshExclusionTests` pins the two together
    /// so a drift in either fails a test rather than silently narrowing the
    /// valve. Threading the live config value in here is the better fix and
    /// is listed in Open_Follow_Ups.
    static let hardExpiryThresholdBlocks = 144

    /// Smallest input total bark will build a refresh for: its `VTXO_DUST`
    /// (= `P2TR_DUST`, 330 sats), checked in `inner_build_refresh_participation`
    /// before any movement is written (read at `bark-0.7.1`), and enforced
    /// again by the server on the round output. Shared by the auto check,
    /// the manual path and the balance card so the CTA is driven by what the
    /// service would actually submit (Refresh_Deduplication.md §10). bark
    /// additionally requires total − fee ≥ dust, which is not pre-checked
    /// here; such a miss still fails cleanly before any write.
    static let minimumRefreshAmountSats: UInt64 = 330

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
            !isExcluded(
                id: vtxo.id,
                expiryHeight: Int(vtxo.expiryHeight),
                exitingIds: exitingIds,
                beingRefreshedIds: beingRefreshedIds,
                currentBlockHeight: currentBlockHeight
            )
        }
    }

    /// The same decision keyed on id and expiry height, so the balance card
    /// (which holds `VTXOModel`s) excludes exactly what the service excludes.
    /// Before this the card dropped every in-flight id unconditionally and a
    /// VTXO with a stale Pending entry vanished from the card instead of
    /// going through the valve (Refresh_Deduplication.md §10, D8).
    static func isExcluded(
        id: String,
        expiryHeight: Int,
        exitingIds: Set<String>,
        beingRefreshedIds: Set<String>,
        currentBlockHeight: Int?
    ) -> Bool {
        if exitingIds.contains(id) {
            return true
        }
        guard beingRefreshedIds.contains(id) else {
            return false
        }
        // Safety valve: inside the hard expiry threshold, refresh even
        // if an in-flight entry claims this VTXO.
        guard let height = currentBlockHeight else {
            return true
        }
        return expiryHeight - height > hardExpiryThresholdBlocks
    }
}
