//
//  TransactionBridgingEquivalenceTests.swift
//  Arke
//
//  The refresh path bulk-bridges persistent transactions through one
//  TransactionMetadataSnapshot per pass instead of the single-arg
//  TransactionModel(from:) (which runs a fetch pair per transaction plus a
//  full aggregation per contact — the 2026-09-24 fetch-storm finding). These
//  pin that the bulk path produces the same models, and that the row-weight
//  ContactModel conversion differs from the full one only in the aggregates.
//

import Testing
import SwiftData
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Transaction Bridging Equivalence")
@MainActor
struct TransactionBridgingEquivalenceTests {

    // MARK: - Setup

    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistentTransaction.self,
            PersistentTag.self,
            TransactionTagAssignment.self,
            PersistentContact.self,
            TransactionContactAssignment.self,
            PersistentContactAddress.self,
            PendingPaymentMetadata.self,
            PendingTagAssignment.self,
            UserProfile.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func makeTransaction(txid: String, amount: Int = 1000, daysAgo: Double = 0) -> PersistentTransaction {
        PersistentTransaction(
            txid: txid,
            movementId: nil,
            type: .received,
            amount: amount,
            date: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400),
            status: .confirmed,
            address: nil
        )
    }

    /// Seeds 3 transactions: one with a shared tag + contact, one with only
    /// the tag, one bare.
    private func seedStore(context: ModelContext) throws {
        let shared = PersistentTag(name: "Groceries", colorHex: "#C33C2D", emoji: "🛒")
        let contact = PersistentContact(cachedName: "Alice")
        let address = PersistentContactAddress(
            id: UUID(), address: "tb1qexample", normalizedAddress: "tb1qexample",
            format: .bitcoin, label: nil, isPrimary: true
        )
        address.contact = contact

        let first = makeTransaction(txid: "movement_1", daysAgo: 0)
        let second = makeTransaction(txid: "movement_2", daysAgo: 1)
        let bare = makeTransaction(txid: "movement_3", daysAgo: 2)

        for model in [first, second, bare] { context.insert(model) }
        context.insert(shared)
        context.insert(contact)
        context.insert(address)
        context.insert(TransactionTagAssignment(tag: shared, transaction: first))
        context.insert(TransactionTagAssignment(tag: shared, transaction: second))
        context.insert(TransactionContactAssignment(contact: contact, transaction: first))
        try context.save()
    }

    // MARK: - Equivalence

    @Test("The bulk-bridged service output matches per-item bridging")
    func bulkMatchesPerItem() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        try seedStore(context: context)

        let service = TransactionService(wallet: MockBarkWallet(), taskManager: TaskDeduplicationManager())
        service.modelContext = context

        let bulk = service.transactions

        let descriptor = FetchDescriptor<PersistentTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let direct = try context.fetch(descriptor).map { TransactionModel(from: $0) }

        #expect(bulk.map(\.txid) == direct.map(\.txid))
        #expect(bulk.map(\.amount) == direct.map(\.amount))
        #expect(bulk.map(\.status) == direct.map(\.status))
        #expect(bulk.map { $0.associatedTags.map(\.id) } == direct.map { $0.associatedTags.map(\.id) })
        #expect(bulk.map { $0.associatedContacts.map(\.id) } == direct.map { $0.associatedContacts.map(\.id) })
    }

    @Test("Row-weight contact conversion differs only in the aggregates")
    func rowWeightContactEquivalence() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        try seedStore(context: context)

        let contact = try #require(try context.fetch(FetchDescriptor<PersistentContact>()).first)

        let full = ContactModel(from: contact)
        let row = ContactModel(rowFrom: contact)

        #expect(row.id == full.id)
        #expect(row.cachedName == full.cachedName)
        #expect(row.contactType == full.contactType)
        #expect(row.addresses.map(\.id) == full.addresses.map(\.id))

        // The whole point of the row-weight init: no aggregation
        #expect(row.transactionCount == nil)
        #expect(row.sentAmount == nil)
        #expect(row.receivedAmount == nil)
        #expect(full.transactionCount == 1)
    }

    // MARK: - Measurement (non-asserting; CI variance)

    @Test("Bulk bridging cost stays flat under a frequent contact")
    func bridgingCostMeasurement() throws {
        // 120 transactions, one contact assigned to 100 of them: the old
        // per-item path aggregated that contact's 100 transactions once per
        // appearance (O(M²)); the snapshot converts it once, row-weight.
        // Printed, not asserted — timings vary too much across machines.
        let container = try createTestContainer()
        let context = ModelContext(container)

        let contact = PersistentContact(cachedName: "Frequent")
        context.insert(contact)
        for index in 0..<120 {
            let transaction = makeTransaction(txid: "movement_\(index)", daysAgo: Double(index))
            context.insert(transaction)
            if index < 100 {
                context.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
            }
        }
        try context.save()

        let service = TransactionService(wallet: MockBarkWallet(), taskManager: TaskDeduplicationManager())
        service.modelContext = context

        let clock = ContinuousClock()
        let bulkTime = clock.measure { _ = service.transactions }

        let descriptor = FetchDescriptor<PersistentTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let rows = try context.fetch(descriptor)
        let perItemTime = clock.measure { _ = rows.map { TransactionModel(from: $0) } }

        print("📏 [BridgingCost] bulk: \(bulkTime), per-item: \(perItemTime) (120 tx, 1 contact × 100 assignments)")
        #expect(service.transactions.count == 120)
    }
}
