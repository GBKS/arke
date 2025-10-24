//
//  Ark_wallet_prototypeTests.swift
//  Ark wallet prototypeTests
//
//  Created by Christoph on 10/16/25.
//

import Testing
import SwiftData
@testable import Ark_wallet_prototype

struct Ark_wallet_prototypeTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

@Suite("ArkBalance Persistence Tests")
struct ArkBalancePersistenceTests {
    
    @Test("PersistedArkBalance creation and conversion")
    func persistedArkBalanceConversion() async throws {
        // Create sample ArkBalanceModel
        let originalBalance = ArkBalanceModel(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000
        )
        
        // Convert to persisted model
        let persistedBalance = PersistedArkBalance.from(originalBalance)
        
        // Verify conversion
        #expect(persistedBalance.spendableSat == 100000)
        #expect(persistedBalance.pendingLightningSendSat == 5000)
        #expect(persistedBalance.pendingInRoundSat == 10000)
        #expect(persistedBalance.pendingExitSat == 2000)
        #expect(persistedBalance.pendingBoardSat == 3000)
        #expect(persistedBalance.id == "ark_balance")
        
        // Convert back to model
        let convertedBalance = persistedBalance.arkBalanceModel
        
        // Verify round-trip conversion
        #expect(convertedBalance.spendableSat == originalBalance.spendableSat)
        #expect(convertedBalance.pendingLightningSendSat == originalBalance.pendingLightningSendSat)
        #expect(convertedBalance.pendingInRoundSat == originalBalance.pendingInRoundSat)
        #expect(convertedBalance.pendingExitSat == originalBalance.pendingExitSat)
        #expect(convertedBalance.pendingBoardSat == originalBalance.pendingBoardSat)
        
        // Verify computed properties work
        #expect(convertedBalance.totalPendingSat == 20000)
        #expect(convertedBalance.totalSat == 120000)
    }
    
    @Test("PersistedArkBalance cache validity")
    func persistedArkBalanceCacheValidity() async throws {
        // Create fresh balance
        let freshBalance = PersistedArkBalance(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000
        )
        
        // Should be valid when just created
        #expect(freshBalance.isValid == true)
        
        // Create old balance (6 minutes ago)
        let oldDate = Date().addingTimeInterval(-6 * 60)
        let oldBalance = PersistedArkBalance(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000,
            lastUpdated: oldDate
        )
        
        // Should be invalid when older than 5 minutes
        #expect(oldBalance.isValid == false)
    }
    
    @Test("PersistedArkBalance update functionality")
    func persistedArkBalanceUpdate() async throws {
        // Create initial balance
        let persistedBalance = PersistedArkBalance(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000
        )
        
        let initialDate = persistedBalance.lastUpdated
        
        // Wait a tiny bit to ensure timestamp changes
        try await Task.sleep(nanoseconds: 1_000_000) // 1 millisecond
        
        // Create new balance data
        let newBalance = ArkBalanceModel(
            spendableSat: 200000,
            pendingLightningSendSat: 10000,
            pendingInRoundSat: 20000,
            pendingExitSat: 4000,
            pendingBoardSat: 6000
        )
        
        // Update persisted balance
        persistedBalance.update(with: newBalance)
        
        // Verify update
        #expect(persistedBalance.spendableSat == 200000)
        #expect(persistedBalance.pendingLightningSendSat == 10000)
        #expect(persistedBalance.pendingInRoundSat == 20000)
        #expect(persistedBalance.pendingExitSat == 4000)
        #expect(persistedBalance.pendingBoardSat == 6000)
        #expect(persistedBalance.lastUpdated > initialDate)
    }
}

@Suite("OnchainBalance Persistence Tests")
struct OnchainBalancePersistenceTests {
    
    @Test("PersistedOnchainBalance creation and conversion")
    func persistedOnchainBalanceConversion() async throws {
        // Create sample OnchainBalanceModel
        let originalBalance = OnchainBalanceModel(
            totalSat: 500000,
            trustedSpendableSat: 400000,
            immatureSat: 50000,
            trustedPendingSat: 30000,
            untrustedPendingSat: 20000,
            confirmedSat: 450000
        )
        
        // Convert to persisted model
        let persistedBalance = PersistedOnchainBalance.from(originalBalance)
        
        // Verify conversion
        #expect(persistedBalance.totalSat == 500000)
        #expect(persistedBalance.trustedSpendableSat == 400000)
        #expect(persistedBalance.immatureSat == 50000)
        #expect(persistedBalance.trustedPendingSat == 30000)
        #expect(persistedBalance.untrustedPendingSat == 20000)
        #expect(persistedBalance.confirmedSat == 450000)
        #expect(persistedBalance.id == "onchain_balance")
        
        // Convert back to model
        let convertedBalance = persistedBalance.onchainBalanceModel
        
        // Verify round-trip conversion
        #expect(convertedBalance.totalSat == originalBalance.totalSat)
        #expect(convertedBalance.trustedSpendableSat == originalBalance.trustedSpendableSat)
        #expect(convertedBalance.immatureSat == originalBalance.immatureSat)
        #expect(convertedBalance.trustedPendingSat == originalBalance.trustedPendingSat)
        #expect(convertedBalance.untrustedPendingSat == originalBalance.untrustedPendingSat)
        #expect(convertedBalance.confirmedSat == originalBalance.confirmedSat)
        
        // Verify computed properties work
        #expect(convertedBalance.totalBTC == 0.005)
        #expect(convertedBalance.trustedSpendableBTC == 0.004)
        #expect(convertedBalance.confirmedBTC == 0.0045)
    }
    
    @Test("PersistedOnchainBalance cache validity")
    func persistedOnchainBalanceCacheValidity() async throws {
        // Create fresh balance
        let freshBalance = PersistedOnchainBalance(
            totalSat: 500000,
            trustedSpendableSat: 400000,
            immatureSat: 50000,
            trustedPendingSat: 30000,
            untrustedPendingSat: 20000,
            confirmedSat: 450000
        )
        
        // Should be valid when just created
        #expect(freshBalance.isValid == true)
        
        // Create old balance (6 minutes ago)
        let oldDate = Date().addingTimeInterval(-6 * 60)
        let oldBalance = PersistedOnchainBalance(
            totalSat: 500000,
            trustedSpendableSat: 400000,
            immatureSat: 50000,
            trustedPendingSat: 30000,
            untrustedPendingSat: 20000,
            confirmedSat: 450000,
            lastUpdated: oldDate
        )
        
        // Should be invalid when older than 5 minutes
        #expect(oldBalance.isValid == false)
    }
    
    @Test("PersistedOnchainBalance update functionality")
    func persistedOnchainBalanceUpdate() async throws {
        // Create initial balance
        let persistedBalance = PersistedOnchainBalance(
            totalSat: 500000,
            trustedSpendableSat: 400000,
            immatureSat: 50000,
            trustedPendingSat: 30000,
            untrustedPendingSat: 20000,
            confirmedSat: 450000
        )
        
        let initialDate = persistedBalance.lastUpdated
        
        // Wait a tiny bit to ensure timestamp changes
        try await Task.sleep(nanoseconds: 1_000_000) // 1 millisecond
        
        // Create new balance data
        let newBalance = OnchainBalanceModel(
            totalSat: 750000,
            trustedSpendableSat: 600000,
            immatureSat: 75000,
            trustedPendingSat: 50000,
            untrustedPendingSat: 25000,
            confirmedSat: 675000
        )
        
        // Update persisted balance
        persistedBalance.update(with: newBalance)
        
        // Verify update
        #expect(persistedBalance.totalSat == 750000)
        #expect(persistedBalance.trustedSpendableSat == 600000)
        #expect(persistedBalance.immatureSat == 75000)
        #expect(persistedBalance.trustedPendingSat == 50000)
        #expect(persistedBalance.untrustedPendingSat == 25000)
        #expect(persistedBalance.confirmedSat == 675000)
        #expect(persistedBalance.lastUpdated > initialDate)
    }
}
