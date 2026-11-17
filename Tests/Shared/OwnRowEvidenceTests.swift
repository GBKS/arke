//
//  OwnRowEvidenceTests.swift
//  ArkéTests
//
//  DeviceRegistrationService.ownRowEvidence(fallbackContainer:walletHash:) — the registry
//  read the access gate makes on a headless launch, where no model context was
//  ever configured (Device_Linking.md §11.1, adversarial finding F1).
//  Created by Assistant on 11/14/26.
//

import Testing
import Foundation
import SwiftData

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Own Row Evidence", .serialized)
@MainActor
struct OwnRowEvidenceTests {

    private func container() throws -> ModelContainer {
        let schema = Schema([DeviceRegistration.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// A service exactly as a BGTask launch sees it: constructed, never given
    /// a model context.
    private func headlessService() -> DeviceRegistrationService {
        DeviceRegistrationService(taskManager: TaskDeduplicationManager())
    }

    private func insertOwnRow(isPrimary: Bool, walletHash: String = "hash-A", into container: ModelContainer, service: DeviceRegistrationService) throws {
        let context = ModelContext(container)
        let row = DeviceRegistration(
            deviceId: try service.getOrCreateDeviceId(),
            deviceName: "Test phone",
            platform: .iOS,
            walletHash: walletHash,
            hasSeed: true,
            isPrimaryDevice: isPrimary
        )
        context.insert(row)
        try context.save()
    }

    @Test("No context and no container is unavailable, not absent")
    func nothingToAskIsUnavailable() async {
        let service = headlessService()
        #expect(await service.ownRowEvidence(fallbackContainer: nil, walletHash: "hash-A") == .unavailable)
    }

    @Test("A headless launch reads its own primary row through the fallback container")
    func fallbackContainerFindsPrimaryRow() async throws {
        let service = headlessService()
        let container = try container()
        try insertOwnRow(isPrimary: true, into: container, service: service)

        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: "hash-A") == .primary)
    }

    @Test("A headless launch sees a secondary row as secondary")
    func fallbackContainerFindsSecondaryRow() async throws {
        let service = headlessService()
        let container = try container()
        try insertOwnRow(isPrimary: false, into: container, service: service)

        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: "hash-A") == .secondary)
    }

    @Test("A headless launch on an unlinked device sees no row, which blocks")
    func fallbackContainerReportsAbsentRow() async throws {
        // The F1 scenario: another device unlinked this one and the deletion
        // has synced; the stale KVS flag must not stand in for the row
        let service = headlessService()
        let container = try container()

        let evidence = await service.ownRowEvidence(fallbackContainer: container, walletHash: "hash-A")
        #expect(evidence == .absent)
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: evidence) == .block(.noRegistration))
    }

    @Test("A row registered under another wallet is otherWallet, not a role")
    func rowForAnotherWalletIsNotEvidence() async throws {
        // Range review 2026-11-16, G1: the upgrade cohort's old primary row
        // after a wipe-and-recreate elsewhere
        let service = headlessService()
        let container = try container()
        try insertOwnRow(isPrimary: true, walletHash: "hash-X", into: container, service: service)

        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: "hash-Y") == .otherWallet)
        // Same wallet, or no wallet known: the role stands
        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: "hash-X") == .primary)
        // No wallet to ask about: a row is not evidence either way (F2 of
        // the pass on this fix), while no row is still no row
        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: nil) == .unavailable)
        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: "") == .unavailable)
    }

    @Test("No row is absent whatever wallet is asked about, including none")
    func absentRowIsAbsentUnscoped() async throws {
        let service = headlessService()
        let container = try container()
        #expect(await service.ownRowEvidence(fallbackContainer: container, walletHash: nil) == .absent)
    }

    @Test("A configured context wins over the fallback container")
    func configuredContextTakesPrecedence() async throws {
        let service = headlessService()
        let configured = try container()
        let fallback = try container()
        try insertOwnRow(isPrimary: true, into: fallback, service: service)
        service.setModelContext(ModelContext(configured))

        // The configured store is empty; the fallback must not be consulted
        #expect(await service.ownRowEvidence(fallbackContainer: fallback, walletHash: "hash-A") == .absent)
    }
}
