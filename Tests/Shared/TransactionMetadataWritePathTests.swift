//
//  TransactionMetadataWritePathTests.swift
//  Arke
//
//  The 2026-09-23 invalidation fix (fetch-resolved accessors) covered the
//  render path; the 2026-09-24 sweep extended it to the write paths — auto
//  tagging, pending-metadata application, the Send flow's replace-assignments
//  deletes, and import/export. These tests pin that contract: every check and
//  delete goes through a fetch, so a row another context (the CloudKit import
//  in production) deleted underneath a cached relationship array can neither
//  trap nor skew a decision. The second ModelContext below stands in for the
//  import's background context, exactly like TransactionMetadataResolutionTests.
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

@Suite("Transaction Metadata Write Paths")
@MainActor
struct TransactionMetadataWritePathTests {

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

    /// Deletes every TransactionTagAssignment through a second context, the
    /// way the CloudKit import does — the first context's cached relationship
    /// arrays keep listing the rows.
    private func deleteAllTagAssignments(via container: ModelContainer) throws {
        let writer = ModelContext(container)
        for assignment in try writer.fetch(FetchDescriptor<TransactionTagAssignment>()) {
            writer.delete(assignment)
        }
        try writer.save()
    }

    // MARK: - Count accessors agree with the fetch-based reads

    @Test("Count accessors see a cross-context deletion")
    func countAccessorsSeeCrossContextDelete() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        // Materialize the cached relationship, then delete the row elsewhere
        #expect(transaction.tagCount == 1)
        try deleteAllTagAssignments(via: container)

        // Before the fix these read the stale cached array (count 1) while
        // associatedTags (fetch-based) said empty — a footgun pair.
        #expect(transaction.tagCount == 0)
        #expect(!transaction.hasTags)
        #expect(!transaction.hasTag(tag))
        #expect(transaction.associatedTags.isEmpty)
    }

    @Test("Tag's transactionCount sees a cross-context deletion")
    func tagCountersSeeCrossContextDelete() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        #expect(tag.transactionCount == 1)
        try deleteAllTagAssignments(via: container)
        #expect(tag.transactionCount == 0)
        #expect(tag.associatedTransactions.isEmpty)
    }

    // MARK: - Live assignment rows

    @Test("liveTagAssignments returns only rows that exist, in assignment order")
    func liveAssignmentsContract() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let first = makeTag("First")
        let second = makeTag("Second")
        context.insert(transaction)
        context.insert(first)
        context.insert(second)
        let earlier = TransactionTagAssignment(tag: first, transaction: transaction, assignedDate: Date(timeIntervalSinceNow: -60))
        context.insert(earlier)
        try context.save()

        // A pending (unsaved) insert must be visible, ordered after the older one
        context.insert(TransactionTagAssignment(tag: second, transaction: transaction, assignedDate: Date()))
        #expect(transaction.liveTagAssignments.compactMap { $0.tag?.name } == ["First", "Second"])

        // A row deleted by another context must not be returned
        try context.save()
        try deleteAllTagAssignments(via: container)
        #expect(transaction.liveTagAssignments.isEmpty)
    }

    @Test("Send-flow replace: deleting through live rows survives a cross-context delete")
    func sendFlowDeleteAllViaLiveRows() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let contact = PersistentContact(cachedName: "Alice")
        let other = PersistentContact(cachedName: "Bob")
        context.insert(transaction)
        context.insert(contact)
        context.insert(other)
        context.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
        let doomed = TransactionContactAssignment(contact: other, transaction: transaction)
        context.insert(doomed)
        try context.save()

        // Materialize the cached array, then a writer context deletes one row
        #expect(transaction.liveContactAssignments.count == 2)
        let writer = ModelContext(container)
        let doomedContactName = "Bob"
        let writerRows = try writer.fetch(FetchDescriptor<TransactionContactAssignment>())
        for row in writerRows where row.contact?.cachedName == doomedContactName {
            writer.delete(row)
        }
        try writer.save()

        // The Send flow's replace pass: delete every remaining live row.
        // Iterating the cached array here would touch the deleted row.
        for assignment in transaction.liveContactAssignments {
            context.delete(assignment)
        }
        try context.save()

        #expect(transaction.liveContactAssignments.isEmpty)
        #expect(try context.fetch(FetchDescriptor<TransactionContactAssignment>()).isEmpty)
    }

    // MARK: - Pending payment metadata

    @Test("PendingPaymentMetadata resolves tags through the store")
    func pendingMetadataLiveAssignments() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let metadata = PendingPaymentMetadata(paymentHash: nil, destinationAddress: "addr", amountSats: 500, paymentType: "ark")
        let mine = makeTag("Mine")
        let othersTag = makeTag("Others")
        let otherMetadata = PendingPaymentMetadata(paymentHash: nil, destinationAddress: "other", amountSats: 700, paymentType: "ark")
        context.insert(metadata)
        context.insert(otherMetadata)
        context.insert(mine)
        context.insert(othersTag)
        context.insert(PendingTagAssignment(tag: othersTag, pendingMetadata: otherMetadata))
        try context.save()

        // Pending (unsaved) insert visible, and scoped to this metadata row
        context.insert(PendingTagAssignment(tag: mine, pendingMetadata: metadata))
        #expect(metadata.associatedTags.map(\.name) == ["Mine"])
        #expect(metadata.hasTags)
        try context.save()

        // A row deleted by another context is not resolved
        let writer = ModelContext(container)
        for row in try writer.fetch(FetchDescriptor<PendingTagAssignment>()) {
            writer.delete(row)
        }
        try writer.save()
        #expect(metadata.liveTagAssignments.isEmpty)
        #expect(!metadata.hasTags)
    }

    // MARK: - Export / import

    @Test("Export omits assignments another context deleted")
    func exportOmitsDeletedAssignments() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        // Materialize, then delete behind the cached array
        #expect(!transaction.associatedTags.isEmpty)
        try deleteAllTagAssignments(via: container)

        let file = try MetadataExportService.buildExportFile(context: context)
        #expect(file.transactionAnnotations.isEmpty)
    }

    @Test("Import doesn't duplicate an assignment the store already has")
    func importDedupRespectsStore() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let transaction = makeTransaction(txid: "movement_1")
        let tag = makeTag("Groceries")
        context.insert(transaction)
        context.insert(tag)
        context.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        try context.save()

        // An import file re-stating the same assignment must be a no-op
        let file = try MetadataExportService.buildExportFile(context: context)
        _ = try MetadataImportService.apply(file: file, context: context)

        let assignments = try context.fetch(FetchDescriptor<TransactionTagAssignment>())
        #expect(assignments.count == 1)
    }

    // MARK: - Auto tagging

    @Test("Auto-tagging is idempotent and re-adds after a cross-context delete")
    func autoTaggingChecksStoreTruth() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = TransactionService(wallet: MockBarkWallet(), taskManager: TaskDeduplicationManager())
        service.modelContext = context

        let transaction = makeTransaction(txid: "movement_1")
        context.insert(transaction)
        try context.save()

        // Two calls, one assignment: the duplicate check reads store truth
        await service.autoTagInternalTransfer(transaction)
        await service.autoTagInternalTransfer(transaction)
        try context.save()
        #expect(transaction.tagCount == 1)
        #expect(transaction.associatedTags.map(\.name) == ["Balance"])

        // A writer context (the import, in production) deletes the assignment
        // while the cached array still lists it: the next pass must neither
        // trap nor skip — store truth says the tag is gone, so it re-adds.
        try deleteAllTagAssignments(via: container)
        await service.autoTagInternalTransfer(transaction)
        try context.save()
        #expect(transaction.tagCount == 1)
        #expect(transaction.associatedTags.map(\.name) == ["Balance"])
    }
}
