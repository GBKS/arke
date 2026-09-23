//
//  TransactionMetadataResolutionTests.swift
//  Arke
//
//  A second device crashed on launch rendering the activity list: the CloudKit
//  import deleted a TransactionTagAssignment row while the list was laying out,
//  and the transaction's already-materialized `tagAssignments` array still
//  listed it, so reading `assignment.tag` trapped with "This model instance was
//  invalidated because its backing data could no longer be found the store"
//  (2026-09-23, PersistentTransaction.associatedTags → LazyVStack layout).
//
//  These tests pin the resolution contract that replaced the relationship walk:
//  tags and contacts come from a fetch, so only rows that exist right now are
//  returned — including when another context deleted them underneath us. The
//  bulk form used by the lists (`TransactionMetadataSnapshot`) must agree with
//  the per-transaction accessors.
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

@Suite("Transaction Metadata Resolution")
@MainActor
struct TransactionMetadataResolutionTests {

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

    private func makeTag(_ name: String) -> PersistentTag {
        PersistentTag(name: name, colorHex: "#C33C2D", emoji: "🏷️")
    }

    // MARK: - Tags

    @Test("Assigned tags resolve after a save")
    func tagsResolveAfterSave() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        #expect(transaction.associatedTags.map(\.name) == ["Groceries"])
        #expect(transaction.hasTag(tag))
    }

    @Test("Assignments inserted but not yet saved are still visible")
    func tagsIncludePendingInsert() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        try context.save()

        // Auto-tagging and metadata import insert assignments and save later in
        // the batch, so resolution must reflect pending inserts.
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))

        #expect(transaction.associatedTags.map(\.name) == ["Groceries"])
    }

    @Test("Assignments deleted but not yet saved are gone")
    func tagsExcludePendingDelete() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        let assignment = TransactionTagAssignment(tag: tag, transaction: transaction)
        context.insert(assignment)
        try context.save()

        context.delete(assignment)

        #expect(transaction.associatedTags.isEmpty)
        #expect(!transaction.hasTag(tag))
    }

    @Test("An assignment deleted by another context is not resolved")
    func tagsExcludeRowDeletedByAnotherContext() throws {
        let container = try createTestContainer()
        let writer = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        writer.insert(transaction)
        writer.insert(tag)
        writer.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try writer.save()

        // The reader stands in for the main context: it materializes the
        // transaction and its relationship array, exactly as a rendered row does.
        let reader = ModelContext(container)
        let readerTransaction = try #require(
            try reader.fetch(FetchDescriptor<PersistentTransaction>()).first
        )
        #expect(readerTransaction.associatedTags.count == 1)
        #expect((readerTransaction.tagAssignments ?? []).count == 1)

        // The CloudKit import stands in here: another context deletes the row
        // the reader's cached relationship still points at.
        let assignments = try writer.fetch(FetchDescriptor<TransactionTagAssignment>())
        for assignment in assignments {
            writer.delete(assignment)
        }
        try writer.save()

        // Must neither trap nor report a tag that no longer exists.
        #expect(readerTransaction.associatedTags.isEmpty)
    }

    @Test("Tags follow assignment order, not fetch order")
    func tagOrderFollowsAssignmentDate() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let first = makeTag("Rent")
        let second = makeTag("Groceries")
        let third = makeTag("Travel")
        context.insert(transaction)
        [first, second, third].forEach { context.insert($0) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Inserted out of order on purpose
        context.insert(TransactionTagAssignment(tag: second, transaction: transaction,
                                                assignedDate: base.addingTimeInterval(60)))
        context.insert(TransactionTagAssignment(tag: third, transaction: transaction,
                                                assignedDate: base.addingTimeInterval(120)))
        context.insert(TransactionTagAssignment(tag: first, transaction: transaction,
                                                assignedDate: base))
        try context.save()

        #expect(transaction.associatedTags.map(\.name) == ["Rent", "Groceries", "Travel"])
    }

    @Test("Tags of other transactions are not mixed in")
    func tagsAreScopedToTheTransaction() throws {
        let context = ModelContext(try createTestContainer())

        let mine = makeTransaction(txid: "movement_1")
        let other = makeTransaction(txid: "movement_2")
        let mineTag = makeTag("Groceries")
        let otherTag = makeTag("Rent")
        [mine, other].forEach { context.insert($0) }
        [mineTag, otherTag].forEach { context.insert($0) }
        context.insert(TransactionTagAssignment(tag: mineTag, transaction: mine))
        context.insert(TransactionTagAssignment(tag: otherTag, transaction: other))
        try context.save()

        #expect(mine.associatedTags.map(\.name) == ["Groceries"])
        #expect(other.associatedTags.map(\.name) == ["Rent"])
        #expect(!mine.hasTag(otherTag))
    }

    // MARK: - Contacts

    @Test("Assigned contacts resolve, and a deleted assignment drops out")
    func contactsResolveAndDrop() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let contact = PersistentContact(cachedName: "Alice")
        context.insert(transaction)
        context.insert(contact)
        let assignment = TransactionContactAssignment(contact: contact, transaction: transaction)
        context.insert(assignment)
        try context.save()

        #expect(transaction.associatedContacts.map(\.cachedName) == ["Alice"])
        #expect(transaction.hasContact(contact))

        context.delete(assignment)
        try context.save()

        #expect(transaction.associatedContacts.isEmpty)
        #expect(!transaction.hasContact(contact))
    }

    @Test("A contact assignment deleted by another context is not resolved")
    func contactsExcludeRowDeletedByAnotherContext() throws {
        let container = try createTestContainer()
        let writer = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let contact = PersistentContact(cachedName: "Alice")
        writer.insert(transaction)
        writer.insert(contact)
        writer.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
        try writer.save()

        let reader = ModelContext(container)
        let readerTransaction = try #require(
            try reader.fetch(FetchDescriptor<PersistentTransaction>()).first
        )
        #expect(readerTransaction.associatedContacts.count == 1)

        for assignment in try writer.fetch(FetchDescriptor<TransactionContactAssignment>()) {
            writer.delete(assignment)
        }
        try writer.save()

        #expect(readerTransaction.associatedContacts.isEmpty)
    }

    // MARK: - Contact Model Bridging

    @Test("Contact addresses resolve, including before a save, and drop when deleted")
    func contactAddressesResolve() throws {
        let context = ModelContext(try createTestContainer())

        let contact = PersistentContact(cachedName: "Alice")
        context.insert(contact)
        let first = PersistentContactAddress(address: "tark1alice", normalizedAddress: "tark1alice",
                                             format: .ark, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        first.contact = contact
        context.insert(first)
        try context.save()

        #expect(contact.liveAddresses.map(\.address) == ["tark1alice"])
        #expect(ContactModel(from: contact).addresses.map(\.address) == ["tark1alice"])

        // The contact editor inserts addresses and saves at the end of the edit
        let second = PersistentContactAddress(address: "bc1alice", normalizedAddress: "bc1alice",
                                              format: .bitcoin, createdAt: Date(timeIntervalSince1970: 1_700_000_060))
        second.contact = contact
        context.insert(second)

        #expect(contact.liveAddresses.map(\.address) == ["tark1alice", "bc1alice"])

        context.delete(first)
        try context.save()

        #expect(contact.liveAddresses.map(\.address) == ["bc1alice"])
        #expect(ContactModel(from: contact).addresses.map(\.address) == ["bc1alice"])
    }

    @Test("Contact model keeps its transaction count and amounts")
    func contactModelAggregates() throws {
        let context = ModelContext(try createTestContainer())

        let contact = PersistentContact(cachedName: "Alice")
        context.insert(contact)

        let received = makeTransaction(txid: "movement_1")   // received, 1000
        let sent = PersistentTransaction(txid: "movement_2", movementId: nil, type: .sent, amount: 400,
                                         date: Date(), status: .confirmed, address: nil)
        [received, sent].forEach { context.insert($0) }
        context.insert(TransactionContactAssignment(contact: contact, transaction: received))
        context.insert(TransactionContactAssignment(contact: contact, transaction: sent))
        try context.save()

        let model = ContactModel(from: contact)
        #expect(model.transactionCount == 2)
        #expect(model.receivedAmount == 1000)
        #expect(model.sentAmount == 400)
        #expect(contact.associatedTransactions.count == 2)
        #expect(contact.totalTransactionAmount == 600)
    }

    @Test("Tag aggregates resolve through the store")
    func tagAggregates() throws {
        let context = ModelContext(try createTestContainer())

        let tag = makeTag("Groceries")
        context.insert(tag)

        let received = makeTransaction(txid: "movement_1")   // received, 1000
        let sent = PersistentTransaction(txid: "movement_2", movementId: nil, type: .sent, amount: 400,
                                         date: Date(), status: .confirmed, address: nil, fees: 7)
        sent.onchainFeeSat = 3
        [received, sent].forEach { context.insert($0) }
        context.insert(TransactionTagAssignment(tag: tag, transaction: received))
        context.insert(TransactionTagAssignment(tag: tag, transaction: sent))
        try context.save()

        #expect(tag.associatedTransactions.count == 2)
        #expect(tag.receivedAmount == 1000)
        #expect(tag.sentAmount == 400)
        #expect(tag.totalTransactionAmount == 600)
        #expect(tag.offchainFees == 7)
        #expect(tag.onchainFees == 3)
        #expect(tag.totalFees == 10)
    }

    // MARK: - Bulk Snapshot

    @Test("Snapshot groups tags and contacts by txid")
    func snapshotGroupsByTxid() throws {
        let context = ModelContext(try createTestContainer())

        let first = makeTransaction(txid: "movement_1")
        let second = makeTransaction(txid: "movement_2")
        let untagged = makeTransaction(txid: "movement_3")
        [first, second, untagged].forEach { context.insert($0) }

        let groceries = makeTag("Groceries")
        let rent = makeTag("Rent")
        [groceries, rent].forEach { context.insert($0) }

        let alice = PersistentContact(cachedName: "Alice")
        context.insert(alice)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(TransactionTagAssignment(tag: groceries, transaction: first, assignedDate: base))
        context.insert(TransactionTagAssignment(tag: rent, transaction: first,
                                                assignedDate: base.addingTimeInterval(60)))
        context.insert(TransactionTagAssignment(tag: rent, transaction: second, assignedDate: base))
        context.insert(TransactionContactAssignment(contact: alice, transaction: second))
        try context.save()

        let snapshot = TransactionMetadataSnapshot(modelContext: context)

        #expect(snapshot.tags(forTxid: "movement_1").map(\.name) == ["Groceries", "Rent"])
        #expect(snapshot.tags(forTxid: "movement_2").map(\.name) == ["Rent"])
        #expect(snapshot.tags(forTxid: "movement_3").isEmpty)
        #expect(snapshot.tags(forTxid: "does_not_exist").isEmpty)

        #expect(snapshot.contacts(forTxid: "movement_2").map(\.cachedName) == ["Alice"])
        #expect(snapshot.contacts(forTxid: "movement_1").isEmpty)

        // The filtered-list predicates the activity lists run
        #expect(snapshot.transaction(withTxid: "movement_1", hasTagWithId: groceries.id))
        #expect(!snapshot.transaction(withTxid: "movement_2", hasTagWithId: groceries.id))
        #expect(snapshot.transaction(withTxid: "movement_2", hasContactWithId: alice.id))
        #expect(!snapshot.transaction(withTxid: "movement_1", hasContactWithId: alice.id))
    }

    @Test("Snapshot agrees with the per-transaction accessors")
    func snapshotMatchesPerTransactionAccessors() throws {
        let context = ModelContext(try createTestContainer())

        let transaction = makeTransaction(txid: "movement_1")
        let groceries = makeTag("Groceries")
        let rent = makeTag("Rent")
        let alice = PersistentContact(cachedName: "Alice")
        context.insert(transaction)
        [groceries, rent].forEach { context.insert($0) }
        context.insert(alice)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(TransactionTagAssignment(tag: rent, transaction: transaction, assignedDate: base))
        context.insert(TransactionTagAssignment(tag: groceries, transaction: transaction,
                                                assignedDate: base.addingTimeInterval(60)))
        context.insert(TransactionContactAssignment(contact: alice, transaction: transaction))
        try context.save()

        let snapshot = TransactionMetadataSnapshot(modelContext: context)

        #expect(snapshot.tags(forTxid: transaction.txid).map(\.id)
                == transaction.associatedTags.map(\.id))
        #expect(snapshot.contacts(forTxid: transaction.txid).map(\.id)
                == transaction.associatedContacts.map(\.id))

        // And the bulk-resolved row renders the same model as the direct path
        let bulk = TransactionModel(
            from: transaction,
            tags: snapshot.tags(forTxid: transaction.txid),
            contacts: snapshot.contacts(forTxid: transaction.txid)
        )
        let direct = TransactionModel(from: transaction)
        #expect(bulk.associatedTags.map(\.id) == direct.associatedTags.map(\.id))
        #expect(bulk.associatedContacts.map(\.id) == direct.associatedContacts.map(\.id))
    }

    @Test("Empty snapshot resolves to no metadata")
    func emptySnapshot() {
        let snapshot = TransactionMetadataSnapshot()

        #expect(snapshot.tags(forTxid: "movement_1").isEmpty)
        #expect(snapshot.contacts(forTxid: "movement_1").isEmpty)
        #expect(!snapshot.transaction(withTxid: "movement_1", hasTagWithId: UUID()))
        #expect(!snapshot.transaction(withTxid: "movement_1", hasContactWithId: UUID()))
    }
}
