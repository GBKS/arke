//
//  DeletionForfeitWarning.swift
//  Arke
//
//  The one decision behind the Delete wallet screen's funds warning: whether
//  there is a Payments balance that expiry will forfeit, how much, and how
//  soon. Pure so it can be unit-tested without a WalletManager.
//
//  Background (Open_Follow_Ups, Tier 0, 2026-08-13 case): a 10,000-sat VTXO
//  was swept at expiry six hours after the wallet was deleted, and the app
//  had shown a generic "you still have funds" note. The server sweeps at
//  chain tip >= expiry height (bark `watchman/policy.rs`,
//  `decide_action_expiry`, read 2026-10-13), and after a last-device deletion
//  nothing is left that could refresh in time. Deletion is never blocked on
//  this (DECIDED 2026-10-10: warn, don't block).
//

import Foundation
import ArkeUI

nonisolated enum DeletionForfeitWarning {

    /// What the warning box says.
    struct State: Equatable {
        enum Scope: Equatable {
            /// Last device: deletion removes the only agent that can refresh.
            case lastDevice
            /// Other devices keep the wallet; one of them has to refresh.
            case otherDevices
        }

        let scope: Scope
        /// Sum of the VTXOs expiry can still forfeit.
        let amountSat: Int
        /// Blocks until the earliest of those expiries. Nil when the height or
        /// the expiry is unknown, and also when the earliest expiry is already
        /// past: the app cannot tell whether the sweep has happened, so the
        /// copy drops the time rather than claiming one.
        let blocksUntilExpiry: Int?
    }

    /// The part of the VTXO list the decision needs. Separated so the view
    /// can substitute a synced balance when no bark handle is open
    /// (read-only secondaries).
    struct Summary: Equatable {
        let amountSat: Int
        let earliestExpiryHeight: Int?
    }

    /// Spent VTXOs are gone and exited ones have left the Ark tree for an
    /// onchain exit; neither is forfeited at expiry. Everything else still
    /// sits under an expiry: bark's unspent list is Spendable + Locked, and
    /// pending boards and round inputs arrive as `.locked` (bark 0.7.1
    /// `vtxo/state.rs`, read 2026-10-13); the spent/exited filter is defence
    /// for callers that pass a wider list. An expiry of 0 means unknown and is
    /// left out of the deadline but counted in the amount.
    static func summarize(_ vtxos: [VTXOModel]) -> Summary {
        let atRisk = vtxos.filter { $0.state != .spent && $0.state != .exited }
        return Summary(
            amountSat: atRisk.reduce(0) { $0 + $1.amountSat },
            earliestExpiryHeight: atRisk.map(\.expiryHeight).filter { $0 > 0 }.min()
        )
    }

    /// Nil when there is nothing to warn about.
    ///
    /// `overrideOffered` is the screen's "Delete from the account anyway…"
    /// condition (`WalletDataCleanupService.shouldOfferOverride`): the
    /// registry was unreadable or every blocker is a doubtful mirror entry.
    /// In both cases "open another device" may point at a device that does
    /// not exist, and the override itself wipes the seed account-wide, so
    /// the copy is the last-device one: recover from the phrase and refresh.
    static func resolve(
        strategy: DeletionStrategy,
        overrideOffered: Bool = false,
        summary: Summary,
        currentBlockHeight: Int?
    ) -> State? {
        guard summary.amountSat > 0 else { return nil }

        var blocksUntilExpiry: Int?
        if let expiry = summary.earliestExpiryHeight,
           let height = currentBlockHeight,
           expiry > height {
            blocksUntilExpiry = expiry - height
        }

        let scope: State.Scope
        switch strategy {
        case .promptForCloudData:
            scope = .lastDevice
        case .localOnly:
            scope = overrideOffered ? .lastDevice : .otherDevices
        }

        return State(scope: scope, amountSat: summary.amountSat, blocksUntilExpiry: blocksUntilExpiry)
    }
}
