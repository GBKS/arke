//
//  PersistentExitCache.swift
//  Arke
//
//  Persistent cache for exit VTXO data to enable fast UI rendering
//

import Foundation
import SwiftData

/// Persistent cache entry for a single exit VTXO
/// Allows transaction list to render immediately with cached exit status data
@Model
final class PersistentExitCache {
    // VTXO identifier (unique)
    var vtxoId: String = ""
    
    // Exit VTXO data
    var amountSats: UInt64 = 0
    var isClaimed: Bool = false
    var isClaimable: Bool = false
    var stateDisplayName: String = ""
    
    // Exit status data (serialized JSON for flexibility)
    var exitStatusJson: String?

    // Blocked state (serialized ExitBlockedInfo), set when the exit can't
    // progress because fees can't be covered
    var blockedInfoJson: String?

    // Cache metadata
    var cachedAt: Date = Date()
    var lastRefreshedAt: Date = Date()

    init(
        vtxoId: String,
        amountSats: UInt64,
        isClaimed: Bool,
        isClaimable: Bool,
        stateDisplayName: String,
        exitStatusJson: String? = nil,
        blockedInfoJson: String? = nil,
        cachedAt: Date = Date(),
        lastRefreshedAt: Date = Date()
    ) {
        self.vtxoId = vtxoId
        self.amountSats = amountSats
        self.isClaimed = isClaimed
        self.isClaimable = isClaimable
        self.stateDisplayName = stateDisplayName
        self.exitStatusJson = exitStatusJson
        self.blockedInfoJson = blockedInfoJson
        self.cachedAt = cachedAt
        self.lastRefreshedAt = lastRefreshedAt
    }
}

// MARK: - Helper Extensions

extension PersistentExitCache {
    /// Check if cache entry is fresh (less than 5 minutes old)
    var isFresh: Bool {
        Date().timeIntervalSince(lastRefreshedAt) < 300 // 5 minutes
    }
    
    /// Check if cache entry is stale (more than 1 hour old)
    var isStale: Bool {
        Date().timeIntervalSince(lastRefreshedAt) > 3600 // 1 hour
    }
    
    /// Age of cache entry in seconds
    var ageInSeconds: TimeInterval {
        Date().timeIntervalSince(lastRefreshedAt)
    }
}
