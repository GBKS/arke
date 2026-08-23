//
//  MetadataImportLogicTests.swift
//  Arke
//
//  Tests for the metadata import merge policy (pure functions) and the
//  export → import round-trip / merge semantics against an in-memory store.
//  Format contract: Docs/Features/Metadata_Export_Import.md.
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

@Suite("Metadata Import Policy Tests")
struct MetadataImportPolicyTests {

    @Test("Normalization trims whitespace and lowercases")
    func normalization() {
        #expect(MetadataImportPolicy.normalize("  Groceries ") == "groceries")
        #expect(MetadataImportPolicy.normalize("TARK1abc") == "tark1abc")
    }

    @Test("Tag matching prefers UUID over name")
    func tagMatchPrecedence() {
        let sharedId = UUID()
        let nameMatchId = UUID()
        let byName = ["groceries": nameMatchId]

        // UUID present locally wins even when a different tag shares the name
        #expect(MetadataImportPolicy.matchTag(importedId: sharedId, importedName: "Groceries",
                                              localIds: [sharedId], localIdsByName: byName) == sharedId)
        // No UUID match falls back to the normalized name
        #expect(MetadataImportPolicy.matchTag(importedId: UUID(), importedName: " GROCERIES ",
                                              localIds: [], localIdsByName: byName) == nameMatchId)
        // Neither matches
        #expect(MetadataImportPolicy.matchTag(importedId: UUID(), importedName: "Rent",
                                              localIds: [], localIdsByName: byName) == nil)
    }

    @Test("Contact matching precedence is UUID, then address, then name")
    func contactMatchPrecedence() {
        let idMatch = UUID()
        let addressMatch = UUID()
        let nameMatch = UUID()
        let byAddress = ["tark1shared": addressMatch]
        let byName = ["alice": nameMatch]

        #expect(MetadataImportPolicy.matchContact(importedId: idMatch, importedName: "Alice",
                                                  importedAddresses: ["TARK1shared"],
                                                  localIds: [idMatch], localIdsByAddress: byAddress,
                                                  localIdsByName: byName) == idMatch)
        #expect(MetadataImportPolicy.matchContact(importedId: UUID(), importedName: "Alice",
                                                  importedAddresses: ["TARK1shared"],
                                                  localIds: [], localIdsByAddress: byAddress,
                                                  localIdsByName: byName) == addressMatch)
        #expect(MetadataImportPolicy.matchContact(importedId: UUID(), importedName: "ALICE",
                                                  importedAddresses: [],
                                                  localIds: [], localIdsByAddress: byAddress,
                                                  localIdsByName: byName) == nameMatch)
        #expect(MetadataImportPolicy.matchContact(importedId: UUID(), importedName: "Bob",
                                                  importedAddresses: ["tark1other"],
                                                  localIds: [], localIdsByAddress: byAddress,
                                                  localIdsByName: byName) == nil)
    }

    @Test("Newest-wins is a strict comparison")
    func newestWins() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        #expect(MetadataImportPolicy.importedWins(importedUpdatedAt: newer, localUpdatedAt: older))
        #expect(!MetadataImportPolicy.importedWins(importedUpdatedAt: older, localUpdatedAt: newer))
        #expect(!MetadataImportPolicy.importedWins(importedUpdatedAt: older, localUpdatedAt: older))
    }

    @Test("Imported notes only fill empty local notes")
    func noteFillPolicy() {
        #expect(MetadataImportPolicy.shouldApplyNote(imported: "coffee", local: nil))
        #expect(MetadataImportPolicy.shouldApplyNote(imported: "coffee", local: ""))
        #expect(!MetadataImportPolicy.shouldApplyNote(imported: "coffee", local: "existing"))
        #expect(!MetadataImportPolicy.shouldApplyNote(imported: nil, local: nil))
        #expect(!MetadataImportPolicy.shouldApplyNote(imported: "", local: nil))
    }
}

@Suite("Metadata Import Service Tests")
@MainActor
struct MetadataImportServiceTests {

    // MARK: - Test Setup

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

    private func makeTransaction(txid: String, notes: String? = nil) -> PersistentTransaction {
        PersistentTransaction(txid: txid, movementId: nil, type: .sent, amount: 1000,
                              date: Date(), status: .confirmed, address: nil, notes: notes)
    }

    // MARK: - Decode

    @Test("Decoding rejects non-arke files and future versions")
    func decodeValidation() throws {
        #expect(throws: MetadataImportError.self) {
            _ = try MetadataImportService.decode(Data("{\"foo\": 1}".utf8))
        }
        #expect(throws: MetadataImportError.self) {
            _ = try MetadataImportService.decode(Data("not json".utf8))
        }
        #expect(throws: MetadataImportError.self) {
            _ = try MetadataImportService.decode(Data("{\"format\": \"arke-metadata\", \"version\": 99}".utf8))
        }
    }

    // MARK: - Round-Trip

    @Test("Export from one store imports losslessly into another")
    func roundTrip() throws {
        // Source store: profile, tag, contact with address, annotated transaction
        let source = try createTestContainer()
        let sourceContext = source.mainContext

        sourceContext.insert(UserProfile(name: "Christoph", avatarData: Data([1, 2, 3])))

        let tag = PersistentTag(name: "Groceries", colorHex: "#00FF00", emoji: "🛒")
        sourceContext.insert(tag)

        let contact = PersistentContact(cachedName: "Alice", notes: "friend")
        sourceContext.insert(contact)
        let address = PersistentContactAddress(address: "TARK1abc", normalizedAddress: "tark1abc",
                                               format: .ark, label: "Spending", isPrimary: true)
        address.contact = contact
        sourceContext.insert(address)

        let transaction = makeTransaction(txid: "tx1", notes: "weekly shop")
        sourceContext.insert(transaction)
        sourceContext.insert(TransactionTagAssignment(tag: tag, transaction: transaction))
        sourceContext.insert(TransactionContactAssignment(contact: contact, transaction: transaction))
        try sourceContext.save()

        let data = try MetadataExportService.makeExportData(context: sourceContext)
        let file = try MetadataImportService.decode(data)

        // Destination store: only the bare transaction exists (came from wallet sync)
        let destination = try createTestContainer()
        let destContext = destination.mainContext
        destContext.insert(makeTransaction(txid: "tx1"))
        try destContext.save()

        let preview = try MetadataImportService.preview(file: file, context: destContext)
        #expect(preview.newTags == 1)
        #expect(preview.newContacts == 1)
        #expect(preview.matchedAnnotations == 1)
        #expect(preview.unmatchedAnnotations == 0)
        #expect(preview.willApplyProfile)

        let result = try MetadataImportService.apply(file: file, context: destContext)
        #expect(result.createdTags == 1)
        #expect(result.createdContacts == 1)
        #expect(result.annotationsApplied == 1)
        #expect(result.profileApplied)

        let importedContacts = try destContext.fetch(FetchDescriptor<PersistentContact>())
        #expect(importedContacts.count == 1)
        #expect(importedContacts.first?.cachedName == "Alice")
        #expect(importedContacts.first?.addresses?.first?.normalizedAddress == "tark1abc")
        #expect(importedContacts.first?.addresses?.first?.isPrimary == true)

        let importedTransaction = try destContext.fetch(FetchDescriptor<PersistentTransaction>()).first
        #expect(importedTransaction?.notes == "weekly shop")
        #expect(importedTransaction?.tagAssignments?.count == 1)
        #expect(importedTransaction?.contactAssignments?.count == 1)

        let profile = try destContext.fetch(FetchDescriptor<UserProfile>()).first
        #expect(profile?.name == "Christoph")
    }

    // MARK: - Merge Semantics

    @Test("UUID-matched contact: newer import overwrites, older import is ignored")
    func contactNewestWins() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        let contactId = UUID()
        let local = PersistentContact(id: contactId, cachedName: "Alice Local", updatedAt: newer)
        context.insert(local)
        try context.save()

        // Older import loses: fields stay local
        var file = emptyFile()
        file.contacts = [ExportedContact(id: contactId, name: "Alice Old", notes: nil, avatarData: nil,
                                         contactType: "standard", createdAt: older, updatedAt: older, addresses: [])]
        var result = try MetadataImportService.apply(file: file, context: context)
        #expect(result.updatedContacts == 0)
        #expect(local.cachedName == "Alice Local")

        // Newer import wins: fields and timestamp adopt the imported values
        let newest = Date(timeIntervalSince1970: 3000)
        file.contacts = [ExportedContact(id: contactId, name: "Alice New", notes: "updated", avatarData: nil,
                                         contactType: "standard", createdAt: older, updatedAt: newest, addresses: [])]
        result = try MetadataImportService.apply(file: file, context: context)
        #expect(result.updatedContacts == 1)
        #expect(local.cachedName == "Alice New")
        #expect(local.updatedAt == newest)
    }

    @Test("Name-matched tag does not duplicate and absorbs assignments")
    func tagNameMerge() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let localTag = PersistentTag(name: "Groceries", colorHex: "#111111", emoji: "🥕")
        context.insert(localTag)
        context.insert(makeTransaction(txid: "tx1"))
        try context.save()

        var file = emptyFile()
        let importedTagId = UUID()
        file.tags = [ExportedTag(id: importedTagId, name: " groceries ", colorHex: "#222222",
                                 emoji: "🛒", createdDate: Date(), isSystemTag: false)]
        file.transactionAnnotations = [ExportedTransactionAnnotation(
            txid: "tx1", notes: nil,
            tagAssignments: [ExportedTagAssignment(tagId: importedTagId, assignedDate: Date())],
            contactAssignments: [])]

        let result = try MetadataImportService.apply(file: file, context: context)
        #expect(result.createdTags == 0)

        // The assignment landed on the existing local tag; its fields are untouched
        let tags = try context.fetch(FetchDescriptor<PersistentTag>())
        #expect(tags.count == 1)
        #expect(tags.first?.colorHex == "#111111")
        #expect(tags.first?.tagAssignments?.count == 1)
    }

    @Test("Existing local notes and assignments survive a re-import")
    func importIsIdempotentAndNonDestructive() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let tag = PersistentTag(name: "Rent", colorHex: "#333333", emoji: "🏠")
        context.insert(tag)
        let transaction = makeTransaction(txid: "tx1", notes: "my own note")
        context.insert(transaction)
        try context.save()

        var file = emptyFile()
        file.tags = [ExportedTag(id: tag.id, name: "Rent", colorHex: "#333333", emoji: "🏠",
                                 createdDate: Date(), isSystemTag: false)]
        file.transactionAnnotations = [ExportedTransactionAnnotation(
            txid: "tx1", notes: "imported note",
            tagAssignments: [ExportedTagAssignment(tagId: tag.id, assignedDate: Date())],
            contactAssignments: [])]

        // Apply twice: the local note survives and the assignment isn't duplicated
        _ = try MetadataImportService.apply(file: file, context: context)
        _ = try MetadataImportService.apply(file: file, context: context)

        #expect(transaction.notes == "my own note")
        #expect(transaction.tagAssignments?.count == 1)
    }

    @Test("Annotations for unknown transactions are skipped and counted")
    func unmatchedAnnotations() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        try context.save()

        var file = emptyFile()
        file.transactionAnnotations = [ExportedTransactionAnnotation(txid: "unknown", notes: "hi",
                                                                     tagAssignments: [], contactAssignments: [])]

        let preview = try MetadataImportService.preview(file: file, context: context)
        #expect(preview.unmatchedAnnotations == 1)

        let result = try MetadataImportService.apply(file: file, context: context)
        #expect(result.annotationsApplied == 0)
        #expect(result.annotationsSkipped == 1)
    }

    @Test("Configured local profile only yields to a newer import")
    func profileMerge() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let newer = Date(timeIntervalSince1970: 2000)
        context.insert(UserProfile(name: "Local Me", updatedAt: newer))
        try context.save()

        var file = emptyFile()
        file.profile = ExportedProfile(name: "Old Me", avatarData: nil,
                                       createdAt: Date(timeIntervalSince1970: 500),
                                       updatedAt: Date(timeIntervalSince1970: 1000))
        var result = try MetadataImportService.apply(file: file, context: context)
        #expect(!result.profileApplied)

        file.profile = ExportedProfile(name: "New Me", avatarData: nil,
                                       createdAt: Date(timeIntervalSince1970: 500),
                                       updatedAt: Date(timeIntervalSince1970: 3000))
        result = try MetadataImportService.apply(file: file, context: context)
        #expect(result.profileApplied)
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).first?.name == "New Me")
    }

    // MARK: - Helpers

    private func emptyFile() -> MetadataExportFile {
        MetadataExportFile(format: MetadataExportFile.currentFormat,
                           version: MetadataExportFile.currentVersion,
                           exportedAt: Date(), appVersion: nil, network: "signet",
                           profile: nil, tags: [], contacts: [], transactionAnnotations: [])
    }
}
