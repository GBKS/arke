//
//  PendingMetadataMatchingTests.swift
//  Arke
//
//  Phase 0: Send Metadata Enhancement
//  Tests for pending payment metadata matching algorithm
//

import Testing
import SwiftData
import Foundation
@testable import Shared

@Suite("Pending Metadata Matching Tests")
struct PendingMetadataMatchingTests {
    
    // MARK: - Test Setup
    
    /// Create an in-memory model container for testing
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistentTransaction.self,
            PendingPaymentMetadata.self,
            PendingTagAssignment.self,
            PersistentTag.self,
            PersistentContact.self,
            TransactionTagAssignment.self,
            TransactionContactAssignment.self
        ])
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        
        return try ModelContainer(for: schema, configurations: configuration)
    }
    
    /// Create a mock wallet for TransactionService
    private class MockWallet: BarkWalletProtocol {
        func getMovements() async throws -> String { return "[]" }
        func sendToAddress(address: String, amountSat: UInt64, feeRateSatPerVbyte: UInt64?) async throws -> String { return "" }
        func receivePayment() async throws -> String { return "" }
        func getBalance() async throws -> String { return "{}" }
        func getArkConfig() async throws -> String { return "{}" }
        func getBoardingAddress() async throws -> String { return "" }
        func getAllVTXOs() async throws -> String { return "[]" }
        func getOnchainBalance() async throws -> String { return "{}" }
        func refreshOnchainWallet(stopGap: UInt32?) async throws {}
        func unilateralExit() async throws -> String { return "" }
        func getUnilateralExits() async throws -> String { return "[]" }
        func claimUnilateralExits() async throws -> String { return "" }
        func getOffboardingAddress() async throws -> String { return "" }
    }
    
    // MARK: - Priority 1: Payment Hash Matching (Lightning)
    
    @Test("Payment hash match - exact match found")
    func testPaymentHashExactMatch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        // Create pending metadata with payment hash
        let paymentHash = "abc123def456"
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: paymentHash,
            destinationAddress: "lnbc100...",
            amountSats: 1000,
            paymentType: "lightning",
            timestamp: Date()
        )
        context.insert(pendingMetadata)
        
        // Create transaction with same payment hash
        let transaction = PersistentTransaction(
            txid: "movement_123",
            movementId: 123,
            type: .sent,
            amount: 1000,
            date: Date(),
            status: .confirmed,
            address: "lnbc100...",
            paymentHash: paymentHash
        )
        context.insert(transaction)
        
        // Create TransactionService and apply metadata
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        // Apply pending metadata
        service.applyPendingMetadata(to: transaction)
        
        // Verify metadata was deleted after match
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.isEmpty, "Pending metadata should be deleted after match")
    }
    
    @Test("Payment hash match - case sensitivity")
    func testPaymentHashCaseSensitive() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        // Create pending metadata with lowercase hash
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: "abc123",
            destinationAddress: "lnbc100...",
            amountSats: 1000,
            paymentType: "lightning"
        )
        context.insert(pendingMetadata)
        
        // Create transaction with uppercase hash (should NOT match)
        let transaction = PersistentTransaction(
            txid: "movement_123",
            movementId: 123,
            type: .sent,
            amount: 1000,
            date: Date(),
            status: .confirmed,
            address: "lnbc100...",
            paymentHash: "ABC123"
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify metadata was NOT deleted (no match)
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.count == 1, "Pending metadata should remain (no case-insensitive match for payment hash)")
    }
    
    // MARK: - Priority 2: Timestamp Matching
    
    @Test("Timestamp match - exact match within window")
    func testTimestampExactMatch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let now = Date()
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create pending metadata
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 50000,
            paymentType: "ark",
            timestamp: now
        )
        pendingMetadata.notes = "Test payment"
        context.insert(pendingMetadata)
        
        // Create transaction at same time
        let transaction = PersistentTransaction(
            txid: "movement_456",
            movementId: 456,
            type: .sent,
            amount: 50000,
            date: now,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify notes were applied
        #expect(transaction.notes == "Test payment", "Notes should be applied from pending metadata")
        
        // Verify metadata was deleted
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.isEmpty, "Pending metadata should be deleted after match")
    }
    
    @Test("Timestamp match - within 5 minute window")
    func testTimestampWithinWindow() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let metadataTime = Date()
        let transactionTime = metadataTime.addingTimeInterval(240) // 4 minutes later
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create pending metadata
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 25000,
            paymentType: "onchain",
            timestamp: metadataTime
        )
        context.insert(pendingMetadata)
        
        // Create transaction 4 minutes later
        let transaction = PersistentTransaction(
            txid: "movement_789",
            movementId: 789,
            type: .sent,
            amount: 25000,
            date: transactionTime,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify match occurred
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.isEmpty, "Should match within 5 minute window")
    }
    
    @Test("Timestamp match - outside window")
    func testTimestampOutsideWindow() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let metadataTime = Date()
        let transactionTime = metadataTime.addingTimeInterval(360) // 6 minutes later (outside 5 min window)
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create pending metadata
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 30000,
            paymentType: "ark",
            timestamp: metadataTime
        )
        context.insert(pendingMetadata)
        
        // Create transaction 6 minutes later
        let transaction = PersistentTransaction(
            txid: "movement_999",
            movementId: 999,
            type: .sent,
            amount: 30000,
            date: transactionTime,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify no match occurred
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.count == 1, "Should not match outside time window")
    }
    
    @Test("Timestamp match - amount mismatch")
    func testTimestampAmountMismatch() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let now = Date()
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create pending metadata with 10000 sats
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 10000,
            paymentType: "ark",
            timestamp: now
        )
        context.insert(pendingMetadata)
        
        // Create transaction with 20000 sats (different amount)
        let transaction = PersistentTransaction(
            txid: "movement_111",
            movementId: 111,
            type: .sent,
            amount: 20000,
            date: now,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify no match occurred
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.count == 1, "Should not match with different amounts")
    }
    
    @Test("Timestamp match - address case insensitive")
    func testTimestampAddressCaseInsensitive() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let now = Date()
        
        // Create pending metadata with lowercase address
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            amountSats: 15000,
            paymentType: "onchain",
            timestamp: now
        )
        context.insert(pendingMetadata)
        
        // Create transaction with uppercase address
        let transaction = PersistentTransaction(
            txid: "movement_222",
            movementId: 222,
            type: .sent,
            amount: 15000,
            date: now,
            status: .confirmed,
            address: "BC1QXY2KGDYGJRSQTZQ2N0YRF2493P83KKFJHX0WLH"
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify match occurred (case-insensitive)
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.isEmpty, "Should match addresses case-insensitively")
    }
    
    // MARK: - Multiple Matches
    
    @Test("Multiple candidates - closest timestamp wins")
    func testMultipleCandidatesClosestWins() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let transactionTime = Date()
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create first pending metadata 60 seconds before transaction
        let metadata1 = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 5000,
            paymentType: "ark",
            timestamp: transactionTime.addingTimeInterval(-60)
        )
        metadata1.notes = "First metadata"
        context.insert(metadata1)
        
        // Create second pending metadata 10 seconds before transaction (closer)
        let metadata2 = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 5000,
            paymentType: "ark",
            timestamp: transactionTime.addingTimeInterval(-10)
        )
        metadata2.notes = "Second metadata (closer)"
        context.insert(metadata2)
        
        // Create transaction
        let transaction = PersistentTransaction(
            txid: "movement_333",
            movementId: 333,
            type: .sent,
            amount: 5000,
            date: transactionTime,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify the closer metadata was used
        #expect(transaction.notes == "Second metadata (closer)", "Should use closest timestamp match")
        
        // Verify one metadata remains (the farther one)
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.count == 1, "One metadata should remain")
        #expect(remainingMetadata.first?.notes == "First metadata", "Farther metadata should remain")
    }
    
    // MARK: - Metadata Transfer
    
    @Test("Metadata transfer - notes, tags, and contact")
    func testFullMetadataTransfer() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        let now = Date()
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Create tag
        let tag = PersistentTag(name: "Shopping", colorHex: "#FF0000", emoji: "🛒")
        context.insert(tag)
        
        // Create contact
        let contact = PersistentContact(
            name: "Alice",
            colorHex: "#00FF00",
            emoji: "👤",
            notes: nil,
            type: .manual
        )
        context.insert(contact)
        
        // Create pending metadata with notes, tag, and contact
        let pendingMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: address,
            amountSats: 8000,
            paymentType: "lightning",
            timestamp: now
        )
        pendingMetadata.notes = "Coffee and snacks"
        pendingMetadata.contact = contact
        
        let tagAssignment = PendingTagAssignment(tag: tag, pendingMetadata: pendingMetadata)
        context.insert(tagAssignment)
        context.insert(pendingMetadata)
        
        // Create transaction
        let transaction = PersistentTransaction(
            txid: "movement_444",
            movementId: 444,
            type: .sent,
            amount: 8000,
            date: now,
            status: .confirmed,
            address: address
        )
        context.insert(transaction)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        service.applyPendingMetadata(to: transaction)
        
        // Verify all metadata was transferred
        #expect(transaction.notes == "Coffee and snacks", "Notes should be transferred")
        #expect(transaction.hasContacts, "Contact should be assigned")
        #expect(transaction.associatedContacts.first?.name == "Alice", "Correct contact should be assigned")
        #expect(transaction.hasTags, "Tag should be assigned")
        #expect(transaction.associatedTags.first?.name == "Shopping", "Correct tag should be assigned")
    }
    
    // MARK: - Cleanup
    
    @Test("Cleanup - old unmatched metadata deleted")
    func testCleanupOldMetadata() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        
        // Create old pending metadata (25 hours ago)
        let oldMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: "bc1q...",
            amountSats: 1000,
            paymentType: "ark",
            timestamp: Date().addingTimeInterval(-90000) // 25 hours ago
        )
        oldMetadata.createdAt = Date().addingTimeInterval(-90000)
        context.insert(oldMetadata)
        
        // Create recent pending metadata (1 hour ago)
        let recentMetadata = PendingPaymentMetadata(
            paymentHash: nil,
            destinationAddress: "bc1q...",
            amountSats: 2000,
            paymentType: "ark",
            timestamp: Date().addingTimeInterval(-3600)
        )
        recentMetadata.createdAt = Date().addingTimeInterval(-3600)
        context.insert(recentMetadata)
        
        let taskManager = TaskDeduplicationManager()
        let service = TransactionService(wallet: MockWallet(), taskManager: taskManager)
        service.setModelContext(context)
        
        // Run cleanup
        service.cleanupOldPendingMetadata()
        
        // Verify old metadata was deleted, recent remains
        let remainingMetadata = try context.fetch(FetchDescriptor<PendingPaymentMetadata>())
        #expect(remainingMetadata.count == 1, "Only recent metadata should remain")
        #expect(remainingMetadata.first?.amountSats == 2000, "Recent metadata should remain")
    }
}
