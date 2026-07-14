//
//  VTXOHealth.swift
//  Ark wallet prototype
//
//  Created by Christoph on 1/6/26.
//

import Foundation
import ArkeUI

/// Represents the health status of VTXOs in the wallet
struct VTXOHealth: Sendable {
    var expiredVTXOs: [VTXOModel]
    var vtxosExpiringSoon: [VTXOModel]
    var thresholdBlocks: Int
    
    init(
        expiredVTXOs: [VTXOModel] = [],
        vtxosExpiringSoon: [VTXOModel] = [],
        thresholdBlocks: Int = 144 // ~1 day
    ) {
        self.expiredVTXOs = expiredVTXOs
        self.vtxosExpiringSoon = vtxosExpiringSoon
        self.thresholdBlocks = thresholdBlocks
    }
    
    // MARK: - Computed Properties
    
    var hasExpiredVTXOs: Bool {
        !expiredVTXOs.isEmpty
    }
    
    var hasVTXOsExpiringSoon: Bool {
        !vtxosExpiringSoon.isEmpty
    }
    
    var needsAttention: Bool {
        hasExpiredVTXOs || hasVTXOsExpiringSoon
    }
    
    var expiredCount: Int {
        expiredVTXOs.count
    }
    
    var expiringSoonCount: Int {
        vtxosExpiringSoon.count
    }
    
    var totalExpiredAmount: Int {
        expiredVTXOs.reduce(0) { $0 + $1.amountSat }
    }
    
    var totalExpiringSoonAmount: Int {
        vtxosExpiringSoon.reduce(0) { $0 + $1.amountSat }
    }
    
    // MARK: - Display Properties
    
    var formattedExpiredAmount: String {
        BitcoinFormatter.shared.formatAmount(totalExpiredAmount)
    }
    
    var formattedExpiringSoonAmount: String {
        BitcoinFormatter.shared.formatAmount(totalExpiringSoonAmount)
    }
    
    var statusMessage: String? {
        if hasExpiredVTXOs && hasVTXOsExpiringSoon {
            return String(localized: "balance_vtxos_expired_and_expiring \(expiredCount) \(expiringSoonCount)")
        } else if hasExpiredVTXOs {
            return String(localized: "balance_vtxos_have_expired \(expiredCount)")
        } else if hasVTXOsExpiringSoon {
            return String(localized: "balance_vtxos_expiring_soon \(expiringSoonCount)")
        } else {
            return nil
        }
    }
    
    var actionMessage: String? {
        if hasExpiredVTXOs {
            return "Refresh or exit expired VTXOs to recover funds"
        } else if hasVTXOsExpiringSoon {
            return "Consider refreshing VTXOs before they expire"
        } else {
            return nil
        }
    }
    
    var priority: VTXOHealthPriority {
        if hasExpiredVTXOs {
            return .critical
        } else if hasVTXOsExpiringSoon {
            // Higher priority if expiring very soon
            // This would need current block height to calculate
            // For now, just return high priority
            return .high
        } else {
            return .normal
        }
    }
    
    // MARK: - Calculate from VTXOs
    
    /// Calculate VTXO health from list of VTXOs and current block height
    static func calculate(
        from vtxos: [VTXOModel],
        currentBlockHeight: Int,
        expiryThresholdBlocks: Int = 144
    ) -> VTXOHealth {
        let expired = vtxos.filter { vtxo in
            vtxo.expiryHeight <= currentBlockHeight && !vtxo.isSpent
        }
        
        let expiringSoon = vtxos.filter { vtxo in
            let blocksUntilExpiry = vtxo.expiryHeight - currentBlockHeight
            return blocksUntilExpiry > 0 && 
                   blocksUntilExpiry <= expiryThresholdBlocks && 
                   !vtxo.isSpent
        }
        
        return VTXOHealth(
            expiredVTXOs: expired,
            vtxosExpiringSoon: expiringSoon,
            thresholdBlocks: expiryThresholdBlocks
        )
    }
    
    /// Get blocks until expiry for a specific VTXO
    func blocksUntilExpiry(for vtxo: VTXOModel, currentHeight: Int) -> Int {
        return max(0, vtxo.expiryHeight - currentHeight)
    }
    
    /// Get estimated time until expiry for a specific VTXO
    func estimatedTimeUntilExpiry(for vtxo: VTXOModel, currentHeight: Int) -> TimeInterval {
        let blocks = blocksUntilExpiry(for: vtxo, currentHeight: currentHeight)
        return TimeInterval(blocks * 10 * 60) // blocks * 10 minutes * 60 seconds
    }
    
    /// Format time remaining until expiry
    func formattedTimeUntilExpiry(for vtxo: VTXOModel, currentHeight: Int) -> String {
        let timeInterval = estimatedTimeUntilExpiry(for: vtxo, currentHeight: currentHeight)
        
        if timeInterval <= 0 {
            return "Expired"
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            return String(localized: "format_approx_days \(days)")
        } else if hours > 0 {
            return String(localized: "format_approx_hours \(hours)")
        } else {
            return String(localized: "format_approx_minutes \(minutes)")
        }
    }
}

/// Priority levels for VTXO health warnings
enum VTXOHealthPriority: Comparable, Sendable {
    case normal
    case high
    case critical
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}
