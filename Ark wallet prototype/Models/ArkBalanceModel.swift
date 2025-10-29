//
//  ArkBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//  Migrated by Assistant on 10/29/25 - Unified with PersistedArkBalance
//

import Foundation
import SwiftData

/// Unified Ark balance model that serves both API decoding and SwiftData persistence
/// 
/// This model combines what was previously ArkBalanceModel (API) and PersistedArkBalance (persistence)
/// into a single class following the transaction architecture migration pattern.
///
/// Key features:
/// - SwiftData @Model for direct UI observation and persistence
/// - Codable for API response decoding (id and lastUpdated excluded from API)
/// - Singleton pattern with id = "ark_balance"
/// - Built-in cache validity and update methods
/// - All existing computed properties preserved
@Model
class ArkBalanceModel: Codable, @unchecked Sendable {
    var id: String
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    var lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case spendableSat = "spendable_sat"
        case pendingLightningSendSat = "pending_lightning_send_sat"
        case pendingInRoundSat = "pending_in_round_sat"
        case pendingExitSat = "pending_exit_sat"
        case pendingBoardSat = "pending_board_sat"
        // Note: id and lastUpdated are not part of API response
    }
    
    // MARK: - Initialization
    
    init(
        spendableSat: Int,
        pendingLightningSendSat: Int,
        pendingInRoundSat: Int,
        pendingExitSat: Int,
        pendingBoardSat: Int,
        lastUpdated: Date = Date()
    ) {
        self.id = "ark_balance" // Singleton approach
        self.spendableSat = spendableSat
        self.pendingLightningSendSat = pendingLightningSendSat
        self.pendingInRoundSat = pendingInRoundSat
        self.pendingExitSat = pendingExitSat
        self.pendingBoardSat = pendingBoardSat
        self.lastUpdated = lastUpdated
    }
    
    // MARK: - Codable Implementation
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = "ark_balance"
        self.spendableSat = try container.decode(Int.self, forKey: .spendableSat)
        self.pendingLightningSendSat = try container.decode(Int.self, forKey: .pendingLightningSendSat)
        self.pendingInRoundSat = try container.decode(Int.self, forKey: .pendingInRoundSat)
        self.pendingExitSat = try container.decode(Int.self, forKey: .pendingExitSat)
        self.pendingBoardSat = try container.decode(Int.self, forKey: .pendingBoardSat)
        self.lastUpdated = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spendableSat, forKey: .spendableSat)
        try container.encode(pendingLightningSendSat, forKey: .pendingLightningSendSat)
        try container.encode(pendingInRoundSat, forKey: .pendingInRoundSat)
        try container.encode(pendingExitSat, forKey: .pendingExitSat)
        try container.encode(pendingBoardSat, forKey: .pendingBoardSat)
        // Note: id and lastUpdated are not encoded for API
    }
    
    // MARK: - Persistence Methods
    
    /// Check if the cached balance is still valid (within 5 minutes)
    var isValid: Bool {
        let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
        return Date().timeIntervalSince(lastUpdated) < cacheValidityDuration
    }
    
    /// Update with new balance data from API response
    func update(from decodedBalance: ArkBalanceModel) {
        self.spendableSat = decodedBalance.spendableSat
        self.pendingLightningSendSat = decodedBalance.pendingLightningSendSat
        self.pendingInRoundSat = decodedBalance.pendingInRoundSat
        self.pendingExitSat = decodedBalance.pendingExitSat
        self.pendingBoardSat = decodedBalance.pendingBoardSat
        self.lastUpdated = Date()
    }
    
    
    /// Spendable balance in BTC
    var spendableBTC: Double {
        Double(spendableSat) / 100_000_000
    }
    
    var pendingLightningSendBTC: Double {
        Double(pendingLightningSendSat) / 100_000_000
    }
    
    var pendingInRoundBTC: Double {
        Double(pendingInRoundSat) / 100_000_000
    }
    
    var pendingExitBTC: Double {
        Double(pendingExitSat) / 100_000_000
    }
    
    var pendingBoardBTC: Double {
        Double(pendingBoardSat) / 100_000_000
    }
    
    // Total of all pending amounts
    var totalPendingSat: Int {
        pendingLightningSendSat + pendingInRoundSat + pendingExitSat + pendingBoardSat
    }
    
    var totalPendingBTC: Double {
        Double(totalPendingSat) / 100_000_000
    }
    
    // Total balance including spendable and all pending
    var totalSat: Int {
        spendableSat + totalPendingSat
    }
    
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
}
