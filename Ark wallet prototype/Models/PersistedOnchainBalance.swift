//
//  PersistedOnchainBalance.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/24/25.
//

import Foundation
import SwiftData

@Model
class PersistedOnchainBalance {
    var id: String
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    var lastUpdated: Date
    
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
    
    /// Convert to UI model for compatibility with existing code
    var onchainBalanceModel: OnchainBalanceModel {
        return OnchainBalanceModel(
            totalSat: totalSat,
            trustedSpendableSat: trustedSpendableSat,
            immatureSat: immatureSat,
            trustedPendingSat: trustedPendingSat,
            untrustedPendingSat: untrustedPendingSat,
            confirmedSat: confirmedSat
        )
    }
    
    /// Create from existing OnchainBalanceModel
    static func from(_ onchainBalance: OnchainBalanceModel) -> PersistedOnchainBalance {
        return PersistedOnchainBalance(
            totalSat: onchainBalance.totalSat,
            trustedSpendableSat: onchainBalance.trustedSpendableSat,
            immatureSat: onchainBalance.immatureSat,
            trustedPendingSat: onchainBalance.trustedPendingSat,
            untrustedPendingSat: onchainBalance.untrustedPendingSat,
            confirmedSat: onchainBalance.confirmedSat
        )
    }
    
    /// Check if the cached balance is still valid (within 5 minutes)
    var isValid: Bool {
        let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
        return Date().timeIntervalSince(lastUpdated) < cacheValidityDuration
    }
    
    /// Update with new balance data
    func update(with onchainBalance: OnchainBalanceModel) {
        self.totalSat = onchainBalance.totalSat
        self.trustedSpendableSat = onchainBalance.trustedSpendableSat
        self.immatureSat = onchainBalance.immatureSat
        self.trustedPendingSat = onchainBalance.trustedPendingSat
        self.untrustedPendingSat = onchainBalance.untrustedPendingSat
        self.confirmedSat = onchainBalance.confirmedSat
        self.lastUpdated = Date()
    }
}