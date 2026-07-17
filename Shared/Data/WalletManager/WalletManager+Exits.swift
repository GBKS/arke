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
    /// Note: Filters out claimed exits, as they are no longer active
    var activeUnilateralExits: [ExitVtxo] {
        // Return cached exits - no automatic refresh during access
        // Refresh is triggered explicitly after wallet initialization
        let allExits = cachedExitVtxos
        
        // Filter out claimed exits - they're complete and no longer active
        let activeExits = allExits.filter { !$0.isClaimed }
        
        return activeExits
    }
    
    /// Get all unilateral exits including claimed/completed ones
    /// Use this when you need to display complete exit history
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
    private func saveExitCacheToDisk() async {
        guard let context = modelContext else { return }
        
        do {
            // Clear old cache entries
            let oldEntries = try context.fetch(FetchDescriptor<PersistentExitCache>())
            for entry in oldEntries {
                context.delete(entry)
            }
            
            // Save new cache entries
            let now = Date()
            for exitVtxo in cachedExitVtxos {
                var blockedInfoJson: String?
                if let blockedInfo = exitBlockedInfoByVtxoId[exitVtxo.vtxoId],
                   let data = try? JSONEncoder().encode(blockedInfo) {
                    blockedInfoJson = String(data: data, encoding: .utf8)
                }

                let cacheEntry = PersistentExitCache(
                    vtxoId: exitVtxo.vtxoId,
                    amountSats: exitVtxo.amountSats,
                    isClaimed: exitVtxo.isClaimed,
                    isClaimable: exitVtxo.isClaimable,
                    stateDisplayName: exitVtxo.stateDisplayName,
                    exitStatusJson: nil, // Could serialize full status here if needed
                    blockedInfoJson: blockedInfoJson,
                    cachedAt: now,
                    lastRefreshedAt: now
                )
                context.insert(cacheEntry)
            }
            
            try context.save()
            Self.logger.info("[Exit Cache] Saved \(self.cachedExitVtxos.count) exit(s) to persistent storage")

        } catch {
            Self.logger.warning("[Exit Cache] Failed to save to disk: \(error)")
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

        // Prune blocked records for exits that are claimed or no longer exist,
        // before they get persisted below
        let activeVtxoIds = Set(cachedExitVtxos.filter { !$0.isClaimed }.map { $0.vtxoId })
        let staleBlockedIds = exitBlockedInfoByVtxoId.keys.filter { !activeVtxoIds.contains($0) }
        if !staleBlockedIds.isEmpty {
            for vtxoId in staleBlockedIds {
                exitBlockedInfoByVtxoId.removeValue(forKey: vtxoId)
            }
            Self.logger.info("[Exit Blocked] Pruned \(staleBlockedIds.count) stale blocked record(s)")
            dataVersion += 1
        }

        // Save to persistent storage for next app launch
        await saveExitCacheToDisk()
        
        // Also fetch and cache exit statuses for all exits — including
        // claimed ones, whose movements still need their claim/CPFP
        // transactions linked (relinkExitMovements reads this cache; without
        // claimed statuses a completed exit's movement never gets childTxids)
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

    /// Persist the fee of an exit claim transaction, reported by bark when
    /// the claim is created (drainExits). The claim pays into the onchain
    /// wallet from the exit output, so BDK sees it as a pure receive and can
    /// never compute its fee — this is the only fee source for claims.
    /// Marked with subsystemKind "exit_claim" so fee attribution can trust
    /// the fee despite the record having no wallet-funded inputs.
    func recordClaimFee(claimTxid: String, feeSats: UInt64) {
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
