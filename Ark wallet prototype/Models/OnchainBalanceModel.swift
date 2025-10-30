//
//  OnchainBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//  Migrated by Assistant on 10/29/25 - Unified with PersistedOnchainBalance
//

import Foundation
import SwiftData

/// Pure API response struct for Onchain balance data
///
/// This struct is used for decoding API responses and passing data between actors.
/// It's naturally Sendable and contains all the computed properties for convenience.
struct OnchainBalanceResponse: Codable, Sendable {
    let totalSat: Int
    let trustedSpendableSat: Int
    let immatureSat: Int
    let trustedPendingSat: Int
    let untrustedPendingSat: Int
    let confirmedSat: Int
    
    enum CodingKeys: String, CodingKey {
        case totalSat = "total_sat"
        case trustedSpendableSat = "trusted_spendable_sat"
        case immatureSat = "immature_sat"
        case trustedPendingSat = "trusted_pending_sat"
        case untrustedPendingSat = "untrusted_pending_sat"
        case confirmedSat = "confirmed_sat"
    }
    
    // MARK: - Computed Properties (mirrored from OnchainBalanceModel)
    
    /// Total balance in BTC
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
    
    /// Trusted spendable balance in BTC
    var trustedSpendableBTC: Double {
        Double(trustedSpendableSat) / 100_000_000
    }
    
    /// Confirmed balance in BTC
    var confirmedBTC: Double {
        Double(confirmedSat) / 100_000_000
    }
}

/// SwiftData persistence model for Onchain balance
/// 
/// This model is now focused purely on persistence and UI observation.
/// API decoding is handled by OnchainBalanceResponse struct.
///
/// Key features:
/// - SwiftData @Model for direct UI observation and persistence
/// - Singleton pattern with id = "onchain_balance"
/// - Built-in cache validity and update methods
/// - All existing computed properties preserved
@Model
class OnchainBalanceModel {
    var id: String
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    var lastUpdated: Date
    
    // MARK: - Initialization
    
    init(
        totalSat: Int,
        trustedSpendableSat: Int,
        immatureSat: Int,
        trustedPendingSat: Int,
        untrustedPendingSat: Int,
        confirmedSat: Int,
        lastUpdated: Date = Date()
    ) {
        self.id = "onchain_balance" // Singleton approach
        self.totalSat = totalSat
        self.trustedSpendableSat = trustedSpendableSat
        self.immatureSat = immatureSat
        self.trustedPendingSat = trustedPendingSat
        self.untrustedPendingSat = untrustedPendingSat
        self.confirmedSat = confirmedSat
        self.lastUpdated = lastUpdated
    }
    
    // MARK: - Convenience Methods
    
    /// Create from API response
    convenience init(from response: OnchainBalanceResponse) {
        self.init(
            totalSat: response.totalSat,
            trustedSpendableSat: response.trustedSpendableSat,
            immatureSat: response.immatureSat,
            trustedPendingSat: response.trustedPendingSat,
            untrustedPendingSat: response.untrustedPendingSat,
            confirmedSat: response.confirmedSat,
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
    func update(from response: OnchainBalanceResponse) {
        self.totalSat = response.totalSat
        self.trustedSpendableSat = response.trustedSpendableSat
        self.immatureSat = response.immatureSat
        self.trustedPendingSat = response.trustedPendingSat
        self.untrustedPendingSat = response.untrustedPendingSat
        self.confirmedSat = response.confirmedSat
        self.lastUpdated = Date()
    }
    
    // MARK: - Computed Properties (mirrored in OnchainBalanceResponse)
    
    /// Total balance in BTC
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
    
    /// Trusted spendable balance in BTC
    var trustedSpendableBTC: Double {
        Double(trustedSpendableSat) / 100_000_000
    }
    
    /// Confirmed balance in BTC
    var confirmedBTC: Double {
        Double(confirmedSat) / 100_000_000
    }
}
