//
//  BalanceRefreshCardState.swift
//  Arke
//
//  The one decision behind the balance card's refresh row: which state to
//  show and whether to offer a CTA. Pure so it can be unit-tested without a
//  WalletManager (Refresh_Deduplication.md §10).
//

import Foundation

/// What the balance card's refresh row shows.
///
/// Precedence, highest first: a refresh in flight; a submittable set at or
/// above the floor (the only state with a CTA); VTXOs the server refused
/// while nothing can actually be scheduled (no candidates, or candidates
/// under the floor — bark lists dust alongside must-refresh VTXOs, so a
/// sub-floor sibling must not mask the refusal); a submittable set under
/// the floor on its own; the countdown to the free window; nothing to do.
nonisolated enum BalanceRefreshCardState: Equatable {
    /// A refresh is in flight.
    case refreshing
    /// `amountSats` can be refreshed now; the CTA is shown.
    case refreshNow(amountSats: Int)
    /// Every candidate was refused by the server within the back-off window
    /// (or is otherwise held back); nothing can be submitted from this device.
    /// Never "expired" or "lost": the app cannot tell a sweep from a divergence.
    case refused(amountSats: Int)
    /// Candidates exist but their total is under bark's dust floor, so a
    /// refresh would be refused before anything is written.
    case tooSmall(amountSats: Int, minimumSats: Int)
    /// Nothing to refresh yet; the free window opens in `blocks`.
    case countdown(blocks: Int)
    /// No VTXOs, or nothing that will ever need a refresh.
    case idle

    /// Whether the row offers the refresh action.
    var showsAction: Bool {
        if case .refreshNow = self { return true }
        return false
    }

    /// Resolve the state.
    ///
    /// - Parameters:
    ///   - hasActiveRefresh: a refresh movement is pending.
    ///   - candidateAmountSats: total of VTXOs the service would submit now
    ///     (after the exit, in-flight and back-off exclusions).
    ///   - candidateCount: how many such VTXOs.
    ///   - heldBackAmountSats: total of VTXOs the back-off holds.
    ///   - heldBackCount: how many such VTXOs.
    ///   - blocksUntilPpmFree: blocks until the next free window; nil when
    ///     unknown or when no VTXO is waiting.
    ///   - minimumSats: the dust floor.
    static func resolve(
        hasActiveRefresh: Bool,
        candidateAmountSats: Int,
        candidateCount: Int,
        heldBackAmountSats: Int,
        heldBackCount: Int,
        blocksUntilPpmFree: Int?,
        minimumSats: Int
    ) -> BalanceRefreshCardState {
        if hasActiveRefresh {
            return .refreshing
        }
        if candidateCount > 0 && candidateAmountSats >= minimumSats {
            return .refreshNow(amountSats: candidateAmountSats)
        }
        // Nothing can be scheduled from here on. If the server holds
        // anything back, that is the thing to say (adversarial pass
        // 2026-10-11, finding 1: a 200-sat dust sibling otherwise turned
        // 19,995 refused sats into "Too small to refresh").
        if heldBackCount > 0 {
            return .refused(amountSats: heldBackAmountSats)
        }
        if candidateCount > 0 {
            return .tooSmall(amountSats: candidateAmountSats, minimumSats: minimumSats)
        }
        if let blocks = blocksUntilPpmFree, blocks > 0 {
            return .countdown(blocks: blocks)
        }
        return .idle
    }
}
