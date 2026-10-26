//
//  ArkBalanceResponse.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import Foundation
import SwiftData

/// Pure API response struct for Ark balance data
///
/// This struct is used for decoding API responses and passing data between actors.
/// It's naturally Sendable and contains all the computed properties for convenience.
struct ArkBalanceResponse: Codable, Sendable {
    /// Sats that can be sent right now. Since bark 0.8.0 this excludes
    /// `needsRefreshSat`.
    let spendableSat: Int
    /// Sats in VTXOs that have expired or reached the server's maximum exit
    /// depth: still owned, still exitable or refreshable, but not sendable
    /// out-of-round until a refresh (bark 0.8.0 `Balance.needs_refresh`).
    let needsRefreshSat: Int
    let pendingLightningSendSat: Int
    /// Sats in HTLC VTXOs of an incoming Lightning payment whose preimage is
    /// revealed but which are not swapped for spendable VTXOs yet. bark has
    /// reported this since 0.7.1; the app mapped it only from bindings v0.26.0.
    let claimableLightningReceiveSat: Int
    /// Sats locked in a round that has started an attempt (bark 0.8.0: the
    /// locked inputs, no longer the requested outputs).
    let pendingInRoundSat: Int
    let pendingExitSat: Int
    let pendingBoardSat: Int
    /// Sats held by an out-of-round send that has not finalized (bark 0.8.0).
    let pendingArkoorSendSat: Int
    /// Sats held by an offboard whose transaction is not on the network yet
    /// (bark 0.8.0).
    let pendingOffboardSat: Int

    enum CodingKeys: String, CodingKey {
        case spendableSat = "spendable_sat"
        case needsRefreshSat = "needs_refresh_sat"
        case pendingLightningSendSat = "pending_lightning_send_sat"
        case claimableLightningReceiveSat = "claimable_lightning_receive_sat"
        case pendingInRoundSat = "pending_in_round_sat"
        case pendingExitSat = "pending_exit_sat"
        case pendingBoardSat = "pending_board_sat"
        case pendingArkoorSendSat = "pending_arkoor_send_sat"
        case pendingOffboardSat = "pending_offboard_sat"
    }
    
    // MARK: - Computed Properties (mirrored from ArkBalanceModel)
    
    /// Spendable balance in BTC
    var spendableBTC: Double {
        Double(spendableSat) / 100_000_000
    }
    
    var pendingLightningSendBTC: Double {
        Double(pendingLightningSendSat) / 100_000_000
    }
    
    var pendingInRoundBTC: Double {
        Double(pendingInRoundSat) / 100_000_000
    }
    
    var pendingExitBTC: Double {
        Double(pendingExitSat) / 100_000_000
    }
    
    var pendingBoardBTC: Double {
        Double(pendingBoardSat) / 100_000_000
    }
    
    /// Sats held by operations in progress — bark's `Balance::pending()`,
    /// field for field. Excludes `needsRefreshSat`, which nothing holds.
    var totalPendingSat: Int {
        pendingLightningSendSat + claimableLightningReceiveSat + pendingInRoundSat
            + pendingExitSat + pendingBoardSat + pendingArkoorSendSat + pendingOffboardSat
    }

    var totalPendingBTC: Double {
        Double(totalPendingSat) / 100_000_000
    }

    /// Everything the user owns but cannot send right now: pending plus
    /// needs-refresh. The balance card shows this as its "Pending" figure
    /// (DECIDED 2026-10-25, `Docs/Migrations/Bark-0.25.0-to-0.26.0/`), so
    /// `spendableSat + heldSat == totalSat` holds on screen.
    var heldSat: Int {
        needsRefreshSat + totalPendingSat
    }

    /// All sats that belong to the wallet — bark's `Balance::total()`:
    /// spendable + needs-refresh + pending.
    var totalSat: Int {
        spendableSat + needsRefreshSat + totalPendingSat
    }
    
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
}
