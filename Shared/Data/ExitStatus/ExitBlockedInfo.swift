//
//  ExitBlockedInfo.swift
//  Arke
//
//  Classification of exit progression/claim failures that indicate an exit
//  is temporarily blocked because fees can't be covered right now.
//  See Docs/Features/Exit_Blocked_State.md for the full design.
//
//  Created by Christoph on 7/14/26.
//

import Foundation

/// Why an exit can't currently move forward.
enum ExitBlockedReason: String, Codable {
    /// CPFP fee-bumping during exit processing needs more confirmed onchain
    /// funds. User-actionable: adding onchain funds lets the exit continue.
    case insufficientOnchainFunds
    
    /// The claim transaction fee (paid from the exit output itself) currently
    /// exceeds the exit's value. Not user-actionable; resolves when network
    /// fees drop. Progression keeps retrying automatically.
    case claimFeeExceedsOutput
    
    /// Any other progression/claim error; the raw message is preserved in
    /// ExitBlockedInfo for the technical details view.
    case other
}

extension ExitBlockedReason {
    /// Markers from bark's ExitError display strings (bark/src/exit/models/error.rs).
    /// Errors cross the FFI as strings and may arrive wrapped in additional
    /// layers (e.g. "Configuration error: Failed to drain exits: Bark.Error.Inner(
    /// message: \"Drain exits failed: Claim Fee Exceeds Output: ...\")"),
    /// so classification matches markers anywhere in the message.
    private static let insufficientFundsMarker = "Insufficient Confirmed Funds"
    private static let claimFeeMarker = "Claim Fee Exceeds Output"
    
    static func classify(_ errorMessage: String) -> ExitBlockedReason {
        if errorMessage.contains(Self.insufficientFundsMarker) {
            return .insufficientOnchainFunds
        }
        if errorMessage.contains(Self.claimFeeMarker) {
            return .claimFeeExceedsOutput
        }
        return .other
    }
}

/// Which step of the exit lifecycle reported the failure. A successful
/// progression must only clear progression-phase blockage: in the common
/// fee-spike case progression succeeds (the exit sits at Claimable) while
/// the claim keeps failing, and clearing indiscriminately would reset the
/// debounce count on every check.
enum ExitBlockedPhase: String, Codable {
    case progression
    case claim
}

/// Record of failed progression/claim attempts for one exit VTXO.
/// Cleared as soon as an attempt for that VTXO's phase succeeds.
struct ExitBlockedInfo: Codable, Equatable {
    let reason: ExitBlockedReason
    let phase: ExitBlockedPhase

    /// Verbatim error message, for the technical details view only.
    /// Never shown as primary UI (developer English, not localized).
    let rawErrorMessage: String
    
    let firstSeenAt: Date
    var lastSeenAt: Date
    
    /// Consecutive failed attempts with the same reason and phase. UI surfaces
    /// the blocked state at 2+ to avoid flapping on a single bad fee estimate.
    var attemptCount: Int
    
    /// Whether the blocked state should be shown to the user yet.
    var isSurfaceable: Bool {
        attemptCount >= 2
    }
}
