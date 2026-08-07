//
//  WalletManager+Exits.swift
//  Arke
//
//  Created by Christoph on 4/20/26.
//
//  ExitStore owns all unilateral-exit state (live exits, statuses, blocked
//  records, persistence); WalletManager keeps its existing exit members as
//  a thin facade over the store so call sites stay unchanged.
//

import Foundation
import SwiftData
import Bark
import ArkeUI
import OSLog

// MARK: - Exit Store

/// Single owner of unilateral-exit state: the live exit list and statuses
/// from bark, the blocked-exit records, and the persistent cache that
/// preserves exit history after bark purges claimed exits.
///
/// The store outlives wallet sessions — the disk cache loads before the
/// wallet opens — so wallet access is injected via `WalletHooks` when the
/// wallet initializes.
@MainActor
@Observable
final class ExitStore {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitStore")

    // MARK: Wiring

    /// Wallet access, set by WalletManager when the wallet initializes
    struct WalletHooks {
        let fetchExitVtxos: () async throws -> [ExitVtxo]
        let fetchExitStatus: (_ vtxoId: String) async throws -> ExitTransactionStatus?
        let relinkMovements: () async -> Void
    }

    @ObservationIgnored var hooks: WalletHooks?
    @ObservationIgnored var modelContext: ModelContext?
    /// Fired on user-visible state changes; WalletManager bumps dataVersion
    @ObservationIgnored var onStateChange: (() -> Void)?

    // MARK: State

    /// Exits bark currently tracks. Claimed (complete) exits get purged
    /// from this list shortly after the claim (observed with bark 0.11 —
    /// we once assumed they stayed forever); cancelled ones
    /// (VtxoAlreadySpent) linger.
    private(set) var exitVtxos: [ExitVtxo] = []

    /// Full status per live VTXO, for transaction linking and detail views
    private(set) var exitStatuses: [String: ExitTransactionStatus] = [:]

    /// Exits currently blocked because fees can't be covered
    private(set) var blockedInfoByVtxoId: [String: ExitBlockedInfo] = [:]

    private(set) var lastRefreshedAt: Date?

    /// In-flight refresh, joined by concurrent refresh calls
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    // MARK: Derived views of the state

    /// Exits still in progress — excludes claimed and cancelled, so a
    /// lingering cancelled exit can't report as "in progress" indefinitely
    /// (blocking the settings exit action, inflating attention counts)
    var activeExits: [ExitVtxo] {
        exitVtxos.filter { $0.isInFlight }
    }

    /// Claimable exits ready to be claimed
    var exitsRequiringAction: [ExitVtxo] {
        activeExits.filter { $0.isClaimable }
    }

    /// Reset in-memory state, e.g. after wallet deletion. The persistent
    /// history is cleared separately (WalletDataCleanupService).
    func clear() {
        exitVtxos = []
        exitStatuses = [:]
        blockedInfoByVtxoId = [:]
        lastRefreshedAt = nil
        onStateChange?()
    }

    // MARK: Disk cache

    /// Load exit cache metadata from persistent storage.
    /// Called at app startup before wallet initialization: restores blocked
    /// state so the UI shows it immediately instead of waiting for two
    /// progression checks to re-debounce. ExitVtxo objects are not
    /// reconstructed (they require full data from bark).
    func loadFromDisk() async {
        guard let context = modelContext else {
            Self.logger.warning("[Exit Cache] Cannot load from disk - no model context")
            return
        }

        let descriptor = FetchDescriptor<PersistentExitCache>(
            sortBy: [SortDescriptor(\.lastRefreshedAt, order: .reverse)]
        )

        do {
            let persistedExits = try context.fetch(descriptor)

            guard !persistedExits.isEmpty else {
                Self.logger.info("[Exit Cache] No persistent cache found (first launch or after migration)")
                return
            }

            Self.logger.info("[Exit Cache] Found \(persistedExits.count) exit(s) in persistent storage")

            if let lastRefresh = persistedExits.first?.lastRefreshedAt {
                let ageSeconds = Date().timeIntervalSince(lastRefresh)
                Self.logger.debug("[Exit Cache] Cache age: \(String(format: "%.1f", ageSeconds))s")
                lastRefreshedAt = lastRefresh
            }

            var restoredBlockedCount = 0
            for entry in persistedExits where !entry.isClaimed {
                if let json = entry.blockedInfoJson,
                   let data = json.data(using: .utf8),
                   let info = try? JSONDecoder().decode(ExitBlockedInfo.self, from: data) {
                    blockedInfoByVtxoId[entry.vtxoId] = info
                    restoredBlockedCount += 1
                }
            }
            if restoredBlockedCount > 0 {
                Self.logger.info("[Exit Blocked] Restored \(restoredBlockedCount) blocked exit(s) from persistent storage")
                onStateChange?()
            }

        } catch {
            Self.logger.warning("[Exit Cache] Failed to load from disk: \(error)")
        }
    }

    /// Save exit cache to persistent storage.
    /// Merges into existing entries rather than wiping: bark purges claimed
    /// exits from its exit list, so entries that vanish from the list are
    /// the app's only remaining record of those exits and must be kept.
    private func saveToDisk() async {
        guard let context = modelContext else { return }

        do {
            let existingEntries = try context.fetch(FetchDescriptor<PersistentExitCache>())
            var entriesByVtxoId: [String: PersistentExitCache] = [:]
            for entry in existingEntries {
                entriesByVtxoId[entry.vtxoId] = entry
            }

            let now = Date()
            for exitVtxo in exitVtxos {
                var blockedInfoJson: String?
                if let blockedInfo = blockedInfoByVtxoId[exitVtxo.vtxoId],
                   let data = try? JSONEncoder().encode(blockedInfo) {
                    blockedInfoJson = String(data: data, encoding: .utf8)
                }

                // Keep an existing snapshot when this refresh has no status
                // for the VTXO
                let statusJson = exitStatuses[exitVtxo.vtxoId]
                    .flatMap { ExitStatusSnapshot.encodeJson(from: $0) }

                if let entry = entriesByVtxoId[exitVtxo.vtxoId] {
                    entry.amountSats = exitVtxo.amountSats
                    entry.isClaimed = exitVtxo.isClaimed
                    entry.isClaimable = exitVtxo.isClaimable
                    entry.stateDisplayName = exitVtxo.stateDisplayName
                    entry.blockedInfoJson = blockedInfoJson
                    if let statusJson {
                        entry.exitStatusJson = statusJson
                    }
                    entry.lastRefreshedAt = now
                } else {
                    context.insert(PersistentExitCache(
                        vtxoId: exitVtxo.vtxoId,
                        amountSats: exitVtxo.amountSats,
                        isClaimed: exitVtxo.isClaimed,
                        isClaimable: exitVtxo.isClaimable,
                        stateDisplayName: exitVtxo.stateDisplayName,
                        exitStatusJson: statusJson,
                        blockedInfoJson: blockedInfoJson,
                        cachedAt: now,
                        lastRefreshedAt: now
                    ))
                }
            }

            // Entries no longer in bark's list: the exit is over. Clear any
            // blocked info (a finished exit can't be blocked, and startup
            // restores blocked banners from these entries) and finalize ones
            // whose last known state shows the claim was underway — bark
            // usually purges before a refresh ever observes "Claimed".
            let liveVtxoIds = Set(exitVtxos.map { $0.vtxoId })
            for entry in existingEntries where !liveVtxoIds.contains(entry.vtxoId) {
                entry.blockedInfoJson = nil
                entry.isClaimable = false
                if !entry.isClaimed, let status = entry.snapshotStatus,
                   status.isClaimed || status.isClaimInProgress {
                    entry.isClaimed = true
                    entry.stateDisplayName = String(localized: "exit_state_complete", defaultValue: "Complete")
                }
            }

            let historicalCount = existingEntries.count(where: { !liveVtxoIds.contains($0.vtxoId) })
            try context.save()
            Self.logger.info("[Exit Cache] Saved \(self.exitVtxos.count) live exit(s), kept \(historicalCount) historical")

        } catch {
            Self.logger.warning("[Exit Cache] Failed to save to disk: \(error)")
        }
    }

    // MARK: Refresh

    /// Refresh from bark: exit list, per-VTXO statuses, disk cache, and
    /// movement re-linking — in that order, exactly once per refresh.
    /// Concurrent calls join the in-flight refresh instead of stacking.
    func refresh() async {
        if let task = refreshTask {
            await task.value
            return
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        guard let hooks else {
            Self.logger.warning("[Exit Cache] Cannot refresh - no wallet hooks")
            return
        }

        Self.logger.debug("[Exit Cache] Refreshing exit cache...")

        do {
            exitVtxos = try await hooks.fetchExitVtxos()
        } catch {
            Self.logger.warning("[Exit Cache] Refresh failed: \(error)")
            return
        }
        lastRefreshedAt = Date()
        Self.logger.info("[Exit Cache] Fetched \(self.exitVtxos.count) exit VTXO(s)")

        // Prune blocked records for exits that are terminal (claimed or
        // cancelled) or no longer exist — a cancelled exit can't progress,
        // so its blocked banner is stale
        let activeVtxoIds = Set(exitVtxos.filter { $0.isInFlight }.map { $0.vtxoId })
        let staleBlockedIds = blockedInfoByVtxoId.keys.filter { !activeVtxoIds.contains($0) }
        if !staleBlockedIds.isEmpty {
            for vtxoId in staleBlockedIds {
                blockedInfoByVtxoId.removeValue(forKey: vtxoId)
            }
            Self.logger.info("[Exit Blocked] Pruned \(staleBlockedIds.count) stale blocked record(s)")
            onStateChange?()
        }

        // Fetch and cache exit statuses for all exits still in bark's list
        // (relinkExitMovements reads this cache to link exit/CPFP
        // transactions). Claimed exits get purged from the list, so their
        // claim tx is linked at drain time instead (recordClaimFee) and
        // their last status survives via the persisted snapshot.
        var newExitStatuses: [String: ExitTransactionStatus] = [:]
        var totalTxids = 0

        for exitVtxo in exitVtxos {
            if let status = try? await hooks.fetchExitStatus(exitVtxo.vtxoId) {
                newExitStatuses[exitVtxo.vtxoId] = status

                let txids = ExitStatusParser.extractAllTransactionIds(from: status)
                if !txids.isEmpty {
                    Self.logger.debug("[Exit Cache] VTXO \(exitVtxo.vtxoId.prefix(16))... has \(txids.count) txid(s)")
                    totalTxids += txids.count
                }
            }
        }
        exitStatuses = newExitStatuses

        // Save to persistent storage for next app launch — after the status
        // fetch, so each entry's snapshot reflects this refresh
        await saveToDisk()

        Self.logger.info("[Exit Cache] Cached \(newExitStatuses.count) exit status(es) with \(totalTxids) total txid(s)")

        Self.logger.debug("[Exit Cache] Triggering exit transaction re-linking...")
        await hooks.relinkMovements()
    }

    // MARK: Statuses

    /// Cached status from the last refresh; nil once bark purges the exit
    func cachedStatus(for vtxoId: String) -> ExitTransactionStatus? {
        exitStatuses[vtxoId]
    }

    /// Last persisted status snapshot for a VTXO — the only source once
    /// bark has purged the completed exit
    func persistedStatus(for vtxoId: String) -> ExitTransactionStatus? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<PersistentExitCache>(
            predicate: #Predicate { $0.vtxoId == vtxoId }
        )
        return (try? context.fetch(descriptor).first)?.snapshotStatus
    }

    /// Snapshot current exit statuses for the given VTXOs into persistent
    /// storage (and the in-memory status cache). Called right after a claim
    /// is broadcast: bark purges claimed exits from its exit list shortly
    /// after, and this is the last reliable chance to capture their history.
    func snapshotStatuses(vtxoIds: [String]) async {
        guard let context = modelContext, let hooks else { return }

        for vtxoId in vtxoIds {
            guard let status = try? await hooks.fetchExitStatus(vtxoId) else {
                Self.logger.warning("[Exit Cache] No status to snapshot for VTXO \(vtxoId.prefix(16))...")
                continue
            }

            exitStatuses[vtxoId] = status

            guard let statusJson = ExitStatusSnapshot.encodeJson(from: status) else { continue }
            let descriptor = FetchDescriptor<PersistentExitCache>(
                predicate: #Predicate { $0.vtxoId == vtxoId }
            )
            do {
                if let entry = try context.fetch(descriptor).first {
                    entry.exitStatusJson = statusJson
                    entry.lastRefreshedAt = Date()
                } else {
                    let amount = exitVtxos.first { $0.vtxoId == vtxoId }?.amountSats ?? 0
                    context.insert(PersistentExitCache(
                        vtxoId: vtxoId,
                        amountSats: amount,
                        isClaimed: false,
                        isClaimable: false,
                        stateDisplayName: String(localized: "exit_state_claim_in_progress", defaultValue: "Claiming"),
                        exitStatusJson: statusJson
                    ))
                }
                try context.save()
                Self.logger.info("[Exit Cache] Snapshotted status for VTXO \(vtxoId.prefix(16))...")
            } catch {
                Self.logger.warning("[Exit Cache] Failed to snapshot status: \(error)")
            }
        }
    }

    // MARK: Blocked exits

    /// Record a failed progression/claim attempt for a VTXO
    func recordBlocked(vtxoId: String, phase: ExitBlockedPhase, errorMessage: String) {
        let reason = ExitBlockedReason.classify(errorMessage)
        let now = Date()

        if let existing = blockedInfoByVtxoId[vtxoId],
           existing.reason == reason, existing.phase == phase {
            blockedInfoByVtxoId[vtxoId] = ExitBlockedInfo(
                reason: reason,
                phase: phase,
                rawErrorMessage: errorMessage,
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: now,
                attemptCount: existing.attemptCount + 1
            )
        } else {
            // New blockage, or the reason/phase changed - restart the debounce count
            blockedInfoByVtxoId[vtxoId] = ExitBlockedInfo(
                reason: reason,
                phase: phase,
                rawErrorMessage: errorMessage,
                firstSeenAt: now,
                lastSeenAt: now,
                attemptCount: 1
            )
        }

        Self.logger.info("[Exit Blocked] VTXO \(vtxoId.prefix(16))...: \(reason.rawValue) during \(phase.rawValue) (attempt \(self.blockedInfoByVtxoId[vtxoId]?.attemptCount ?? 1))")
        onStateChange?()
    }

    /// Clear the blocked state for a VTXO after a successful attempt of the
    /// given phase. A successful claim ends the exit, so it clears any
    /// record. A successful progression only clears progression-phase
    /// blockage: progression succeeds every check while the exit sits at
    /// Claimable, and clearing the claim record would reset its debounce
    /// count each time.
    func clearBlocked(vtxoId: String, phase: ExitBlockedPhase) {
        guard let existing = blockedInfoByVtxoId[vtxoId] else { return }
        if phase == .progression && existing.phase == .claim { return }
        blockedInfoByVtxoId.removeValue(forKey: vtxoId)
        Self.logger.info("[Exit Blocked] VTXO \(vtxoId.prefix(16))...: cleared after successful \(phase.rawValue)")
        onStateChange?()
    }

    /// Blocked info for a VTXO, debounced: only returned once the blockage
    /// has persisted for 2+ consecutive checks, so a single bad fee estimate
    /// doesn't flash a banner
    func blockedInfo(for vtxoId: String) -> ExitBlockedInfo? {
        guard let info = blockedInfoByVtxoId[vtxoId], info.isSurfaceable else { return nil }
        return info
    }
}

// MARK: - WalletManager facade

extension WalletManager {

    /// Active unilateral exits (from Bark SDK), excluding terminal ones
    var activeUnilateralExits: [ExitVtxo] {
        exitStore.activeExits
    }

    /// All unilateral exits bark still tracks — claimed exits get purged
    /// from bark's list, so completed exits are usually absent here.
    /// For completed exit history use the PersistentExitCache snapshots
    /// (persistedExitStatus / the X-Ray completed section).
    var allUnilateralExits: [ExitVtxo] {
        exitStore.exitVtxos
    }

    /// Get exits that require user action (claimable exits ready to be claimed)
    var exitsRequiringAction: [ExitVtxo] {
        exitStore.exitsRequiringAction
    }

    /// Check if there are any active unilateral exits in progress
    var hasActiveUnilateralExits: Bool {
        !activeUnilateralExits.isEmpty
    }

    /// Check if any exits require user action (ready to claim)
    var hasExitsRequiringAction: Bool {
        !exitsRequiringAction.isEmpty
    }

    // MARK: - Exit Cache Management

    /// Load exit cache metadata from persistent storage
    /// Called at app startup before wallet initialization
    func loadExitCacheFromDisk() async {
        await exitStore.loadFromDisk()
    }

    /// Refresh exit cache from Bark SDK
    /// Only runs if wallet is initialized - prevents premature refresh attempts
    func refreshExitCache() async {
        guard isInitialized else {
            Self.logger.warning("[Exit Cache] Cannot refresh - wallet not initialized")
            return
        }
        await exitStore.refresh()
    }

    /// Force immediate exit cache refresh
    /// Use this when you know exit state has changed
    func invalidateExitCache() {
        Task {
            await refreshExitCache()
        }
    }

    /// Exit VTXOs and status for an exit transaction, matched by its input
    /// VTXO ids — the shared load behind the swipe card's and the detail
    /// view's exit progress banner. The status comes from the first matched
    /// VTXO (a movement's VTXOs all belong to the same exit).
    func exitData(forInputVtxoIds inputVtxoIds: [String]) async -> (exitVtxos: [ExitVtxo], status: ExitTransactionStatus?) {
        let inputIds = Set(inputVtxoIds)
        let matched = allUnilateralExits.filter { inputIds.contains($0.vtxoId) }
        guard let first = matched.first else { return (matched, nil) }
        let status = try? await getExitStatus(vtxoId: first.vtxoId, includeHistory: true, includeTransactions: true)
        return (matched, status)
    }

    /// Get cached exit status for a VTXO
    /// Returns nil if not in cache
    func getCachedExitStatus(for vtxoId: String) -> ExitTransactionStatus? {
        exitStore.cachedStatus(for: vtxoId)
    }

    /// Last persisted status snapshot for a VTXO — the only source once
    /// bark has purged the completed exit
    func persistedExitStatus(for vtxoId: String) -> ExitTransactionStatus? {
        exitStore.persistedStatus(for: vtxoId)
    }

    /// Snapshot current exit statuses into persistent storage.
    /// Called right after a claim is broadcast — see ExitStore.snapshotStatuses.
    func snapshotExitStatuses(vtxoIds: [String]) async {
        await exitStore.snapshotStatuses(vtxoIds: vtxoIds)
    }

    /// Persist the fee of an exit claim transaction, reported by bark when
    /// the claim is created (drainExits). The claim pays into the onchain
    /// wallet from the exit output, so BDK sees it as a pure receive and can
    /// never compute its fee — this is the only fee source for claims.
    /// Marked with subsystemKind "exit_claim" so fee attribution can trust
    /// the fee despite the record having no wallet-funded inputs.
    /// Also links the claim record to its exit movement(s) right here —
    /// bark purges claimed exits from its exit list, so waiting for the
    /// status-cache relink can miss the claim txid permanently, leaving the
    /// claim visible as an unexplained onchain receive in the activity list.
    func recordClaimFee(claimTxid: String, feeSats: UInt64, drainedVtxoIds: [String]) {
        guard let context = modelContext else {
            Self.logger.warning("[Exit Claim] Cannot record claim fee - no model context")
            return
        }

        let onchainTxid = "onchain_\(claimTxid)"
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == onchainTxid }
        )

        do {
            let record: PersistentTransaction
            if let existing = try context.fetch(descriptor).first {
                record = existing
            } else {
                record = PersistentTransaction(
                    txid: onchainTxid,
                    movementId: nil,
                    type: .received,
                    amount: 0,
                    date: Date(),
                    status: .pending,
                    address: nil,
                    subsystemCategory: "onchain_transaction"
                )
                record.sourceType = "onchain"
                record.subsystemName = "bitcoin.core"
                record.paymentMethodType = "bitcoin"
                context.insert(record)
            }

            record.onchainFeeSat = Int(feeSats)
            record.subsystemKind = "exit_claim"
            try context.save()
            Self.logger.info("[Exit Claim] Recorded claim fee \(feeSats) sats for \(claimTxid.prefix(16))...")

            transactionLinkingService?.linkClaimTransaction(
                claimTxid: claimTxid,
                drainedVtxoIds: drainedVtxoIds,
                context: context
            )
        } catch {
            Self.logger.error("[Exit Claim] Failed to record claim fee: \(error)")
        }
    }

    // MARK: - Blocked Exits

    /// Record a failed progression/claim attempt for a VTXO
    /// Called by ExitProgressionService when bark reports a funding-related error
    func recordExitBlocked(vtxoId: String, phase: ExitBlockedPhase, errorMessage: String) {
        exitStore.recordBlocked(vtxoId: vtxoId, phase: phase, errorMessage: errorMessage)
    }

    /// Clear the blocked state for a VTXO after a successful attempt of the given phase
    func clearExitBlocked(vtxoId: String, phase: ExitBlockedPhase) {
        exitStore.clearBlocked(vtxoId: vtxoId, phase: phase)
    }

    /// Blocked info for a VTXO, debounced — see ExitStore.blockedInfo(for:)
    func getExitBlockedInfo(for vtxoId: String) -> ExitBlockedInfo? {
        exitStore.blockedInfo(for: vtxoId)
    }

    // MARK: - Exit Progression

    /// Manually trigger exit progression check
    /// Normally runs automatically, but can be triggered manually if needed
    func triggerExitProgression() {
        exitProgressionService?.triggerImmediateCheck()
    }

    /// Check if exit progression service is running
    var isExitProgressionRunning: Bool {
        exitProgressionService?.isRunning ?? false
    }
}
