//
//  OnchainBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//  Migrated by Assistant on 10/29/25 - Unified with PersistedOnchainBalance
//

import Foundation
import SwiftData

/// Unified Onchain balance model that serves both API decoding and SwiftData persistence
/// 
/// This model combines what was previously OnchainBalanceModel (API) and PersistedOnchainBalance (persistence)
/// into a single class following the transaction architecture migration pattern.
///
/// Key features:
/// - SwiftData @Model for direct UI observation and persistence
/// - Codable for API response decoding (id and lastUpdated excluded from API)
/// - Singleton pattern with id = "onchain_balance"
/// - Built-in cache validity and update methods
/// - All existing computed properties preserved
@Model
class OnchainBalanceModel: Codable, @unchecked Sendable {
    var id: String
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    var lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case totalSat = "total_sat"
        case trustedSpendableSat = "trusted_spendable_sat"
        case immatureSat = "immature_sat"
        case trustedPendingSat = "trusted_pending_sat"
        case untrustedPendingSat = "untrusted_pending_sat"
        case confirmedSat = "confirmed_sat"
        // Note: id and lastUpdated are not part of API response
    }
    
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
    
    // MARK: - Codable Implementation
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = "onchain_balance"
        self.totalSat = try container.decode(Int.self, forKey: .totalSat)
        self.trustedSpendableSat = try container.decode(Int.self, forKey: .trustedSpendableSat)
        self.immatureSat = try container.decode(Int.self, forKey: .immatureSat)
        self.trustedPendingSat = try container.decode(Int.self, forKey: .trustedPendingSat)
        self.untrustedPendingSat = try container.decode(Int.self, forKey: .untrustedPendingSat)
        self.confirmedSat = try container.decode(Int.self, forKey: .confirmedSat)
        self.lastUpdated = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalSat, forKey: .totalSat)
        try container.encode(trustedSpendableSat, forKey: .trustedSpendableSat)
        try container.encode(immatureSat, forKey: .immatureSat)
        try container.encode(trustedPendingSat, forKey: .trustedPendingSat)
        try container.encode(untrustedPendingSat, forKey: .untrustedPendingSat)
        try container.encode(confirmedSat, forKey: .confirmedSat)
        // Note: id and lastUpdated are not encoded for API
    }
    
    // MARK: - Persistence Methods
    
    /// Check if the cached balance is still valid (within 5 minutes)
    var isValid: Bool {
        let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
        return Date().timeIntervalSince(lastUpdated) < cacheValidityDuration
    }
    
    /// Update with new balance data from API response
    func update(from decodedBalance: OnchainBalanceModel) {
        self.totalSat = decodedBalance.totalSat
        self.trustedSpendableSat = decodedBalance.trustedSpendableSat
        self.immatureSat = decodedBalance.immatureSat
        self.trustedPendingSat = decodedBalance.trustedPendingSat
        self.untrustedPendingSat = decodedBalance.untrustedPendingSat
        self.confirmedSat = decodedBalance.confirmedSat
        self.lastUpdated = Date()
    }
    
    // MARK: - Computed Properties
    
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
