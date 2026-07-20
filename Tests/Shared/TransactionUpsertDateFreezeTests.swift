//
//  TransactionUpsertDateFreezeTests.swift
//  Arke
//
//  Bark re-finishes cancelled exit movements on every sync in which the chain
//  tip advanced, bumping their completed_at each time (see
//  Docs/Features/Exit_Completion_Issues.md §2a). These tests pin the app-side
//  mitigation: a movement that is already cancelled keeps its date across
//  upserts, while the initial transition into cancelled and all other status
//  paths still track date changes.
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

@Suite("Upsert Date Freeze Tests")
@MainActor
struct TransactionUpsertDateFreezeTests {

    // MARK: - Test Setup

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

    private func makeService(context: ModelContext) -> TransactionService {
        let service = TransactionService(wallet: MockBarkWallet(), taskManager: TaskDeduplicationManager())
        service.setModelContext(context)
        return service
    }

    /// Exit movement JSON in the shape returned by bark's movement API
    private func exitMovementJson(
        status: String,
        createdAt: String,
        completedAt: String?
    ) -> String {
        let completedAtJson = completedAt.map { "\"\($0)\"" } ?? "null"
        return """
        [{
            "id": 42,
            "status": "\(status)",
            "subsystem_kind": "start",
            "subsystem_name": "bark.exit",
            "intended_balance_sats": -50000,
            "effective_balance_sats": -50000,
            "offchain_fee_sats": 0,
            "sent_to_addresses": [],
            "received_on_addresses": [],
            "input_vtxo_ids": ["vtxo-1"],
            "output_vtxo_ids": [],
            "exited_vtxo_ids": [],
            "metadata_json": "",
            "created_at": "\(createdAt)",
            "updated_at": "\(createdAt)",
            "completed_at": \(completedAtJson)
        }]
        """
    }

    private func fetchMovement(context: ModelContext) throws -> PersistentTransaction {
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == "movement_42" }
        )
        let transaction = try context.fetch(descriptor).first
        try #require(transaction != nil)
        return transaction!
    }

    // MARK: - Tests

    @Test("Already-cancelled movement keeps its date when completed_at is bumped")
    func alreadyCancelledDateFrozen() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let service = makeService(context: context)

        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "canceled",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: "2026-07-18T12:00:00.000+00:00"
        ))
        let dateAfterCancellation = try fetchMovement(context: context).date

        // Bark bumps completed_at on a later sync; the date must not move
        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "canceled",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: "2026-07-19T09:00:00.000+00:00"
        ))

        let movement = try fetchMovement(context: context)
        #expect(movement.date == dateAfterCancellation)
        #expect(movement.transactionStatus == .cancelled)
    }

    @Test("First transition into cancelled still updates the date")
    func firstCancellationUpdatesDate() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let service = makeService(context: context)

        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "pending",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: nil
        ))
        let dateWhilePending = try fetchMovement(context: context).date

        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "canceled",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: "2026-07-18T12:00:00.000+00:00"
        ))

        let movement = try fetchMovement(context: context)
        #expect(movement.transactionStatus == .cancelled)
        #expect(movement.date != dateWhilePending)
        #expect(movement.date > dateWhilePending)
    }

    @Test("Non-cancelled movements still track date changes")
    func confirmedDateStillUpdates() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let service = makeService(context: context)

        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "pending",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: nil
        ))
        let dateWhilePending = try fetchMovement(context: context).date

        await service.upsertTransactionsFromServerData(exitMovementJson(
            status: "successful",
            createdAt: "2026-07-18T10:00:00.000+00:00",
            completedAt: "2026-07-18T12:00:00.000+00:00"
        ))

        let movement = try fetchMovement(context: context)
        #expect(movement.transactionStatus == .confirmed)
        #expect(movement.date > dateWhilePending)
    }
}
