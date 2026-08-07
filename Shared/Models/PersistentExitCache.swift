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
///
/// Format v2 (bark 0.16+): state/history stored as Codable
/// `ParsedExitState`. v1 snapshots stored the Rust-Debug strings the old
/// bindings emitted (including pre-0.11 case names); they remain readable
/// forever via `ExitStatusParser` and upgrade lazily on the next write.
nonisolated struct ExitStatusSnapshot: Codable {
    let version: Int
    let vtxoId: String
    let state: ParsedExitState
    let history: [ParsedExitState]?
    let transactionCount: UInt32

    static let currentVersion = 2

    init(status: ExitTransactionStatus) {
        self.version = Self.currentVersion
        self.vtxoId = status.vtxoId
        self.state = ParsedExitState(from: status.state)
        self.history = status.history.map { $0.map { ParsedExitState(from: $0) } }
        self.transactionCount = status.transactionCount
    }

    /// Reconstructed Bark status, so persisted exits flow through the same
    /// channels as live ones. Lossless for v2 snapshots; v1 legacy tx
    /// statuses map to their nearest Bark case (see ParsedExitState+Bark).
    var status: ExitTransactionStatus {
        ExitTransactionStatus(
            vtxoId: vtxoId,
            state: Bark.ExitState(from: state),
            history: history.map { $0.map { Bark.ExitState(from: $0) } },
            transactionCount: transactionCount
        )
    }

    static func encodeJson(from status: ExitTransactionStatus) -> String? {
        guard let data = try? JSONEncoder().encode(ExitStatusSnapshot(status: status)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a persisted snapshot, falling back to the v1 string format.
    static func decode(fromJson json: String) -> ExitStatusSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        if let v2 = try? JSONDecoder().decode(ExitStatusSnapshot.self, from: data),
           v2.version >= 2 {
            return v2
        }
        guard let v1 = try? JSONDecoder().decode(V1.self, from: data) else { return nil }
        return ExitStatusSnapshot(v1: v1)
    }

    /// v1 on-disk shape: Rust-Debug strings from the pre-0.16 bindings
    private struct V1: Codable {
        let vtxoId: String
        let state: String
        let history: [String]?
        let transactionCount: UInt32
    }

    private init(v1: V1) {
        self.version = Self.currentVersion
        self.vtxoId = v1.vtxoId
        self.state = ExitStatusParser.parseState(v1.state) ?? .unparsed(v1.state)
        self.history = v1.history.map { $0.map { ExitStatusParser.parseState($0) ?? .unparsed($0) } }
        self.transactionCount = v1.transactionCount
    }
}

// MARK: - Helper Extensions

extension PersistentExitCache {
    /// Last known exit status decoded from the persisted snapshot (v2 or
    /// legacy v1 string format), if any
    var snapshotStatus: ExitTransactionStatus? {
        guard let json = exitStatusJson else { return nil }
        return ExitStatusSnapshot.decode(fromJson: json)?.status
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
