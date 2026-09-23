//
//  TransactionDeletionBlastRadiusTests.swift
//  ArkéTests
//
//  Deleting a PersistentTransaction is never a local, reversible act. The row
//  is CloudKit-mirrored, and it cascades to TransactionTagAssignment and
//  TransactionContactAssignment (PersistentTransaction.swift) — so a bulk
//  delete from any device-scoped code path destroys the account's transaction
//  rows AND every tag and contact assignment the user ever made, on every
//  device. The transactions come back on the next refresh (re-upserted from
//  bark movements); the assignments do not, because bark knows nothing about
//  tags and contacts.
//
//  That is what a local-only wallet deletion on a secondary device did until
//  2026-09-23: WalletDataCleanupService correctly skipped all cloud data, and
//  then WalletManager.deleteWallet() → resetManagerState() bulk-deleted the
//  transactions anyway, blanking the primary's activity list.
//
//  These tests pin the blast radius, not the call site — they exist so that the
//  next person tempted to add a "clear all transactions" helper to a service
//  sees what it takes with it. Bulk deletion belongs to
//  WalletDataCleanupService alone, on a full wipe (Launch_Sequence_Contract
//  rule 23).
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

@Suite("Transaction Deletion Blast Radius")
@MainActor
struct TransactionDeletionBlastRadiusTests {

    // MARK: - Setup

    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistentTransaction.self,
            PersistentTag.self,
            TransactionTagAssignment.self,
            PersistentContact.self,
            TransactionContactAssignment.self,
            PersistentContactAddress.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func makeTransaction(txid: String) -> PersistentTransaction {
        PersistentTransaction(
            txid: txid,
            movementId: nil,
            type: .received,
            amount: 1000,
            date: Date(),
            status: .confirmed,
            address: nil
        )
    }

    // MARK: - Cascade

    @Test("Deleting a transaction destroys its tag assignment")
    func deletingTransactionCascadesToTagAssignment() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let tag = PersistentTag(name: "Groceries", colorHex: "#C33C2D", emoji: "🏷️")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionTagAssignment>()).count == 1)

        context.delete(transaction)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionTagAssignment>()).isEmpty)
        // The tag itself survives — only the user's assignment of it is gone,
        // which is the part no refresh can rebuild.
        #expect(try context.fetch(FetchDescriptor<PersistentTag>()).count == 1)
    }

    @Test("Deleting a transaction destroys its contact assignment")
    func deletingTransactionCascadesToContactAssignment() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let contact = PersistentContact(cachedName: "Alice")
        context.insert(transaction)
        context.insert(contact)
        context.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionContactAssignment>()).count == 1)

        context.delete(transaction)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionContactAssignment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentContact>()).count == 1)
    }

    @Test("A bulk delete takes every assignment in the store with it")
    func bulkDeleteWipesAllAssignments() throws {
        let context = ModelContext(try createTestContainer())

        let tag = PersistentTag(name: "Groceries", colorHex: "#C33C2D", emoji: "🏷️")
        let contact = PersistentContact(cachedName: "Alice")
        context.insert(tag)
        context.insert(contact)

        for index in 0..<5 {
            let transaction = makeTransaction(txid: "movement_\(index)")
            context.insert(transaction)
            context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
            context.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
        }
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionTagAssignment>()).count == 5)
        #expect(try context.fetch(FetchDescriptor<TransactionContactAssignment>()).count == 5)

        // The shape of the removed `clearTransactionModels()`: fetch all, delete all.
        for transaction in try context.fetch(FetchDescriptor<PersistentTransaction>()) {
            context.delete(transaction)
        }
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TransactionTagAssignment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TransactionContactAssignment>()).isEmpty)
    }

    // MARK: - Coverage contract

    @Test("Both assignment models are declared cascade-wiped, not directly wiped")
    func assignmentsAreDeclaredAsCascades() {
        let cascade = WalletWipeCoverage.cascadeWiped.map { ObjectIdentifier($0) }
        #expect(cascade.contains(ObjectIdentifier(TransactionTagAssignment.self)))
        #expect(cascade.contains(ObjectIdentifier(TransactionContactAssignment.self)))

        // Cascade-wiped means "no code deletes these directly" — they can only
        // disappear with their owning transaction, which is why deleting
        // transactions outside a full wipe is forbidden.
        let direct = WalletWipeCoverage.directlyWiped.map { ObjectIdentifier($0) }
        #expect(!direct.contains(ObjectIdentifier(TransactionTagAssignment.self)))
        #expect(!direct.contains(ObjectIdentifier(TransactionContactAssignment.self)))
    }
}
