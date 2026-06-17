//
//  WalletManager+Exits.swift
//  Arke
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import SwiftData
import Bark
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
                let cacheEntry = PersistentExitCache(
                    vtxoId: exitVtxo.vtxoId,
                    amountSats: exitVtxo.amountSats,
                    isClaimed: exitVtxo.isClaimed,
                    isClaimable: exitVtxo.isClaimable,
                    stateDisplayName: exitVtxo.stateDisplayName,
                    exitStatusJson: nil, // Could serialize full status here if needed
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
        
        // Save to persistent storage for next app launch
        await saveExitCacheToDisk()
        
        // Also fetch and cache exit statuses for all active exits
        var newExitStatuses: [String: ExitTransactionStatus] = [:]
        var statusCount = 0
        var totalTxids = 0
        
        for exitVtxo in cachedExitVtxos where !exitVtxo.isClaimed {
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
