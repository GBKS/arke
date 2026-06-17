//
//  BalanceRefreshStatusViewModel.swift
//  Arke
//
//  Created by Assistant on 4/24/26.
//

import SwiftUI
import Observation

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
    
    /// Get the set of VTXO IDs that are currently being refreshed in pending transactions
    var vtxosBeingRefreshed: Set<String> {
        guard hasActiveRefresh else { return Set() }
        
        // Get all pending refresh transactions
        let pendingRefreshes = walletManager.transactions.filter {
            $0.category == .refresh && $0.status == .pending
        }
        
        // Collect all VTXO IDs that are inputs to these transactions
        return Set(pendingRefreshes.flatMap { $0.inputVtxoIds })
    }
    
    var hasActiveRefresh: Bool {
        walletManager.transactions.contains {
            $0.category == .refresh && $0.status == .pending
        }
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
            return "Refreshing"
        } else if hasVtxosToRefresh {
            return "Refresh now"
        } else if let blocks = blocksUntilPpmFree, blocks > 0 {
            return "Refresh in \(formatBlocks(blocks))"
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
            
            // Load VTXOs needing refresh from SDK
            let vtxosFromSDK = try await walletManager.getVTXOsNeedingRefresh()
            
            // Filter out VTXOs that are already being refreshed
            if hasActiveRefresh {
                let beingRefreshed = vtxosBeingRefreshed
                vtxosNeedingRefresh = vtxosFromSDK.filter { !beingRefreshed.contains($0.id) }
            } else {
                vtxosNeedingRefresh = vtxosFromSDK
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
    
    /// Format blocks into human-readable time
    func formatBlocks(_ blocks: Int) -> String {
        let network = walletManager.arkInfo?.network.lowercased() ?? "bitcoin"
        let secondsPerBlock = (network == "mainnet" || network == "bitcoin") ? 600 : 150
        let seconds = blocks * secondsPerBlock
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        
        return formatter.string(from: TimeInterval(seconds)) ?? "\(blocks) blocks"
    }
}
