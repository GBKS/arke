//
//  VTXORefreshService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 4/17/26.
//

import Foundation
import ArkeUI
import SwiftUI
import Bark
import OSLog
import UserNotifications

/// Outcome of a manual refresh request.
///
/// `refreshManually()` can legitimately do nothing — no candidates after the
/// exclusions, or a check already holding the gate. Callers need to tell that
/// apart from a real schedule, otherwise the UI reports success for a refresh
/// that never happened (see Refresh_Deduplication.md).
enum ManualRefreshOutcome {
    /// A delegated refresh was registered; the server will execute it.
    case scheduled(RoundState)
    /// The call reached bark but no round was created — nothing needed
    /// refreshing, or everything was excluded (mid-exit / already in flight).
    case nothingToDo
    /// A refresh check was already running. Its exclusions cover the same
    /// VTXOs, so this request was intentionally dropped rather than raced.
    case alreadyInProgress
    /// The server rejected the inputs as unusable *and* the post-error
    /// refetch shows them locked in an issued round (F5 race): the refresh
    /// the user asked for is running — we just didn't schedule it.
    /// Surfacing this as an error told users "Refresh Failed" for a refresh
    /// in flight (Refresh_Deduplication.md §2).
    case alreadyIssuedByServer
    /// The server rejected the inputs as unusable and none of them is in
    /// flight: it considers them spent, exited or banned, so this wallet's
    /// view of them is out of date (the 2026-10-09 divergence incident).
    /// Also returned when every candidate is already held back by the
    /// 24 h back-off. Honest failure, not "already refreshing"
    /// (Refresh_Deduplication.md §9).
    case rejectedByServer
    /// The submittable candidates total less than bark's dust floor
    /// (`RefreshExclusion.minimumRefreshAmountSats`); bark would refuse to
    /// build the refresh before writing anything, so the app says so
    /// instead of showing that error as "Refresh Failed" (§10).
    case belowMinimum(totalSats: UInt64)
}

/// Service responsible for automatically refreshing VTXOs when refreshes are free
///
/// This service monitors VTXOs and automatically triggers refreshes when refresh is 
/// completely free (0 sats) according to the server's fee schedule.
///
/// The service can refresh VTXOs at any stage of their lifecycle, including expired VTXOs,
/// as long as they haven't been spent, exited, or locked. This makes it especially valuable
/// for recovering VTXOs when users open the wallet after extended periods of inactivity.
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every hour (much less frequent than round progression)
/// - Fee-driven: Only refreshes when completely free according to fee schedule
/// - Transparent: Logs all automatic refreshes for user visibility
@MainActor
@Observable
class VTXORefreshService {
    
    /// Logger for VTXO refresh service operations
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "VTXORefresh")
    
    // MARK: - Configuration
    
    /// How often to check for VTXOs needing free refresh (in seconds)
    /// Set to 1 hour - VTXOs have long lifespans so frequent checks aren't needed
    private let checkInterval: TimeInterval = 3600 // 1 hour
    
    /// Maximum percentage of VTXO lifespan remaining to trigger auto-refresh
    /// Only auto-refresh VTXOs in their last 10% of life (e.g., last ~3 days for mainnet, last ~2.3 hours for signet)
    ///
    /// NOTE: This threshold exists to prevent continuous refresh loops when the server's fee schedule
    /// has a free refresh window that's longer than the VTXO lifespan (e.g., signet with 1-day VTXOs
    /// but a mainnet fee schedule that makes refreshes free in the last 2 days). This can be removed
    /// if server fee schedules are properly configured for each network's VTXO expiry delta.
    private let maxLifespanPercentForAutoRefresh: Double = 0.10 // 10%
    
    // MARK: - State
    
    /// Whether the service is currently running
    private(set) var isRunning: Bool = false
    
    /// Whether a check is currently in progress (prevents overlapping checks)
    private var isChecking: Bool = false
    
    /// Last time VTXOs were checked for auto-refresh
    private(set) var lastCheckTime: Date?
    
    /// Last time a VTXO was auto-refreshed
    private(set) var lastRefreshTime: Date?
    
    /// Count of VTXOs auto-refreshed in current session
    private(set) var autoRefreshCount: Int = 0
    
    /// Last error encountered (for debugging)
    private(set) var lastError: String?
    
    /// Scheduled notification date (for debugging/display)
    private(set) var scheduledNotificationDate: Date?
    
    /// Notification identifier for VTXO refresh reminders
    private let notificationIdentifier = "com.arke.vtxo.refresh.reminder"

    /// Inputs the server rejected as unusable, held back for 24 h so a
    /// wallet whose view has diverged from the server stops adding one
    /// Failed refresh row per launch (Refresh_Deduplication.md §9).
    /// Persisted device-locally; pruned to the spendable set on every check.
    private var rejectionBackoff: RefreshRejectionBackoff

    /// Among `vtxos`, the ids the back-off would hold back from a refresh
    /// call right now — the same per-id rule (`shouldSkip`, valve included)
    /// the two service paths apply, so the balance card's refused state
    /// and the service's behaviour cannot disagree (§10, D4).
    func heldBackVtxoIds(among vtxos: [VTXOModel], currentBlockHeight: Int?) -> Set<String> {
        let at = now()
        return Set(vtxos.filter {
            rejectionBackoff.shouldSkip(
                id: $0.id,
                expiryHeight: $0.expiryHeight,
                currentBlockHeight: currentBlockHeight,
                now: at
            )
        }.map(\.id))
    }

    // MARK: - Dependencies

    private let wallet: BarkWalletProtocol
    private weak var walletManager: WalletManager?
    private let defaults: UserDefaults
    private let now: () -> Date

    // MARK: - Timer

    private var timer: Timer?

    // MARK: - Initialization

    init(
        wallet: BarkWalletProtocol,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.wallet = wallet
        self.defaults = defaults
        self.now = now
        self.rejectionBackoff = RefreshRejectionBackoff.load(
            from: defaults,
            key: UserDefaults.refreshRejectedInputsKey
        )
    }

    private func persistRejectionBackoff() {
        // Deletion runs `stop()` (resetManagerState) before
        // `clearUserDefaults()` removes the key; a check still mid-await
        // must not write the old wallet's verdicts back afterwards.
        guard isRunning else { return }
        rejectionBackoff.save(to: defaults, key: UserDefaults.refreshRejectedInputsKey)
    }

    /// Tell the balance card the held-back set changed. Called after a
    /// verdict is recorded or pruned — *after*, because the post-error
    /// refetch has already bumped `transactionVersion` by then and the card
    /// reloaded against the old set (§10, D5).
    private func notifyRefreshStatusChanged() {
        walletManager?.refreshStatusVersion += 1
    }

    /// Resolve a `unusable_inputs` rejection after the post-error refetch,
    /// record a real rejection in the back-off, and say which it was.
    /// Shared by the auto and manual paths so they cannot drift.
    private func handleUnusableInputs(
        requested: [String],
        beingRefreshedBefore: Set<String>,
        error: Swift.Error
    ) async -> RefreshRejection.Verdict {
        let beingRefreshedAfter = await walletManager?.vtxoIdsBeingRefreshed() ?? []
        let message = error.localizedDescription
        let verdict = RefreshRejection.classify(
            requested: requested,
            beingRefreshedBefore: beingRefreshedBefore,
            beingRefreshedAfter: beingRefreshedAfter,
            serverMessage: message
        )
        switch verdict {
        case .inFlight(let ids):
            Self.logger.info("Server rejected \(requested.count) VTXO(s) as unusable; \(ids.count) entered an issued round since our check — treating as in-flight, not a failure")
        case .rejected(let ids, let precise):
            rejectionBackoff.record(ids: ids, precise: precise, at: now())
            persistRejectionBackoff()
            notifyRefreshStatusChanged()
            // One warning per attempt, server text public: VTXO ids are
            // pseudonymous and bark's own selection logger already prints
            // them; the reason is what support needs from a debug export.
            Self.logger.warning("Server rejected \(ids.count) of \(requested.count) VTXO(s) as unusable and none is in flight — holding them back for 24h (\(precise ? "ids from server" : "whole batch", privacy: .public)). Server said: \(message, privacy: .public)")
        }
        return verdict
    }
    
    /// Set the wallet manager reference (needed for data access)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }
    
    // MARK: - Lifecycle
    
    /// Start the VTXO auto-refresh service
    func start() {
        guard !isRunning else {
            Self.logger.warning("Service already running")
            return
        }
        
        Self.logger.info("Starting service (check interval: \(Int(self.checkInterval))s)")
        isRunning = true
        
        // Run initial check immediately
        Task {
            await checkAndRefreshVTXOs()
            // Schedule notification based on current VTXO state
            await scheduleNextRefreshNotification()
        }
        
        // Schedule timer for periodic checks with tolerance for battery optimization
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndRefreshVTXOs()
            }
        }
        timer?.tolerance = 60 // Allow 1 minute variance for battery optimization
    }
    
    /// Stop the VTXO auto-refresh service
    func stop() {
        guard isRunning else { return }
        
        Self.logger.info("Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            Self.logger.warning("Cannot trigger check - service not running")
            return
        }
        
        Self.logger.info("Manual check triggered")
        Task {
            await checkAndRefreshVTXOs()
        }
    }

    /// Re-run the check and recompute the reminder when the app returns to
    /// the foreground. The reminder is a fixed time interval derived from an
    /// assumed block rate, so it drifts against the real chain while the app
    /// is away; recomputing from a fresh block height on every foreground
    /// return keeps that drift bounded to one background stretch.
    func checkAndRescheduleAfterForeground() async {
        guard isRunning else { return }
        Self.logger.info("Foreground return — re-checking VTXOs and recomputing the refresh reminder")
        await checkAndRefreshVTXOs()
        await scheduleNextRefreshNotification()
    }
    
    // MARK: - Auto-Refresh Logic
    
    /// Check for VTXOs in the free refresh window and refresh them automatically
    private func checkAndRefreshVTXOs() async {
        // Prevent overlapping checks
        guard !isChecking else {
            Self.logger.debug("Check already in progress, skipping")
            return
        }
        
        isChecking = true
        defer { isChecking = false }
        
        let startTime = Date()
        Self.logger.debug("Starting check at \(startTime)")
        
        do {
            // Step 1: Get current data. The block height goes through the
            // async getter, which refetches once the 60s cache has expired —
            // the synchronous `estimatedBlockHeight` property returned nil
            // after that, so the hourly check skipped with "missing data"
            // whenever nothing else had fetched the height in the last minute.
            let fetchedBlockHeight = await walletManager?.getEstimatedBlockHeight() ?? nil
            guard let arkInfo = walletManager?.arkInfo,
                  let feeSchedule = arkInfo.feeSchedule,
                  let currentBlockHeight = fetchedBlockHeight else {
                let missingArkInfo = walletManager?.arkInfo == nil
                let missingFeeSchedule = walletManager?.arkInfo?.feeSchedule == nil
                let missingBlockHeight = fetchedBlockHeight == nil
                Self.logger.warning("Missing required data - arkInfo: \(missingArkInfo), feeSchedule: \(missingFeeSchedule), blockHeight: \(missingBlockHeight), skipping")
                lastCheckTime = Date()
                return
            }
            
            // Step 2: Get all VTXOs that could potentially be refreshed.
            // Two exclusions (see RefreshExclusion):
            // - Guard B: mid-exit VTXOs stay spendable since bark 0.11.3
            //   (MR #2117); refreshing one spends it and self-cancels the
            //   exit (Exit_Refresh_Coordination.md).
            // - Guard C: VTXOs already in an in-flight refresh — delegated
            //   inputs stay spendable until the server issues the round, so
            //   re-selecting them here would double-schedule
            //   (Refresh_Deduplication.md).
            let exitingIds = await exitingVtxoIds()
            let beingRefreshedIds = await walletManager?.vtxoIdsBeingRefreshed() ?? []
            let allSpendable = try await wallet.spendableVtxos()
            let guarded = RefreshExclusion.filter(
                allSpendable,
                exitingIds: exitingIds,
                beingRefreshedIds: beingRefreshedIds,
                currentBlockHeight: currentBlockHeight
            )

            if guarded.count < allSpendable.count {
                Self.logger.info("Excluded \(allSpendable.count - guarded.count) VTXO(s) from auto-refresh (in-progress exit or in-flight refresh)")
            }

            // Server rejections (§9): prune verdicts whose VTXO left the
            // spendable set or aged out, then hold back the rest.
            let beforePrune = rejectionBackoff
            rejectionBackoff.prune(keeping: Set(allSpendable.map(\.id)), now: now())
            if rejectionBackoff != beforePrune {
                persistRejectionBackoff()
                notifyRefreshStatusChanged()
            }
            let (vtxos, heldBack) = rejectionBackoff.filter(
                guarded,
                currentBlockHeight: currentBlockHeight,
                now: now()
            )
            if !heldBack.isEmpty {
                Self.logger.info("Holding back \(heldBack.count) VTXO(s) the server rejected as unusable within the last 24h")
            }

            if vtxos.isEmpty {
                Self.logger.debug("No spendable VTXOs - skipping")
                lastCheckTime = Date()
                return
            }
            
            // Step 3: Find VTXOs eligible for free refresh
            let eligibleVTXOs = findVTXOsForAutoRefresh(
                vtxos: vtxos,
                currentBlockHeight: currentBlockHeight,
                vtxoLifespan: arkInfo.vtxoExpiryDelta,
                feeSchedule: feeSchedule,
                network: arkInfo.network
            )
            
            if eligibleVTXOs.isEmpty {
                Self.logger.debug("No VTXOs eligible for auto-refresh")
                lastCheckTime = Date()
                lastError = nil
                return
            }
            
            Self.logger.info("Found \(eligibleVTXOs.count) VTXO(s) eligible for free refresh")
            for (index, vtxo) in eligibleVTXOs.enumerated() {
                let blocksUntilExpiry = Int(vtxo.expiryHeight) - currentBlockHeight
                let percentRemaining = Double(blocksUntilExpiry) / Double(arkInfo.vtxoExpiryDelta) * 100
                Self.logger.debug("[\(index + 1)] Amount: \(vtxo.amountSats) sats, Expiry: \(blocksUntilExpiry) blocks (\(String(format: "%.1f", percentRemaining))%)")
            }
            
            // Step 3.5: Validate total amount meets minimum threshold
            let totalAmount = eligibleVTXOs.reduce(0) { $0 + $1.amountSats }
            let minimumAmount = RefreshExclusion.minimumRefreshAmountSats
            if totalAmount < minimumAmount {
                Self.logger.debug("Total VTXO amount (\(totalAmount) sats) is below minimum (\(minimumAmount) sats) - skipping refresh")
                lastCheckTime = Date()
                lastError = nil
                return
            }
            
            // Step 4: Trigger the delegated refresh with VTXO IDs
            // Using delegated refresh so the app doesn't need to stay online until the round starts
            let vtxoIds = eligibleVTXOs.map { $0.id }
            Self.logger.info("Scheduling automatic delegated refresh for \(vtxoIds.count) VTXO(s)...")

            let roundState: RoundState?
            do {
                roundState = try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
            } catch {
                // Scoped to the scheduling call only: bark writes the Pending
                // refresh movement before server registration (F1), so a
                // throw here can leave a movement the app can't see. Steps
                // 1-3 can't have written anything, so their failures must not
                // trigger this refetch — an offline check would otherwise do
                // a full transaction refetch every hour.
                await walletManager?.refreshAfterVTXOChange()

                if isUnusableInputsRejection(error) {
                    switch await handleUnusableInputs(
                        requested: vtxoIds,
                        beingRefreshedBefore: beingRefreshedIds,
                        error: error
                    ) {
                    case .inFlight:
                        // Inputs already committed to a round (F5) — the
                        // refresh is running; this attempt was redundant.
                        lastCheckTime = Date()
                        lastError = nil
                    case .rejected(let ids, _):
                        // Real rejection, now in the back-off; logged once
                        // by the handler. Not thrown: the outer catch would
                        // log it a second time at error level.
                        lastCheckTime = Date()
                        lastError = "Server rejected \(ids.count) VTXO(s) as unusable; held back for 24h"
                    }
                    return
                }
                throw error
            }

            if let roundState = roundState {
                Self.logger.info("Delegated refresh scheduled, Round ID: \(roundState.id)")
            } else {
                Self.logger.info("No refresh scheduled (VTXOs may not need refresh yet)")
            }

            // Step 5: Refresh balances and transactions
            await walletManager?.refreshAfterVTXOChange()
            Self.logger.debug("Refreshed balances and transactions")
            
            // Step 6: Schedule notification for next refresh
            await scheduleNextRefreshNotification()
            
            // Success — count as a refresh only when one was actually scheduled
            lastCheckTime = Date()
            if roundState != nil {
                lastRefreshTime = Date()
                autoRefreshCount += 1
            }
            lastError = nil

            let duration = Date().timeIntervalSince(startTime)
            Self.logger.info("Auto-refresh completed in \(String(format: "%.2f", duration))s (total session count: \(self.autoRefreshCount))")
            
        } catch {
            // Log error but don't stop the service. No refetch here — the
            // scheduling call does its own (see step 4); everything else in
            // this method is read-only, so there are no writes to republish.
            let errorMessage = error.localizedDescription
            Self.logger.error("Error during check: \(errorMessage)")
            lastError = errorMessage
            lastCheckTime = Date()

            // Continue running despite errors - will retry on next interval
        }
    }

    /// Find VTXOs that should be auto-refreshed
    /// 
    /// Returns VTXOs where:
    /// 1. Refresh is completely free according to the fee schedule, AND
    /// 2. VTXO is in its last 10% of lifespan (signet only - prevents refresh loops)
    /// 
    /// The percentage constraint prevents continuous refresh loops when server fee schedules
    /// have free refresh windows longer than the VTXO lifespan (e.g., signet with 1-day VTXOs
    /// but mainnet fee schedule with 2-day free window).
    /// 
    /// - Parameters:
    ///   - vtxos: All spendable VTXOs (already filtered by SDK to exclude spent/exited/locked)
    ///   - currentBlockHeight: Current blockchain height
    ///   - vtxoLifespan: Total VTXO lifespan in blocks (for fee calculation)
    ///   - feeSchedule: Server fee schedule
    ///   - network: Network name (mainnet, signet, etc.)
    /// - Returns: VTXOs where refresh is free and VTXO is near expiry
    private func findVTXOsForAutoRefresh(
        vtxos: [Vtxo],
        currentBlockHeight: Int,
        vtxoLifespan: Int,
        feeSchedule: ArkeUI.FeeSchedule,
        network: String
    ) -> [Vtxo] {
        return vtxos.filter { vtxo in
            let blocksUntilExpiry = Int(vtxo.expiryHeight) - currentBlockHeight
            
            // Constraint 1: Refresh must be completely free (0 sats)
            guard feeSchedule.isFreeRefresh(blocksUntilExpiry: blocksUntilExpiry) else {
                return false
            }
            
            // Constraint 2: For signet only, VTXO must be in its last 10% of lifespan
            // This prevents refresh loops when the fee schedule's free window is longer than VTXO lifespan
            if network.lowercased() == "signet" {
                let percentOfLifeRemaining = Double(blocksUntilExpiry) / Double(vtxoLifespan)
                return percentOfLifeRemaining <= maxLifespanPercentForAutoRefresh
            }
            
            // For mainnet: If it's free, refresh it
            return true
        }
    }
    
    /// Calculate when the next VTXO will enter the free refresh window
    /// 
    /// This finds the block height when the first VTXO will become eligible for free refresh
    /// based on the fee schedule's ppm expiry table. For signet, applies the 10% lifespan
    /// constraint to prevent refresh loops caused by misconfigured fee schedules.
    /// 
    /// The fee schedule works with thresholds:
    /// - Table sorted ascending: [(0, ppm: 0), (288, ppm: 2000), ...]
    /// - When blocksUntilExpiry >= 288 → uses threshold 288 (NOT FREE)
    /// - When blocksUntilExpiry < 288 → uses threshold 0 (FREE if ppm: 0)
    /// - So free window is when blocksUntilExpiry < nextHigherThreshold
    /// 
    /// - Parameters:
    ///   - vtxos: All spendable VTXOs
    ///   - currentBlockHeight: Current blockchain height
    ///   - vtxoLifespan: Total VTXO lifespan in blocks
    ///   - feeSchedule: Server fee schedule
    ///   - network: Network name (mainnet, signet, etc.)
    /// - Returns: Block height when free refresh window opens, or nil if no free window exists
    private func calculateNextFreeRefreshHeight(
        vtxos: [Vtxo],
        currentBlockHeight: Int,
        vtxoLifespan: Int,
        feeSchedule: ArkeUI.FeeSchedule,
        network: String
    ) -> Int? {
        // Find the threshold where ppm is 0
        let sortedTable = feeSchedule.refresh.ppmExpiryTable
            .sorted { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }
        
        guard let freeEntryIndex = sortedTable.firstIndex(where: { $0.ppm == 0 }) else {
            Self.logger.debug("No free refresh window in fee schedule")
            return nil
        }
        
        let freeEntry = sortedTable[freeEntryIndex]
        
        // Find the next higher threshold (when it stops being free)
        // Free window is: freeEntry.threshold <= blocksUntilExpiry < nextThreshold
        let nextThreshold: Int
        if freeEntryIndex + 1 < sortedTable.count {
            nextThreshold = sortedTable[freeEntryIndex + 1].expiryBlocksThreshold
        } else {
            // No higher threshold, free window extends indefinitely upward
            // This shouldn't happen in practice, but handle it
            Self.logger.debug("Free refresh window has no upper bound")
            return nil
        }
        
        Self.logger.debug("Free refresh window: \(freeEntry.expiryBlocksThreshold) to \(nextThreshold - 1) blocks before expiry")
        
        // Find the earliest VTXO that will enter the free refresh window
        let nextHeights = vtxos.compactMap { vtxo -> Int? in
            let expiryHeight = Int(vtxo.expiryHeight)
            
            // VTXO enters free window when: blocksUntilExpiry < nextThreshold
            // Which happens when: (expiryHeight - currentHeight) < nextThreshold
            // Rearranging: currentHeight > expiryHeight - nextThreshold
            // So free window starts when currentHeight reaches: expiryHeight - (nextThreshold - 1)
            // (at that point, blocksUntilExpiry = nextThreshold - 1, which is < nextThreshold)
            let freeWindowStartHeight = expiryHeight - (nextThreshold - 1)
            
            // For signet: also apply the 10% lifespan constraint to prevent refresh loops
            // For mainnet: use the free window start directly
            if network.lowercased() == "signet" {
                let tenPercentBeforeExpiry = expiryHeight - Int(Double(vtxoLifespan) * maxLifespanPercentForAutoRefresh)
                // Use whichever comes later (more conservative)
                return max(freeWindowStartHeight, tenPercentBeforeExpiry)
            } else {
                return freeWindowStartHeight
            }
        }
        
        // Return the earliest height among all VTXOs (when the first one enters the window)
        guard let earliestHeight = nextHeights.min() else {
            Self.logger.debug("No VTXOs found for free refresh calculation")
            return nil
        }
        
        // Only return if it's in the future
        guard earliestHeight > currentBlockHeight else {
            Self.logger.debug("Free refresh window already open (height \(earliestHeight) <= current \(currentBlockHeight))")
            return nil
        }
        
        return earliestHeight
    }
    
    // MARK: - Manual Refresh (for UI triggers)
    
    /// Manually refresh VTXOs (exposed for UI triggers)
    /// This bypasses the auto-refresh logic and always refreshes all VTXOs that need it
    /// Uses delegated refresh so the app doesn't need to stay online until the round starts
    ///
    /// - Returns: What actually happened, so the caller can avoid reporting
    ///   success for a no-op (`ManualRefreshOutcome`).
    func refreshManually() async throws -> ManualRefreshOutcome {
        Self.logger.info("Manual refresh requested")

        // Same gate as the auto check: interleaving would let each path read
        // a pre-exclusion snapshot of the other's work. If a check is mid-run
        // it covers the same VTXOs, so skipping is safe.
        guard !isChecking else {
            Self.logger.info("Refresh check already in progress — manual request skipped")
            return .alreadyInProgress
        }
        isChecking = true
        defer { isChecking = false }

        // Get VTXOs that need refresh. Exclusions mirror the auto path
        // (see RefreshExclusion): mid-exit VTXOs (Guard B) and VTXOs already
        // in an in-flight refresh (Guard C, Refresh_Deduplication.md).
        let exitingIds = await exitingVtxoIds()
        let beingRefreshedIds = await walletManager?.vtxoIdsBeingRefreshed() ?? []
        let currentBlockHeight = walletManager?.estimatedBlockHeight
        let guarded = RefreshExclusion.filter(
            try await wallet.getVtxosToRefresh(),
            exitingIds: exitingIds,
            beingRefreshedIds: beingRefreshedIds,
            currentBlockHeight: currentBlockHeight
        )

        // Server rejections (§9). No prune here: the candidate list is
        // "needs refresh", not the spendable set the verdicts are keyed to;
        // the auto check prunes on every launch.
        let (vtxos, heldBack) = rejectionBackoff.filter(
            guarded,
            currentBlockHeight: currentBlockHeight,
            now: now()
        )

        guard !vtxos.isEmpty else {
            if !heldBack.isEmpty {
                Self.logger.info("Manual refresh: all \(heldBack.count) candidate(s) were rejected by the server within the last 24h — not re-submitting")
                return .rejectedByServer
            }
            Self.logger.debug("No VTXOs need refreshing")
            return .nothingToDo
        }

        // Same floor as the auto path (§10, D1–D3): bark refuses to build a
        // refresh under its dust floor before writing anything, so say so
        // rather than surfacing that as "Refresh Failed".
        let totalAmount = vtxos.reduce(UInt64(0)) { $0 + $1.amountSats }
        if totalAmount < RefreshExclusion.minimumRefreshAmountSats {
            Self.logger.info("Manual refresh: candidate total \(totalAmount) sats is below the \(RefreshExclusion.minimumRefreshAmountSats)-sat floor — not submitting")
            return .belowMinimum(totalSats: totalAmount)
        }

        let vtxoIds = vtxos.map { $0.id }

        let roundState: RoundState?
        do {
            roundState = try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
        } catch {
            // bark writes the Pending refresh movement *before* server
            // registration (F1), so a throw can leave a movement behind.
            // Refetch before propagating or the app stays blind to it — and
            // a blind app re-offers "Refresh now" for VTXOs that already
            // have a lingering Pending entry (F5/F9 → stranded round state).
            await walletManager?.refreshAfterVTXOChange()

            if isUnusableInputsRejection(error) {
                switch await handleUnusableInputs(
                    requested: vtxoIds,
                    beingRefreshedBefore: beingRefreshedIds,
                    error: error
                ) {
                case .inFlight:
                    return .alreadyIssuedByServer
                case .rejected:
                    return .rejectedByServer
                }
            }
            throw error
        }

        // Refetch on both no-op and success — the exclusions are derived from
        // transaction state, so the next read must see whatever this wrote.
        await walletManager?.refreshAfterVTXOChange()

        guard let roundState else {
            Self.logger.info("No refresh scheduled for \(vtxoIds.count) VTXO(s)")
            return .nothingToDo
        }

        Self.logger.info("Manual delegated refresh scheduled for \(vtxoIds.count) VTXO(s), Round ID: \(roundState.id)")
        return .scheduled(roundState)
    }
    
    /// IDs of VTXOs currently in the unilateral exit process (any state).
    ///
    /// On error this returns an empty set and the refresh proceeds unfiltered:
    /// a missed exclusion only risks the benign self-cancel race (funds stay
    /// safe), whereas skipping the refresh entirely could miss a near-expiry
    /// renewal, which risks actual fund loss.
    private func exitingVtxoIds() async -> Set<String> {
        do {
            return Set(try await wallet.getExitVtxos().map { $0.vtxoId })
        } catch {
            Self.logger.warning("Could not fetch exit VTXOs for refresh exclusion: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Notification Scheduling
    
    /// Schedule a local notification to remind user to refresh VTXOs
    /// Called after any operation that changes the VTXO set (send/receive/refresh)
    func scheduleNextRefreshNotification() async {
        do {
            // Cancel any existing scheduled notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            scheduledNotificationDate = nil
            
            // Get required data (async height getter: refetches when the
            // cache has expired, see checkAndRefreshVTXOs)
            guard let currentHeight = await walletManager?.getEstimatedBlockHeight() ?? nil,
                  let arkInfo = walletManager?.arkInfo,
                  let feeSchedule = arkInfo.feeSchedule else {
                Self.logger.debug("Cannot schedule notification - missing data")
                return
            }
            
            // Get all spendable VTXOs to find the next one needing refresh
            let vtxos = try await wallet.spendableVtxos()
            guard !vtxos.isEmpty else {
                Self.logger.debug("No spendable VTXOs - not scheduling notification")
                return
            }
            
            // Find the VTXO that will enter the free refresh window first
            guard let nextFreeRefreshHeight = calculateNextFreeRefreshHeight(
                vtxos: vtxos,
                currentBlockHeight: currentHeight,
                vtxoLifespan: arkInfo.vtxoExpiryDelta,
                feeSchedule: feeSchedule,
                network: arkInfo.network
            ) else {
                Self.logger.debug("No free refresh window found - not scheduling notification")
                return
            }
            
            // Calculate blocks until free refresh window
            let blocksUntilRefresh = nextFreeRefreshHeight - currentHeight
            
            Self.logger.debug("Blocks until free refresh: \(blocksUntilRefresh), current: \(currentHeight), target: \(nextFreeRefreshHeight)")
            
            // Don't schedule if already in the window or very soon (< 10 blocks, ~1.5 hours)
            guard blocksUntilRefresh > 10 else {
                Self.logger.debug("Free refresh window starts very soon (\(blocksUntilRefresh) blocks), not scheduling notification")
                return
            }
            
            // Convert to time. Bitcoin signet targets the same ~10-minute
            // block interval as mainnet (measured ~10.8 min/block on
            // 2026-09-26/27); the previous 150s/block assumption fired the
            // reminder ~4x early and, because the app reschedules on every
            // launch, kept firing it. Same constant the expiry UI uses.
            let secondsPerBlock = BlockTimeFormatter.secondsPerBlock
            let secondsUntilRefresh = blocksUntilRefresh * secondsPerBlock
            
            Self.logger.debug("Network: '\(arkInfo.network)', secondsPerBlock: \(secondsPerBlock), secondsUntilRefresh: \(secondsUntilRefresh)")
            
            // Notify when the free refresh window opens
            let notificationDate = Date().addingTimeInterval(TimeInterval(secondsUntilRefresh))
            
            Self.logger.info("Scheduling refresh notification for \(notificationDate) (\(secondsUntilRefresh)s from now, block \(nextFreeRefreshHeight))")
            
            // Check notification authorization; prompt only while undetermined —
            // a denied status is respected without re-requesting every cycle.
            let center = UNUserNotificationCenter.current()
            var authStatus = await center.notificationSettings().authorizationStatus
            if authStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authStatus = await center.notificationSettings().authorizationStatus
            }
            guard authStatus == .authorized || authStatus == .provisional else {
                Self.logger.warning("Notifications not authorized (status: \(authStatus.rawValue)) — reminder not scheduled")
                return
            }
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification_vtxo_refresh_title", defaultValue: "Time to Refresh")
            content.body = String(localized: "notification_vtxo_refresh_body", defaultValue: "Your wallet needs maintenance to keep your funds fresh. Open the app to refresh.")
            content.sound = .default
            content.categoryIdentifier = "VTXO_REFRESH"
            
            // Schedule notification
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secondsUntilRefresh), repeats: false)
            let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
            
            try await center.add(request)
            scheduledNotificationDate = notificationDate
            
            Self.logger.info("Successfully scheduled notification for \(notificationDate)")
            
        } catch {
            Self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
        }
    }
    
    /// Cancel any pending refresh notifications
    func cancelScheduledNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        scheduledNotificationDate = nil
        Self.logger.debug("Cancelled scheduled notification")
    }
    
    // MARK: - Debug Info
    
    /// Get human-readable status for debugging/display
    var statusDescription: String {
        var parts: [String] = []
        
        parts.append("Running: \(isRunning)")
        
        if let lastCheck = lastCheckTime {
            let elapsed = Date().timeIntervalSince(lastCheck)
            parts.append("Last check: \(String(format: "%.0f", elapsed))s ago")
        } else {
            parts.append("Last check: Never")
        }
        
        if let lastRefresh = lastRefreshTime {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            parts.append("Last refresh: \(String(format: "%.0f", elapsed))s ago")
        }
        
        parts.append("Session refreshes: \(autoRefreshCount)")
        
        if let error = lastError {
            parts.append("Last error: \(error)")
        }
        
        return parts.joined(separator: " | ")
    }
}
