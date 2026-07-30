//
//  PersistentExitCache.swift
//  Arke
//
//  Persistent cache for exit VTXO data to enable fast UI rendering
//

import Foundation
import SwiftData
import Bark

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

// MARK: - Exit Status Snapshot

/// Codable mirror of Bark.ExitTransactionStatus, stored in
/// `PersistentExitCache.exitStatusJson`. bark purges completed exits from
/// its exit list (and their statuses with them), so this snapshot is the
/// app's only durable record of an exit's history once it's claimed.
nonisolated struct ExitStatusSnapshot: Codable {
    let vtxoId: String
    let state: String
    let history: [String]?
    let transactionCount: UInt32

    init(status: ExitTransactionStatus) {
        self.vtxoId = status.vtxoId
        self.state = status.state
        self.history = status.history
        self.transactionCount = status.transactionCount
    }

    var status: ExitTransactionStatus {
        ExitTransactionStatus(
            vtxoId: vtxoId,
            state: state,
            history: history,
            transactionCount: transactionCount
        )
    }

    static func encodeJson(from status: ExitTransactionStatus) -> String? {
        guard let data = try? JSONEncoder().encode(ExitStatusSnapshot(status: status)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Helper Extensions

extension PersistentExitCache {
    /// Last known exit status decoded from the persisted snapshot, if any
    var snapshotStatus: ExitTransactionStatus? {
        guard let json = exitStatusJson,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ExitStatusSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.status
    }

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
