//
//  PersistedArkBalance.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/24/25.
//

import Foundation
import SwiftData

@Model
class PersistedArkBalance {
    var id: String
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    var lastUpdated: Date
    
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
    
    /// Convert to UI model for compatibility with existing code
    var arkBalanceModel: ArkBalanceModel {
        return ArkBalanceModel(
            spendableSat: spendableSat,
            pendingLightningSendSat: pendingLightningSendSat,
            pendingInRoundSat: pendingInRoundSat,
            pendingExitSat: pendingExitSat,
            pendingBoardSat: pendingBoardSat
        )
    }
    
    /// Create from existing ArkBalanceModel
    static func from(_ arkBalance: ArkBalanceModel) -> PersistedArkBalance {
        return PersistedArkBalance(
            spendableSat: arkBalance.spendableSat,
            pendingLightningSendSat: arkBalance.pendingLightningSendSat,
            pendingInRoundSat: arkBalance.pendingInRoundSat,
            pendingExitSat: arkBalance.pendingExitSat,
            pendingBoardSat: arkBalance.pendingBoardSat
        )
    }
    
    /// Check if the cached balance is still valid (within 5 minutes)
    var isValid: Bool {
        let cacheValidityDuration: TimeInterval = 5 * 60 // 5 minutes
        return Date().timeIntervalSince(lastUpdated) < cacheValidityDuration
    }
    
    /// Update with new balance data
    func update(with arkBalance: ArkBalanceModel) {
        self.spendableSat = arkBalance.spendableSat
        self.pendingLightningSendSat = arkBalance.pendingLightningSendSat
        self.pendingInRoundSat = arkBalance.pendingInRoundSat
        self.pendingExitSat = arkBalance.pendingExitSat
        self.pendingBoardSat = arkBalance.pendingBoardSat
        self.lastUpdated = Date()
    }
}