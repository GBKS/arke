//
//  WalletManager+Exits.swift
//  Arke
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import SwiftData
import Bark
import ArkeUI
import OSLog

extension WalletManager {
    
    /// Active unilateral exits (from Bark SDK)
    /// Note: Filters out terminal exits. Claimed (complete) exits get purged
    /// from bark's exit list shortly after the claim (observed with bark
    /// 0.11 — we once assumed they stayed forever), but cancelled ones
    /// (VtxoAlreadySpent) linger there, so filtering by isInFlight is still
    /// needed to keep cancelled exits from reporting as "in progress"
    /// indefinitely (blocking the settings exit action, inflating attention
    /// counts).
    var activeUnilateralExits: [ExitVtxo] {
        // Return cached exits - no automatic refresh during access
        // Refresh is triggered explicitly after wallet initialization
        let allExits = cachedExitVtxos

        return allExits.filter { $0.isInFlight }
    }

    /// All unilateral exits bark still tracks — claimed exits get purged
    /// from bark's list, so completed exits are usually absent here.
    /// For completed exit history use the PersistentExitCache snapshots
    /// (persistedExitStatus / the X-Ray completed section).
    /// Uses cached data - refresh is triggered explicitly after wallet initialization
    var allUnilateralExits: [ExitVtxo] {
        return cachedExitVtxos
    }
    
    /// Get exits that require user action (claimable exits ready to be claimed)
    var exitsRequiringAction: [ExitVtxo] {
        activeUnilateralExits.filter { $0.isClaimable }
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
    /// Note: We don't reconstruct ExitVtxo objects from cache since they require
    /// full data from Bark. Instead, we just verify cache exists and mark it as stale.
    func loadExitCacheFromDisk() async {
        guard let context = modelContext else {
            Self.logger.warning("[Exit Cache] Cannot load from disk - no model context")
            return
        }
        
        let descriptor = FetchDescriptor<PersistentExitCache>(
            sortBy: [SortDescriptor(\.lastRefreshedAt, order: .reverse)]
        )
        
        do {
            let persistedExits = try context.fetch(descriptor)

            if !persistedExits.isEmpty {
                Self.logger.info("[Exit Cache] Found \(persistedExits.count) exit(s) in persistent storage")

                // Check age of cache
                if let lastRefresh = persistedExits.first?.lastRefreshedAt {
                    let ageSeconds = Date().timeIntervalSince(lastRefresh)
                    Self.logger.debug("[Exit Cache] Cache age: \(String(format: "%.1f", ageSeconds))s")

                    // Set cache time to trigger refresh, but don't populate empty objects
                    // The fresh data will be loaded during wallet initialization
                    exitVtxosCacheTime = lastRefresh
                }

                // Restore blocked state so the UI shows it immediately instead of
                // waiting for the next two progression checks to re-debounce
                var restoredBlockedCount = 0
                for entry in persistedExits where !entry.isClaimed {
                    if let json = entry.blockedInfoJson,
                       let data = json.data(using: .utf8),
                       let info = try? JSONDecoder().decode(ExitBlockedInfo.self, from: data) {
                        exitBlockedInfoByVtxoId[entry.vtxoId] = info
                        restoredBlockedCount += 1
                    }
                }
                if restoredBlockedCount > 0 {
                    Self.logger.info("[Exit Blocked] Restored \(restoredBlockedCount) blocked exit(s) from persistent storage")
                    dataVersion += 1
                }
            } else {
                Self.logger.info("[Exit Cache] No persistent cache found (first launch or after migration)")
            }

        } catch {
            Self.logger.warning("[Exit Cache] Failed to load from disk: \(error)")
        }
    }
    
    /// Save exit cache to persistent storage
    /// Called after successful refresh from wallet
    /// Merges into existing entries rather than wiping: bark purges claimed
    /// exits from its exit list, so entries that vanish from the list are the
    /// app's only remaining record of those exits and must be kept.
    private func saveExitCacheToDisk() async {
        guard let context = modelContext else { return }

        do {
            let existingEntries = try context.fetch(FetchDescriptor<PersistentExitCache>())
            var entriesByVtxoId: [String: PersistentExitCache] = [:]
            for entry in existingEntries {
                entriesByVtxoId[entry.vtxoId] = entry
            }

            let now = Date()
            for exitVtxo in cachedExitVtxos {
                var blockedInfoJson: String?
                if let blockedInfo = exitBlockedInfoByVtxoId[exitVtxo.vtxoId],
                   let data = try? JSONEncoder().encode(blockedInfo) {
                    blockedInfoJson = String(data: data, encoding: .utf8)
                }

                // Keep an existing snapshot when this refresh has no status
                // for the VTXO (statuses are fetched after this save runs on
                // the first refresh)
                let statusJson = cachedExitStatuses[exitVtxo.vtxoId]
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
            let liveVtxoIds = Set(cachedExitVtxos.map { $0.vtxoId })
            for entry in existingEntries where !liveVtxoIds.contains(entry.vtxoId) {
                entry.blockedInfoJson = nil
                entry.isClaimable = false
                if !entry.isClaimed, let state = entry.snapshotStatus?.state,
                   state.hasPrefix("Claimed") || state.hasPrefix("ClaimInProgress") {
                    entry.isClaimed = true
                    entry.stateDisplayName = String(localized: "exit_state_complete", defaultValue: "Complete")
                }
            }

            let historicalCount = existingEntries.count(where: { !liveVtxoIds.contains($0.vtxoId) })
            try context.save()
            Self.logger.info("[Exit Cache] Saved \(self.cachedExitVtxos.count) live exit(s), kept \(historicalCount) historical")

        } catch {
            Self.logger.warning("[Exit Cache] Failed to save to disk: \(error)")
        }
    }

    /// Snapshot current exit statuses for the given VTXOs into persistent
    /// storage (and the in-memory status cache). Called right after a claim
    /// is broadcast: bark purges claimed exits from its exit list shortly
    /// after, and this is the last reliable chance to capture their history.
    func snapshotExitStatuses(vtxoIds: [String]) async {
        guard let context = modelContext else { return }

        for vtxoId in vtxoIds {
            guard let status = try? await getExitStatus(
                vtxoId: vtxoId,
                includeHistory: true,
                includeTransactions: true
            ) else {
                Self.logger.warning("[Exit Cache] No status to snapshot for VTXO \(vtxoId.prefix(16))...")
                continue
            }

            cachedExitStatuses[vtxoId] = status

            guard let statusJson = ExitStatusSnapshot.encodeJson(from: status) else { continue }
            let descriptor = FetchDescriptor<PersistentExitCache>(
                predicate: #Predicate { $0.vtxoId == vtxoId }
            )
            do {
                if let entry = try context.fetch(descriptor).first {
                    entry.exitStatusJson = statusJson
                    entry.lastRefreshedAt = Date()
                } else {
                    let amount = cachedExitVtxos.first { $0.vtxoId == vtxoId }?.amountSats ?? 0
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
    
    /// Refresh exit cache from Bark SDK
    /// Only runs if wallet is initialized - prevents premature refresh attempts
    func refreshExitCache() async {
        // Guard: Only refresh if wallet is initialized
        guard isInitialized else {
            Self.logger.warning("[Exit Cache] Cannot refresh - wallet not initialized")
            return
        }

        // Use task deduplication to prevent concurrent refreshes
        do {
            try await taskManager.execute(key: "exit-cache-refresh") {
                try await self._performExitCacheRefresh()
            }
        } catch {
            Self.logger.warning("[Exit Cache] Refresh failed: \(error)")
        }
    }
    
    /// Internal method that performs the actual cache refresh
    /// Separated for task deduplication
    private func _performExitCacheRefresh() async throws {
        Self.logger.debug("[Exit Cache] Refreshing exit cache...")

        cachedExitVtxos = try await getExitVtxos()
        exitVtxosCacheTime = Date()
        Self.logger.info("[Exit Cache] Fetched \(self.cachedExitVtxos.count) exit VTXO(s)")

        // Prune blocked records for exits that are terminal (claimed or
        // cancelled) or no longer exist, before they get persisted below — a
        // cancelled exit can't progress, so its blocked banner is stale
        let activeVtxoIds = Set(cachedExitVtxos.filter { $0.isInFlight }.map { $0.vtxoId })
        let staleBlockedIds = exitBlockedInfoByVtxoId.keys.filter { !activeVtxoIds.contains($0) }
        if !staleBlockedIds.isEmpty {
            for vtxoId in staleBlockedIds {
                exitBlockedInfoByVtxoId.removeValue(forKey: vtxoId)
            }
            Self.logger.info("[Exit Blocked] Pruned \(staleBlockedIds.count) stale blocked record(s)")
            dataVersion += 1
        }

        // Also fetch and cache exit statuses for all exits still in bark's
        // list (relinkExitMovements reads this cache to link exit/CPFP
        // transactions). Claimed exits get purged from the list, so their
        // claim tx is linked at drain time instead (recordClaimFee) and
        // their last status survives via the persisted snapshot.
        var newExitStatuses: [String: ExitTransactionStatus] = [:]
        var statusCount = 0
        var totalTxids = 0

        for exitVtxo in cachedExitVtxos {
            if let status = try? await getExitStatus(
                vtxoId: exitVtxo.vtxoId,
                includeHistory: true,
                includeTransactions: true
            ) {
                newExitStatuses[exitVtxo.vtxoId] = status
                statusCount += 1
                
                // Log txids extracted from this status
                let txids = ExitStatusParser.extractAllTransactionIds(from: status)
                if !txids.isEmpty {
                    Self.logger.debug("[Exit Cache] VTXO \(exitVtxo.vtxoId.prefix(16))... has \(txids.count) txid(s)")
                    totalTxids += txids.count
                }
            }
        }
        cachedExitStatuses = newExitStatuses
        exitStatusesCacheTime = Date()

        // Save to persistent storage for next app launch — after the status
        // fetch, so each entry's snapshot reflects this refresh
        await saveExitCacheToDisk()

        Self.logger.info("[Exit Cache] Cached \(statusCount) exit status(es) with \(totalTxids) total txid(s)")

        // Trigger re-linking after cache is refreshed
        Self.logger.debug("[Exit Cache] Triggering exit transaction re-linking...")
        await relinkExitTransactions()
    }
    
    /// Force immediate exit cache refresh bypassing TTL
    /// Use this when you know exit state has changed
    func invalidateExitCache() {
        exitVtxosCacheTime = nil
        exitStatusesCacheTime = nil
        Task {
            await refreshExitCache()
            // After refreshing exit cache, trigger re-linking for exits
            await relinkExitTransactions()
        }
    }
    
    /// Re-link exit movements after exit status cache updates
    /// Called automatically when exit cache is refreshed
    private func relinkExitTransactions() async {
        guard let context = modelContext,
              let linkingService = transactionLinkingService else {
            return
        }
        await linkingService.relinkExitMovements(context: context)
    }
    
    /// Get cached exit status for a VTXO
    /// Returns nil if not in cache
    func getCachedExitStatus(for vtxoId: String) -> ExitTransactionStatus? {
        return cachedExitStatuses[vtxoId]
    }

    /// Last persisted status snapshot for a VTXO — the only source once
    /// bark has purged the completed exit
    func persistedExitStatus(for vtxoId: String) -> ExitTransactionStatus? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<PersistentExitCache>(
            predicate: #Predicate { $0.vtxoId == vtxoId }
        )
        return (try? context.fetch(descriptor).first)?.snapshotStatus
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
        let reason = ExitBlockedReason.classify(errorMessage)
        let now = Date()

        if let existing = exitBlockedInfoByVtxoId[vtxoId],
           existing.reason == reason, existing.phase == phase {
            exitBlockedInfoByVtxoId[vtxoId] = ExitBlockedInfo(
                reason: reason,
                phase: phase,
                rawErrorMessage: errorMessage,
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: now,
                attemptCount: existing.attemptCount + 1
            )
        } else {
            // New blockage, or the reason/phase changed - restart the debounce count
            exitBlockedInfoByVtxoId[vtxoId] = ExitBlockedInfo(
                reason: reason,
                phase: phase,
                rawErrorMessage: errorMessage,
                firstSeenAt: now,
                lastSeenAt: now,
                attemptCount: 1
            )
        }

        Self.logger.info("[Exit Blocked] VTXO \(vtxoId.prefix(16))...: \(reason.rawValue) during \(phase.rawValue) (attempt \(self.exitBlockedInfoByVtxoId[vtxoId]?.attemptCount ?? 1))")
        dataVersion += 1
    }

    /// Clear the blocked state for a VTXO after a successful attempt of the given
    /// phase. A successful claim ends the exit, so it clears any record. A
    /// successful progression only clears progression-phase blockage: progression
    /// succeeds every check while the exit sits at Claimable, and clearing the
    /// claim record would reset its debounce count each time.
    func clearExitBlocked(vtxoId: String, phase: ExitBlockedPhase) {
        guard let existing = exitBlockedInfoByVtxoId[vtxoId] else { return }
        if phase == .progression && existing.phase == .claim { return }
        exitBlockedInfoByVtxoId.removeValue(forKey: vtxoId)
        Self.logger.info("[Exit Blocked] VTXO \(vtxoId.prefix(16))...: cleared after successful \(phase.rawValue)")
        dataVersion += 1
    }

    /// Blocked info for a VTXO, debounced: only returned once the blockage has
    /// persisted for 2+ consecutive checks, so a single bad fee estimate doesn't
    /// flash a banner
    func getExitBlockedInfo(for vtxoId: String) -> ExitBlockedInfo? {
        guard let info = exitBlockedInfoByVtxoId[vtxoId], info.isSurfaceable else { return nil }
        return info
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
