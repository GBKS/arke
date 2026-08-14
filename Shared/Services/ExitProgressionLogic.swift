//
//  ExitProgressionLogic.swift
//  Arke
//
//  Pure decision logic and the fund-moving claim sequence for unilateral
//  exit progression, extracted from ExitProgressionService so both are
//  unit-testable without a wallet. The service is the humble shell: it
//  fetches state, asks these types what to do, and performs the effects.
//

import Foundation
import Bark
import OSLog

// MARK: - Narrow wallet surface for the claim sequence

/// The wallet operations the claim sequence needs. BarkWalletProtocol
/// refines this, so the production wallet passes straight through; tests
/// implement just these five methods.
protocol ExitClaimWallet {
    func getOnchainAddress() async throws -> String
    func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction
    func extractTxFromPsbt(psbtBase64: String) throws -> String
    func broadcastTx(txHex: String) async throws -> String
    func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus]
}

// MARK: - Pure decisions

enum ExitProgressionLogic {

    /// The kind of work a progression pass would address.
    enum WorkKind: String {
        case pending
        case claimable
        case claimInProgress = "claim-in-progress"
    }

    /// Whether a progression pass is needed, and for what.
    ///
    /// bark's hasPendingExits() only counts Start/Processing/AwaitingDelta.
    /// An exit sitting at Claimable is NOT "pending" but must still be
    /// claimed (the bark daemon performs AwaitingDelta -> Claimable and
    /// never claims), and a broadcast claim (ClaimInProgress) is neither
    /// pending nor claimable but needs progressExits to be marked Claimed
    /// once the claim tx confirms. Dropping any of the three strands
    /// silently strands exits.
    static func requiredWork(
        hasPending: Bool,
        claimableCount: Int,
        hasClaimsInProgress: Bool
    ) -> WorkKind? {
        if hasPending { return .pending }
        if claimableCount > 0 { return .claimable }
        if hasClaimsInProgress { return .claimInProgress }
        return nil
    }

    /// One blocked-state bookkeeping change.
    enum BlockedUpdate: Equatable {
        case record(vtxoId: String, phase: ExitBlockedPhase, message: String)
        case clear(vtxoId: String, phase: ExitBlockedPhase)
    }

    /// Blocked updates from a progression pass: a per-VTXO error records
    /// progression-phase blockage, success clears it. Clearing is
    /// progression-phase only — claim-phase blockage survives progression
    /// success by design (see WalletManager.clearExitBlocked).
    static func progressionBlockedUpdates(statuses: [ExitProgressStatus]) -> [BlockedUpdate] {
        statuses.map { status in
            if let error = status.error {
                return .record(vtxoId: status.vtxoId, phase: .progression, message: error)
            } else {
                return .clear(vtxoId: status.vtxoId, phase: .progression)
            }
        }
    }

    /// Blocked updates from a claim attempt: the claim is one transaction
    /// draining all the given VTXOs, so its outcome applies to each.
    static func claimBlockedUpdates(claimedVtxoIds: [String], errorMessage: String?) -> [BlockedUpdate] {
        claimedVtxoIds.map { vtxoId in
            if let errorMessage {
                return .record(vtxoId: vtxoId, phase: .claim, message: errorMessage)
            } else {
                return .clear(vtxoId: vtxoId, phase: .claim)
            }
        }
    }
}

// MARK: - Launch sequence

/// The ordered steps of ExitProgressionService's launch pass, with every
/// effect injected. The ORDER is load-bearing
/// (Docs/Initialization/Launch_Sequence_Contract.md, rule 8):
/// - reattachActivities first, so updates from the initial check reach a
///   Live Activity that survived the previous process
/// - the initial progression check BEFORE recreateActivities: on a fresh
///   seed import bark replays already-completed exits through its state
///   machine, so they read as in-flight until the first pass settles
///   them — recreating earlier spawns a lock-screen activity for an exit
///   that finished long ago (2026-08-13)
/// - rescheduleReminders last, for the same reason: re-arming before the
///   pass arms check-in reminders for replayed, already-finished exits
enum LaunchSequence {

    struct Effects {
        /// Reattach to a surviving Live Activity (never recreates)
        let reattachActivities: @MainActor () async -> Void
        /// The initial checkAndProgressExits pass
        let runInitialCheck: @MainActor () async -> Void
        /// Recreate a missing Live Activity for genuinely in-flight exits
        let recreateActivities: @MainActor () async -> Void
        /// Re-arm or clear check-in reminders from in-flight state
        let rescheduleReminders: @MainActor () async -> Void
    }

    static func run(effects: Effects) async {
        await effects.reattachActivities()
        await effects.runInitialCheck()
        await effects.recreateActivities()
        await effects.rescheduleReminders()
    }
}

// MARK: - Claim sequence

/// The ordered, fund-moving steps of claiming exits, with the two
/// persistence effects injected. The ORDER is load-bearing:
/// - recordClaim runs right after broadcast, while the drained VTXO ids
///   are known — it persists the fee and links the claim tx to its exit
///   movements; bark purges claimed exits from its list soon after, so
///   the status-cache relink can miss the claim entirely
/// - snapshotStatuses runs after progressExits so it captures
///   ClaimInProgress (carrying the claim txid), the last reliable state
///   before the purge
enum ExitClaimSequence {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitClaim")

    struct Effects {
        /// Persist the claim fee and link the claim tx to its movements
        /// (claim txid, fee sats, drained VTXO ids)
        let recordClaim: (String, UInt64, [String]) -> Void
        /// Snapshot the exits' statuses to persistent storage (VTXO ids)
        let snapshotStatuses: ([String]) async -> Void
    }

    /// Runs the claim and returns the broadcast claim txid.
    @discardableResult
    static func run(
        claimableVtxoIds: [String],
        wallet: ExitClaimWallet,
        feeRateSatPerVb: UInt64?,
        effects: Effects
    ) async throws -> String {
        let address = try await wallet.getOnchainAddress()

        let claimTx = try await wallet.drainExits(
            vtxoIds: claimableVtxoIds,
            address: address,
            feeRateSatPerVb: feeRateSatPerVb
        )
        Self.logger.notice("✅ Claim transaction created (Fee: \(claimTx.feeSats) sats)")

        let txHex = try wallet.extractTxFromPsbt(psbtBase64: claimTx.psbtBase64)
        let txid = try await wallet.broadcastTx(txHex: txHex)
        Self.logger.notice("✅ Claim transaction broadcast! TXID: \(txid)")

        effects.recordClaim(txid, claimTx.feeSats, claimableVtxoIds)

        // Progress exits to sync state (updates to ClaimInProgress)
        _ = try await wallet.progressExits(feeRateSatPerVb: feeRateSatPerVb)

        await effects.snapshotStatuses(claimableVtxoIds)

        return txid
    }
}
