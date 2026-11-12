//
//  MetadataPresenceTests.swift
//  ArkéTests
//
//  Whether the delete flow's export step offers the Contacts & Metadata
//  row: only when the user added something. The failure mode that matters
//  is the app's own provisioning (faucet contact, system tags, blank
//  profile) counting as user data.
//

import Foundation
import SwiftData
import Testing
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Metadata Presence Tests")
@MainActor
struct MetadataPresenceTests {

    private func makeContext() throws -> ModelContext {
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }

    private func makeTransaction(txid: String, notes: String? = nil) -> PersistentTransaction {
        PersistentTransaction(txid: txid, movementId: nil, type: .sent, amount: 1000,
                              date: Date(), status: .confirmed, address: nil, notes: notes)
    }

    @Test("An empty store has nothing to export")
    func emptyStore() throws {
        let context = try makeContext()
        #expect(try MetadataExportService.hasUserAddedMetadata(context: context) == false)
    }

    @Test("App-provisioned rows do not count: faucet contact, system tag, blank profile, transaction without a note")
    func provisionedRowsDoNotCount() throws {
        let context = try makeContext()
        context.insert(PersistentContact(cachedName: "Faucetto Signetto", contactType: .faucet))
        context.insert(PersistentTag(name: "Faucet", colorHex: "#000000", emoji: "", isSystemTag: true))
        context.insert(UserProfile())
        context.insert(makeTransaction(txid: "a"))
        context.insert(makeTransaction(txid: "b", notes: ""))
        try context.save()
        #expect(try MetadataExportService.hasUserAddedMetadata(context: context) == false)
    }

    @Test("Each kind of user-added row counts on its own", arguments: ["contact", "tag", "profile", "note"])
    func userRowsCount(kind: String) throws {
        let context = try makeContext()
        switch kind {
        case "contact": context.insert(PersistentContact(cachedName: "Alice"))
        case "tag": context.insert(PersistentTag(name: "Coffee", colorHex: "#000000", emoji: ""))
        case "profile": context.insert(UserProfile(name: "Me"))
        default: context.insert(makeTransaction(txid: "c", notes: "lunch"))
        }
        try context.save()
        #expect(try MetadataExportService.hasUserAddedMetadata(context: context) == true)
    }
}
