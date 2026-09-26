//
//  BalanceRefreshStatusViewModel.swift
//  Arke
//
//  Created by Assistant on 4/24/26.
//

import SwiftUI
import Observation
import ArkeUI

/// Shared view model for balance refresh status calculations
/// Uses ultra-simple logic: show when refresh becomes ppm-free (cheapest)
@Observable
@MainActor
class BalanceRefreshStatusViewModel {
    
    // MARK: - Dependencies
    
    private let walletManager: WalletManager
    
    // MARK: - State
    
    var vtxos: [VTXOModel] = []
    var latestBlockHeight: Int?
    var nextRoundStartTime: UInt64?
    var hasCompletedInitialLoad = false
    
    /// Cached list of VTXOs needing refresh (updated during loadData)
    var vtxosNeedingRefresh: [VTXOModel] = []
    
    // MARK: - Initialization
    
    init(walletManager: WalletManager) {
        self.walletManager = walletManager
    }
    
    // MARK: - Computed Properties
    
    var activeVTXOs: [VTXOModel] {
        vtxos.filter { $0.state != .spent }
    }
    
    var hasActiveRefresh: Bool {
        walletManager.hasActiveRefresh
    }
    
    var hasVtxosToRefresh: Bool {
        !vtxosNeedingRefresh.isEmpty && !hasActiveRefresh
    }
    
    /// Calculate when the next VTXO enters the ppm-free window
    var nextPpmFreeHeight: Int? {
        guard let feeSchedule = walletManager.arkInfo?.feeSchedule,
              let nextExpiry = activeVTXOs.min(by: { $0.expiryHeight < $1.expiryHeight }) else {
            return nil
        }
        
        return calculatePpmFreeHeight(vtxo: nextExpiry, feeSchedule: feeSchedule)
    }
    
    /// Calculate blocks until the ppm-free window starts
    var blocksUntilPpmFree: Int? {
        guard let ppmFreeHeight = nextPpmFreeHeight,
              let currentHeight = latestBlockHeight else {
            return nil
        }
        return ppmFreeHeight - currentHeight
    }
    
    /// Simple status message based on three states
    var statusMessage: String {
        if hasActiveRefresh {
            return String(localized: "balance_refreshing", defaultValue: "Refreshing")
        } else if hasVtxosToRefresh {
            return L10n.balanceRefreshNow
        } else if let blocks = blocksUntilPpmFree, blocks > 0 {
            return String(localized: "balance_refresh_in %@", defaultValue: "Refresh in \(formatBlocks(blocks))")
        } else {
            return ""
        }
    }
    
    /// Returns the total amount (in satoshis) of VTXOs that should be refreshed
    var totalAmountToRefresh: Int {
        return vtxosNeedingRefresh.reduce(0) { $0 + $1.amountSat }
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        do {
            vtxos = try await walletManager.getVTXOs()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            nextRoundStartTime = try? await walletManager.nextRoundStartTime()
            
            // Load VTXOs needing refresh from SDK, excluding those already in
            // an in-flight refresh.
            //
            // What this buys: `vtxoIdsBeingRefreshed()` also covers VTXOs
            // locked by an issued pending round, which the previous
            // movement-only filter missed. The `if hasActiveRefresh` gate it
            // replaces was redundant, not a blind spot — the old helper
            // already returned an empty set when no refresh was pending, and
            // `hasVtxosToRefresh` still ANDs `!hasActiveRefresh`. The
            // "Refresh now" symptom is addressed by the post-schedule refetch
            // instead (Refresh_Deduplication.md Phase 1).
            let vtxosFromSDK = try await walletManager.getVTXOsNeedingRefresh()
            let beingRefreshed = await walletManager.vtxoIdsBeingRefreshed()
            // Also exclude VTXOs mid-exit (Guard B, fail-open like the service
            // path) so the modal's list and amount match what the service will
            // actually schedule — without this the confirmation can overstate
            // the refresh, and "Refresh now" appears for an all-mid-exit set.
            let exitingIds = await walletManager.exitingVtxoIds()
            vtxosNeedingRefresh = vtxosFromSDK.filter {
                !beingRefreshed.contains($0.id) && !exitingIds.contains($0.id)
            }
        } catch {
            print("BalanceRefreshStatusViewModel: \(error)")
        }
        hasCompletedInitialLoad = true
    }
    
    // MARK: - Helper Methods
    
    /// Calculate when a VTXO enters the ppm-free window
    private func calculatePpmFreeHeight(vtxo: VTXOModel, feeSchedule: FeeSchedule) -> Int? {
        // Find the threshold where ppm becomes 0
        let ppmTable = feeSchedule.refresh.ppmExpiryTable
            .sorted { $0.expiryBlocksThreshold > $1.expiryBlocksThreshold }
        
        for entry in ppmTable {
            if entry.ppm == 0 {
                // VTXO enters ppm-free window at:
                // expiry_height - threshold_blocks
                return vtxo.expiryHeight - entry.expiryBlocksThreshold
            }
        }
        
        // No ppm-free window exists
        return nil
    }
    
    /// Format blocks into human-readable time, assuming 10-minute blocks
    /// on all networks.
    func formatBlocks(_ blocks: Int) -> String {
        BlockTimeFormatter.duration(forBlocks: blocks)
    }
}
