//
//  ReadOnlySyncedDataTests.swift
//  Arke
//
//  A secondary (read-only) device has no wallet session: its balances and
//  addresses are CloudKit-synced rows. Both services used to read those rows
//  exactly once, at init — which on a fresh install happens *before* the first
//  CloudKit import lands, so the balance sat at 0 and the receive screen stayed
//  empty for the whole session (2026-09-23, second iPhone: "No Ark balance
//  found in CloudKit yet" at launch, import streamed in over the next 30s,
//  correct balance only after a relaunch).
//
//  These tests pin that rows arriving after init are picked up, and that the
//  balance singletons resolve newest-first — CloudKit forbids unique
//  constraints, so two devices can each create an "ark_balance" row.
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

@Suite("Read-Only Synced Data")
@MainActor
struct ReadOnlySyncedDataTests {

    // MARK: - Setup

    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            ArkBalanceModel.self,
            OnchainBalanceModel.self,
            PersistentAddress.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Waits for a main-actor condition driven by the services' notification
    /// observers, which hop through a Task before re-reading.
    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - Balances

    @Test("Balance rows arriving after init are read on the next CloudKit change")
    func balancePicksUpLateImport() async throws {
        let context = ModelContext(try createTestContainer())

        // Launch on a fresh install: the store has nothing yet
        let service = ReadOnlyBalanceService()
        service.setModelContext(context)

        #expect(service.arkBalance == nil)
        #expect(service.totalBalance?.grandTotalSat == 0)

        // The CloudKit import lands afterwards
        context.insert(ArkBalanceModel(spendableSat: 2980, pendingLightningSendSat: 0,
                                       pendingInRoundSat: 0, pendingExitSat: 0, pendingBoardSat: 0))
        context.insert(OnchainBalanceModel(totalSat: 500, confirmedSat: 500, pendingSat: 0))
        try context.save()
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)

        #expect(await eventually { service.arkBalance?.spendableSat == 2980 })
        #expect(service.onchainBalance?.confirmedSat == 500)
        #expect(service.totalBalance?.grandTotalSat == 3480)
    }

    @Test("A balance row updated in place by another context is re-read, not served stale")
    func balancePicksUpInPlaceUpdate() async throws {
        let container = try createTestContainer()
        let writer = ModelContext(container)

        // The row already exists and the service has already materialized it —
        // the steady state on a secondary device after its first import.
        writer.insert(ArkBalanceModel(spendableSat: 1000, pendingLightningSendSat: 0,
                                      pendingInRoundSat: 0, pendingExitSat: 0, pendingBoardSat: 0))
        try writer.save()

        let reader = ModelContext(container)
        let service = ReadOnlyBalanceService()
        service.setModelContext(reader)
        #expect(service.arkBalance?.spendableSat == 1000)

        // The primary spends: its balance row is *updated in place* and
        // exported, unlike a new transaction or tag assignment, which arrives as
        // a new row. This is the case that did not refresh on device.
        let rows = try writer.fetch(FetchDescriptor<ArkBalanceModel>())
        let row = try #require(rows.first)
        row.spendableSat = 400
        row.lastUpdated = Date(timeIntervalSince1970: 1_800_000_000)
        try writer.save()

        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)

        #expect(await eventually { service.arkBalance?.spendableSat == 400 })
        #expect(service.totalBalance?.totalSpendableSat == 400)
    }

    @Test("An explicit refresh also re-reads the balance rows")
    func balanceRefreshRereads() throws {
        let context = ModelContext(try createTestContainer())

        let service = ReadOnlyBalanceService()
        service.setModelContext(context)
        #expect(service.arkBalance == nil)

        context.insert(ArkBalanceModel(spendableSat: 1234, pendingLightningSendSat: 0,
                                       pendingInRoundSat: 0, pendingExitSat: 0, pendingBoardSat: 0))
        try context.save()

        // This is what pull-to-refresh and WalletManager.refreshBalances() reach
        // in read-only mode; before the fix it had no callers at all.
        service.refreshBalances()

        #expect(service.arkBalance?.spendableSat == 1234)
        #expect(service.totalBalance?.grandTotalSat == 1234)
    }

    @Test("Duplicate balance singletons resolve newest-first")
    func duplicateBalanceRowsResolveNewest() throws {
        let context = ModelContext(try createTestContainer())

        // Two devices each created an "ark_balance" row; the older one is the
        // stale copy a device left behind while it was (wrongly) primary.
        let stale = ArkBalanceModel(spendableSat: 11, pendingLightningSendSat: 0, pendingInRoundSat: 0,
                                    pendingExitSat: 0, pendingBoardSat: 0,
                                    lastUpdated: Date(timeIntervalSince1970: 1_600_000_000))
        let current = ArkBalanceModel(spendableSat: 2980, pendingLightningSendSat: 0, pendingInRoundSat: 0,
                                      pendingExitSat: 0, pendingBoardSat: 0,
                                      lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(stale)
        context.insert(current)

        let staleOnchain = OnchainBalanceModel(totalSat: 1, confirmedSat: 1, pendingSat: 0,
                                               lastUpdated: Date(timeIntervalSince1970: 1_600_000_000))
        let currentOnchain = OnchainBalanceModel(totalSat: 500, confirmedSat: 500, pendingSat: 0,
                                                 lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(staleOnchain)
        context.insert(currentOnchain)
        try context.save()

        let service = ReadOnlyBalanceService()
        service.setModelContext(context)

        #expect(service.arkBalance?.spendableSat == 2980)
        #expect(service.onchainBalance?.confirmedSat == 500)
    }

    // MARK: - Addresses

    @Test("Address rows arriving after init are read on the next CloudKit change")
    func addressPicksUpLateImport() async throws {
        let context = ModelContext(try createTestContainer())

        let service = ReadOnlyAddressService(modelContext: context)
        #expect(service.arkAddress.isEmpty)
        #expect(service.onchainAddress.isEmpty)

        context.insert(PersistentAddress(address: "tark1secondary", addressType: .ark))
        context.insert(PersistentAddress(address: "tb1qsecondary", addressType: .onchain))
        try context.save()
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)

        #expect(await eventually { service.arkAddress == "tark1secondary" })
        #expect(service.onchainAddress == "tb1qsecondary")
    }
}

/// The observer that feeds everything above used to *drop* remote-change
/// notifications that arrived too soon after the last handled one: a 1.5s
/// `debounce` followed by a 2.0s minimum interval with an early return and no
/// re-schedule, so anything landing in the 1.5–2.0s band was lost until some
/// later, unrelated change. Since debounce only emits after 1.5s of quiet,
/// that band is routinely hit. Everything refreshed *only* by
/// `cloudKitDataDidChange` inherited the hole — i.e. most of the read-only
/// path, while `@Query`-backed UI updated normally.
@Suite("Remote Change Throttle")
struct RemoteChangeThrottleTests {

    private let interval: TimeInterval = 2.0
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The first notification is handled immediately")
    func firstIsHandled() {
        #expect(RemoteChangeThrottle.decide(
            now: now, lastHandled: nil, minimumInterval: interval, deferralPending: false
        ) == .handleNow)
    }

    @Test("A notification past the interval is handled immediately")
    func pastIntervalIsHandled() {
        #expect(RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-2.5),
            minimumInterval: interval,
            deferralPending: false
        ) == .handleNow)
    }

    @Test("A notification exactly at the interval is handled immediately")
    func atIntervalIsHandled() {
        #expect(RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-interval),
            minimumInterval: interval,
            deferralPending: false
        ) == .handleNow)
    }

    /// The regression this whole type exists for: the debounce guarantees
    /// ≥1.5s between emissions, so this is the band that was being discarded.
    @Test("A notification in the debounce/interval band is deferred, not dropped")
    func rapidFireIsDeferred() {
        guard case .deferBy(let delay) = RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-1.6),
            minimumInterval: interval,
            deferralPending: false
        ) else {
            Issue.record("Expected a deferral")
            return
        }
        // 1.6 is not exactly representable, so Date arithmetic at real-world
        // magnitudes leaves ~2.4e-8 of error — exact equality would fail.
        #expect(abs(delay - 0.4) < 0.0001)
    }

    @Test("The deferral only waits out the remaining time")
    func deferralWaitsRemainderOnly() {
        guard case .deferBy(let delay) = RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-0.5),
            minimumInterval: interval,
            deferralPending: false
        ) else {
            Issue.record("Expected a deferral")
            return
        }
        #expect(abs(delay - 1.5) < 0.0001)
    }

    @Test("A second rapid-fire notification folds into the pending deferral")
    func secondRapidFireCoalesces() {
        #expect(RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-1.6),
            minimumInterval: interval,
            deferralPending: true
        ) == .coalesceIntoPendingDeferral)
    }

    /// A pending deferral must not swallow a notification that is *due* — it
    /// is handled now and the stale deferral is cancelled.
    @Test("A pending deferral does not suppress a due notification")
    func pendingDeferralDoesNotSuppressDueNotification() {
        #expect(RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(-5),
            minimumInterval: interval,
            deferralPending: true
        ) == .handleNow)
    }

    /// A backwards clock jump (NTP correction, timezone-independent) would
    /// otherwise compute a deferral longer than the interval itself.
    @Test("A last-handled timestamp in the future defers by at most the interval")
    func futureTimestampClampsToInterval() {
        #expect(RemoteChangeThrottle.decide(
            now: now,
            lastHandled: now.addingTimeInterval(60),
            minimumInterval: interval,
            deferralPending: false
        ) == .deferBy(interval))
    }
}
