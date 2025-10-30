//
//  ArkBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//  Migrated by Assistant on 10/29/25 - Unified with PersistedArkBalance
//

import Foundation
import SwiftData

/// Pure API response struct for Ark balance data
///
/// This struct is used for decoding API responses and passing data between actors.
/// It's naturally Sendable and contains all the computed properties for convenience.
struct ArkBalanceResponse: Codable, Sendable {
    let spendableSat: Int
    let pendingLightningSendSat: Int
    let pendingInRoundSat: Int
    let pendingExitSat: Int
    let pendingBoardSat: Int
    
    enum CodingKeys: String, CodingKey {
        case spendableSat = "spendable_sat"
        case pendingLightningSendSat = "pending_lightning_send_sat"
        case pendingInRoundSat = "pending_in_round_sat"
        case pendingExitSat = "pending_exit_sat"
        case pendingBoardSat = "pending_board_sat"
    }
    
    // MARK: - Computed Properties (mirrored from ArkBalanceModel)
    
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

/// SwiftData persistence model for Ark balance
/// 
/// This model is now focused purely on persistence and UI observation.
/// API decoding is handled by ArkBalanceResponse struct.
///
/// Key features:
/// - SwiftData @Model for direct UI observation and persistence
/// - Singleton pattern with id = "ark_balance"
/// - Built-in cache validity and update methods
/// - All existing computed properties preserved
@Model
class ArkBalanceModel {
    var id: String
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    var lastUpdated: Date
    
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
    
    // MARK: - Convenience Methods
    
    /// Create from API response
    convenience init(from response: ArkBalanceResponse) {
        self.init(
            spendableSat: response.spendableSat,
            pendingLightningSendSat: response.pendingLightningSendSat,
            pendingInRoundSat: response.pendingInRoundSat,
            pendingExitSat: response.pendingExitSat,
            pendingBoardSat: response.pendingBoardSat,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Persistence Methods
    
    /// Check if the cached balance is still valid (within 5 minutes)
    var isValid: Bool {
        let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
        return Date().timeIntervalSince(lastUpdated) < cacheValidityDuration
    }
    
    /// Update with new balance data from API response
    func update(from response: ArkBalanceResponse) {
        self.spendableSat = response.spendableSat
        self.pendingLightningSendSat = response.pendingLightningSendSat
        self.pendingInRoundSat = response.pendingInRoundSat
        self.pendingExitSat = response.pendingExitSat
        self.pendingBoardSat = response.pendingBoardSat
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
