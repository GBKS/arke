//
//  Ark_wallet_prototypeTests.swift
//  Ark wallet prototypeTests
//
//  Created by Christoph on 10/16/25.
//

import Testing
import SwiftData
import Foundation
@testable import Ark_wallet_prototype

struct Ark_wallet_prototypeTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

@Suite("ArkBalance Unified Model Tests")
struct ArkBalancePersistenceTests {
    
    @Test("ArkBalanceModel unified model functionality")
    func arkBalanceModelUnifiedFunctionality() async throws {
        // Create ArkBalanceModel (now unified for both API and persistence)
        let arkBalance = ArkBalanceModel(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000
        )
        
        // Verify basic properties
        #expect(arkBalance.spendableSat == 100000)
        #expect(arkBalance.pendingLightningSendSat == 5000)
        #expect(arkBalance.pendingInRoundSat == 10000)
        #expect(arkBalance.pendingExitSat == 2000)
        #expect(arkBalance.pendingBoardSat == 3000)
        #expect(arkBalance.id == "ark_balance")
        
        // Verify computed properties work
        #expect(arkBalance.totalPendingSat == 20000)
        #expect(arkBalance.totalSat == 120000)
        #expect(arkBalance.spendableBTC == 0.001)
        #expect(arkBalance.totalBTC == 0.0012)
        
        // Verify BTC conversions for individual pending amounts
        #expect(arkBalance.pendingLightningSendBTC == 0.00005)
        #expect(arkBalance.pendingInRoundBTC == 0.0001)
        #expect(arkBalance.pendingExitBTC == 0.00002)
        #expect(arkBalance.pendingBoardBTC == 0.00003)
        #expect(arkBalance.totalPendingBTC == 0.0002)
    }
    
    @Test("ArkBalanceModel cache validity")
    func arkBalanceModelCacheValidity() async throws {
        // Create fresh balance
        let freshBalance = ArkBalanceModel(
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
        let oldBalance = ArkBalanceModel(
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
    
    @Test("ArkBalanceModel update functionality")
    func arkBalanceModelUpdate() async throws {
        // Create initial balance
        let arkBalance = ArkBalanceModel(
            spendableSat: 100000,
            pendingLightningSendSat: 5000,
            pendingInRoundSat: 10000,
            pendingExitSat: 2000,
            pendingBoardSat: 3000
        )
        
        let initialDate = arkBalance.lastUpdated
        
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
        
        // Update balance
        arkBalance.update(from: newBalance)
        
        // Verify update
        #expect(arkBalance.spendableSat == 200000)
        #expect(arkBalance.pendingLightningSendSat == 10000)
        #expect(arkBalance.pendingInRoundSat == 20000)
        #expect(arkBalance.pendingExitSat == 4000)
        #expect(arkBalance.pendingBoardSat == 6000)
        #expect(arkBalance.lastUpdated > initialDate)
    }
    
    @Test("ArkBalanceModel Codable functionality")
    func arkBalanceModelCodable() async throws {
        // Test JSON decoding (simulating API response)
        let jsonData = """
        {
            "spendable_sat": 150000,
            "pending_lightning_send_sat": 8000,
            "pending_in_round_sat": 12000,
            "pending_exit_sat": 3000,
            "pending_board_sat": 4500
        }
        """.data(using: .utf8)!
        
        let decodedBalance = try JSONDecoder().decode(ArkBalanceModel.self, from: jsonData)
        
        // Verify decoded values
        #expect(decodedBalance.spendableSat == 150000)
        #expect(decodedBalance.pendingLightningSendSat == 8000)
        #expect(decodedBalance.pendingInRoundSat == 12000)
        #expect(decodedBalance.pendingExitSat == 3000)
        #expect(decodedBalance.pendingBoardSat == 4500)
        #expect(decodedBalance.id == "ark_balance")
        #expect(decodedBalance.totalSat == 177500)
        
        // Test encoding back to JSON
        let encodedData = try JSONEncoder().encode(decodedBalance)
        let reDecodedBalance = try JSONDecoder().decode(ArkBalanceModel.self, from: encodedData)
        
        // Verify round-trip encoding/decoding
        #expect(reDecodedBalance.spendableSat == decodedBalance.spendableSat)
        #expect(reDecodedBalance.pendingLightningSendSat == decodedBalance.pendingLightningSendSat)
        #expect(reDecodedBalance.pendingInRoundSat == decodedBalance.pendingInRoundSat)
        #expect(reDecodedBalance.pendingExitSat == decodedBalance.pendingExitSat)
        #expect(reDecodedBalance.pendingBoardSat == decodedBalance.pendingBoardSat)
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
