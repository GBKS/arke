//
//  ExitProgressionService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 2/5/26.
//

import Foundation
import SwiftUI
import Bark
import ArkeUI
import OSLog

/// Service responsible for automatically progressing unilateral exits in the background
///
/// This service runs a timer that periodically checks for active exits and progresses them
/// through their state machine. The Bark SDK handles all the complex exit logic - this
/// service just polls it regularly and triggers progression.
///
/// Exit Flow (Fully Automatic):
/// 1. User starts exit → SDK creates exit transactions (fee pre-approved)
/// 2. Service auto-progresses: Start → Processing → AwaitingDelta → Claimable (automatic)
/// 3. Service auto-claims: Claimable → ClaimInProgress → Claimed (automatic)
/// 4. Exit complete - funds moved to onchain wallet
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every 5 minutes (configurable)
/// - SDK-driven: No complex state tracking, just polls SDK
/// - Silent failures: Logs errors but doesn't interrupt user
@MainActor
@Observable
class ExitProgressionService {

    // MARK: - Logging

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitProgression")

    // MARK: - Configuration

    /// How often to check for exit progression (in seconds)
    private let checkInterval: TimeInterval = 5 * 60 // 5 minutes

    // MARK: - State

    /// Whether the service is currently running
    private(set) var isRunning: Bool = false

    /// Last time exits were checked/progressed
    private(set) var lastCheckTime: Date?

    /// Last error encountered (for debugging)
    private(set) var lastError: String?

    // MARK: - Dependencies

    internal let wallet: BarkWalletProtocol
    internal weak var walletManager: WalletManager?

    // MARK: - Timer

    private var timer: Timer?

    // MARK: - Initialization

    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet

        // Listen for exit check-in notifications (iOS only)
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: .exitCheckInReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.userCheckedIn()
            }
        }
        #endif
    }

    /// Set the wallet manager reference (needed for cache invalidation)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }

    // MARK: - Lifecycle

    /// Start the exit progression service
    func start() {
        guard !isRunning else {
            Self.logger.warning("⚠️ Service already running")
            return
        }

        Self.logger.info("▶️ Starting service (check interval: \(Int(self.checkInterval))s)")
        isRunning = true

        // The launch pass. Its order is load-bearing and pinned by
        // LaunchSequence (see its doc comment and the launch sequence
        // contract); the activity/reminder steps are iOS-only no-ops
        // elsewhere.
        Task {
            await LaunchSequence.run(effects: LaunchSequence.Effects(
                reattachActivities: {
                    #if os(iOS)
                    await self.reattachToExistingActivities()
                    #endif
                },
                runInitialCheck: {
                    await self.checkAndProgressExits()
                },
                recreateActivities: {
                    #if os(iOS)
                    await self.recreateMissingActivities()
                    #endif
                },
                rescheduleReminders: {
                    #if os(iOS)
                    await self.rescheduleCheckInRemindersIfNeeded()
                    #endif
                }
            ))
        }

        // Schedule timer for periodic checks
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndProgressExits()
            }
        }
    }

    /// Stop the exit progression service
    func stop() {
        guard isRunning else { return }

        Self.logger.info("⏹️ Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            Self.logger.warning("⚠️ Cannot trigger check - service not running")
            return
        }

        Self.logger.info("🔄 Manual check triggered")
        Task {
            await checkAndProgressExits()
        }
    }

    // MARK: - Fee Rates

    /// Explicit fee rate override for exit operations.
    ///
    /// On mainnet this is nil: bark resolves rates internally from its chain
    /// source (fast tier for CPFP progression, regular for the claim), and
    /// second-guessing that risks underpaying a real exit. Off mainnet the
    /// same estimator gets poisoned by fee spam (signet estimates in the
    /// six-digit sat/vB range), which makes bark's CPFP funding fail — so
    /// pass the app-side rate, which FeeRateService sanity-caps on
    /// non-mainnet networks. Fast tier for everything: it matches what
    /// progression pays, and only overshoots the claim's regular tier.
    private func exitFeeRateOverride() async -> UInt64? {
        guard let walletManager, !walletManager.isMainnet else { return nil }
        return await walletManager.currentFeeRates().fast
    }

    // MARK: - Exit Progression Logic

    /// Check for active exits and progress them if needed.
    /// The decisions live in ExitProgressionLogic (unit-tested); this
    /// method fetches state and performs the effects.
    internal func checkAndProgressExits() async {
        let startTime = Date()
        Self.logger.debug("🔍 Starting check")

        do {
            // Step 1: Quick check - do we have any exits that need work?
            // Three separate probes because bark has no single "needs work"
            // query — see ExitProgressionLogic.requiredWork for why each
            // strand matters.
            let hasPending = try await wallet.hasPendingExits()
            var claimableExits = try await wallet.listClaimableExits()
            let hasClaimsInProgress = try await wallet.getExitVtxos().contains { $0.isClaimInProgress }

            guard let work = ExitProgressionLogic.requiredWork(
                hasPending: hasPending,
                claimableCount: claimableExits.count,
                hasClaimsInProgress: hasClaimsInProgress
            ) else {
                Self.logger.debug("✅ No pending, claimable, or claim-in-progress exits - skipping progression")

                // A Claimed exit is none of the above, so this early return
                // is the steady state right after an exit completes - still
                // sweep Live Activities here or finished exits keep their
                // activity on the lock screen forever (iOS only)
                #if os(iOS)
                await updateAllLiveActivities()
                #endif

                lastCheckTime = Date()
                lastError = nil
                return
            }

            Self.logger.info("📋 Found \(work.rawValue, privacy: .public) exits - progressing...")

            // Step 2: Progress all exits (broadcasts, fee bumps, state updates)
            let statuses = try await wallet.progressExits(feeRateSatPerVb: await exitFeeRateOverride())

            // Log what happened and track per-VTXO blocked state
            if statuses.isEmpty {
                Self.logger.debug("ℹ️ No exits progressed")
            } else {
                Self.logger.info("✅ Progressed \(statuses.count, privacy: .public) exit(s)")
                for (index, status) in statuses.enumerated() {
                    if let error = status.error {
                        Self.logger.warning("[\(index)] VTXO \(status.vtxoId): ❌ Error: \(error, privacy: .public)")
                    } else {
                        Self.logger.info("[\(index)] VTXO \(status.vtxoId): ✅ Success")
                    }
                }
                apply(ExitProgressionLogic.progressionBlockedUpdates(statuses: statuses))
            }

            // Step 3: Check for claimable exits and auto-claim them
            // Re-fetch after progression, which may have just made exits claimable
            claimableExits = try await wallet.listClaimableExits()

            if !claimableExits.isEmpty {
                Self.logger.notice("💰 Found \(claimableExits.count, privacy: .public) claimable exit(s) - auto-claiming...")
                let claimedVtxoIds = claimableExits.map { $0.vtxoId }
                do {
                    try await autoClaimExits(claimableExits)
                    apply(ExitProgressionLogic.claimBlockedUpdates(claimedVtxoIds: claimedVtxoIds, errorMessage: nil))
                } catch {
                    // A failed claim (e.g. fees currently exceeding the exit's
                    // value) must not abort the sync/cache steps below - record
                    // it per VTXO and retry on the next interval
                    Self.logger.error("❌ Auto-claim failed: \(error.localizedDescription, privacy: .public)")
                    apply(ExitProgressionLogic.claimBlockedUpdates(claimedVtxoIds: claimedVtxoIds, errorMessage: error.localizedDescription))
                }
            }

            // Step 4: Sync exit state with blockchain
            try await wallet.syncExits()
            Self.logger.debug("✅ Synced exit state")

            // Step 5: Invalidate cache to trigger UI updates
            walletManager?.invalidateExitCache()
            Self.logger.debug("✅ Invalidated exit cache")

            // Step 6: Update Live Activities (iOS only)
            #if os(iOS)
            await updateAllLiveActivities()
            #endif

            // Success
            lastCheckTime = Date()
            lastError = nil

            let duration = Date().timeIntervalSince(startTime)
            Self.logger.notice("✅ Check completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch {
            // Log error but don't stop the service
            let errorMessage = error.localizedDescription
            Self.logger.error("❌ Error during check: \(errorMessage, privacy: .public)")
            lastError = errorMessage
            lastCheckTime = Date()

            // Continue running despite errors - will retry on next interval
        }
    }

    /// Automatically claim exits that have become claimable.
    /// The fund-moving steps and their load-bearing order live in
    /// ExitClaimSequence (unit-tested); this wires in the wallet and the
    /// persistence effects.
    private func autoClaimExits(_ claimableExits: [ExitVtxo]) async throws {
        let claimableVtxoIds = claimableExits.map { $0.vtxoId }
        let totalAmount = claimableExits.reduce(0) { $0 + $1.amountSats }
        Self.logger.info("Creating claim transaction for \(claimableVtxoIds.count, privacy: .public) VTXO(s) (\(totalAmount) sats)...")

        try await ExitClaimSequence.run(
            claimableVtxoIds: claimableVtxoIds,
            wallet: wallet,
            feeRateSatPerVb: await exitFeeRateOverride(),
            effects: ExitClaimSequence.Effects(
                recordClaim: { [weak walletManager] txid, feeSats, vtxoIds in
                    // Persist the claim fee (bark is the only source for it;
                    // BDK sees the claim as a pure receive) and link the claim
                    // to its exit movement(s) while the drained VTXO ids are
                    // known — bark purges these exits from its list after claim
                    walletManager?.recordClaimFee(claimTxid: txid, feeSats: feeSats, drainedVtxoIds: vtxoIds)
                },
                snapshotStatuses: { [weak walletManager] vtxoIds in
                    // Now ClaimInProgress, carrying the claim txid — the last
                    // reliable state before the purge
                    await walletManager?.snapshotExitStatuses(vtxoIds: vtxoIds)
                }
            )
        )
    }

    /// Apply blocked-state bookkeeping decided by ExitProgressionLogic
    private func apply(_ updates: [ExitProgressionLogic.BlockedUpdate]) {
        for update in updates {
            switch update {
            case .record(let vtxoId, let phase, let message):
                walletManager?.recordExitBlocked(vtxoId: vtxoId, phase: phase, errorMessage: message)
            case .clear(let vtxoId, let phase):
                walletManager?.clearExitBlocked(vtxoId: vtxoId, phase: phase)
            }
        }
    }

    // MARK: - Manual Operations

    /// Manually progress exits (exposed for UI triggers)
    func progressExitsManually() async throws {
        Self.logger.info("🔄 Manual progression requested")

        // Same gate as checkAndProgressExits() — see
        // ExitProgressionLogic.requiredWork
        let hasPending = try await wallet.hasPendingExits()
        let claimableExits = try await wallet.listClaimableExits()
        let hasClaimsInProgress = try await wallet.getExitVtxos().contains { $0.isClaimInProgress }
        guard ExitProgressionLogic.requiredWork(
            hasPending: hasPending,
            claimableCount: claimableExits.count,
            hasClaimsInProgress: hasClaimsInProgress
        ) != nil else {
            Self.logger.info("ℹ️ No pending, claimable, or claim-in-progress exits to progress")
            return
        }

        let statuses = try await wallet.progressExits(feeRateSatPerVb: await exitFeeRateOverride())
        apply(ExitProgressionLogic.progressionBlockedUpdates(statuses: statuses))
        try await wallet.syncExits()
        walletManager?.invalidateExitCache()

        Self.logger.notice("✅ Manually progressed \(statuses.count, privacy: .public) exit(s)")
    }
}
