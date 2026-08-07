//
//  ExitBlockedInfoTests.swift
//  ArkéTests
//
//  Unit tests for ExitBlockedReason classification and ExitBlockedInfo debounce
//  Created by Christoph on 7/14/26.
//

import Testing
import Foundation
import SwiftData
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Exit Blocked Info Tests")
struct ExitBlockedInfoTests {
    
    // MARK: - Classification
    
    @Test("Classify raw insufficient funds message from progressExits")
    func testClassifyInsufficientFundsRaw() {
        // ExitProgressStatus.error carries bark's ExitError display string directly
        let message = "Insufficient Confirmed Funds: 0.00012345 BTC is needed but only 0.00001000 BTC is available"
        #expect(ExitBlockedReason.classify(message) == .insufficientOnchainFunds)
    }
    
    @Test("Classify wrapped claim fee message from drainExits")
    func testClassifyClaimFeeWrapped() {
        // The drainExits throw arrives wrapped in FFI error layers (verified
        // against a real debug log from 2026-07-14)
        let message = "Configuration error: Failed to drain exits: Bark.Error.Inner(message: \"Drain exits failed: Claim Fee Exceeds Output: Cost to claim exits was 0.07026272 BTC, but the total output was 0.00039965 BTC\")"
        #expect(ExitBlockedReason.classify(message) == .claimFeeExceedsOutput)
    }
    
    @Test("Classify raw claim fee message")
    func testClassifyClaimFeeRaw() {
        let message = "Claim Fee Exceeds Output: Cost to claim exits was 0.07026272 BTC, but the total output was 0.00039965 BTC"
        #expect(ExitBlockedReason.classify(message) == .claimFeeExceedsOutput)
    }
    
    @Test("Unknown errors fall back to other")
    func testClassifyUnknownError() {
        let message = "Exit Package Broadcast Failure: Unable to broadcast exit transaction package abc123: bad-txns-inputs-missingorspent"
        #expect(ExitBlockedReason.classify(message) == .other)
    }
    
    // MARK: - Debounce
    
    @Test("Blocked state is not surfaceable after a single attempt")
    func testSingleAttemptNotSurfaceable() {
        let info = ExitBlockedInfo(
            reason: .claimFeeExceedsOutput,
            phase: .claim,
            rawErrorMessage: "Claim Fee Exceeds Output: ...",
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            attemptCount: 1
        )
        #expect(!info.isSurfaceable)
    }
    
    @Test("Blocked state is surfaceable after two attempts")
    func testTwoAttemptsSurfaceable() {
        let info = ExitBlockedInfo(
            reason: .claimFeeExceedsOutput,
            phase: .claim,
            rawErrorMessage: "Claim Fee Exceeds Output: ...",
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            attemptCount: 2
        )
        #expect(info.isSurfaceable)
    }

    // MARK: - Persistence

    @Test("ExitBlockedInfo round-trips through JSON")
    func testJsonRoundTrip() throws {
        // Persistence in PersistentExitCache.blockedInfoJson relies on this
        let original = ExitBlockedInfo(
            reason: .insufficientOnchainFunds,
            phase: .progression,
            rawErrorMessage: "Insufficient Confirmed Funds: 0.00012345 BTC is needed but only 0.00001000 BTC is available",
            firstSeenAt: Date(timeIntervalSince1970: 1_784_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_784_000_300),
            attemptCount: 3
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExitBlockedInfo.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isSurfaceable)
    }
}

// MARK: - Exit Store

/// Tests for ExitStore, the single owner of unilateral-exit state.
/// Wallet access is injected via WalletHooks, so these run against canned
/// responses and count hook invocations.
@Suite("Exit Store")
@MainActor
struct ExitStoreTests {

    /// Counts hook invocations across a store's lifetime
    private final class HookCounter {
        var fetchVtxosCalls = 0
        var relinkCalls = 0
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PersistentExitCache.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Store wired to canned wallet responses. `exits` is re-evaluated per
    /// refresh so tests can change what bark "returns" between refreshes.
    private func makeStore(
        context: ModelContext?,
        counter: HookCounter,
        statuses: [String: ExitTransactionStatus] = [:],
        exits: @escaping () -> [ExitVtxo]
    ) -> ExitStore {
        let store = ExitStore()
        store.modelContext = context
        store.hooks = ExitStore.WalletHooks(
            fetchExitVtxos: {
                counter.fetchVtxosCalls += 1
                return exits()
            },
            fetchExitStatus: { vtxoId in statuses[vtxoId] },
            relinkMovements: { counter.relinkCalls += 1 }
        )
        return store
    }

    private func liveExit(_ vtxoId: String, amount: UInt64 = 10_000) -> ExitVtxo {
        ExitVtxo(
            vtxoId: vtxoId,
            amountSats: amount,
            state: .claimable(tipHeight: 0, claimableSince: BlockRef(height: 0, hash: ""), lastScannedBlock: nil),
            isClaimable: true
        )
    }

    @Test("A refresh triggers movement re-linking exactly once")
    func testRefreshRelinksOnce() async throws {
        // Regression: invalidateExitCache used to run the relink twice per
        // refresh (once itself, once via the refresh it triggered)
        let counter = HookCounter()
        let store = makeStore(context: nil, counter: counter) { [self] in [liveExit("vtxo_a")] }

        await store.refresh()

        #expect(counter.relinkCalls == 1)
        #expect(counter.fetchVtxosCalls == 1)
    }

    @Test("Concurrent refresh calls join one in-flight refresh")
    func testConcurrentRefreshJoins() async throws {
        let counter = HookCounter()
        let store = makeStore(context: nil, counter: counter) { [self] in [liveExit("vtxo_a")] }

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        #expect(counter.fetchVtxosCalls == 1)
        #expect(counter.relinkCalls == 1)
    }

    @Test("An exit that vanishes mid-claim is finalized as claimed on disk")
    func testVanishedClaimInProgressFinalized() async throws {
        // bark purges claimed exits from getExitVtxos(), usually before a
        // refresh ever observes "Claimed" — the persisted entry is the only
        // surviving record and must be kept and marked complete
        let container = try makeContainer()
        let context = container.mainContext
        let counter = HookCounter()

        let status = ExitTransactionStatus(
            vtxoId: "vtxo_a",
            state: .claimInProgress(
                tipHeight: 301627,
                claimableSince: BlockRef(height: 301555, hash: "00000001"),
                claimTxid: "dc2b6f00"
            ),
            history: nil,
            transactionCount: 1
        )
        var barkList = [ExitVtxo(
            vtxoId: "vtxo_a",
            amountSats: 25_000,
            state: .claimInProgress(
                tipHeight: 301627,
                claimableSince: BlockRef(height: 301555, hash: "00000001"),
                claimTxid: "dc2b6f00"
            ),
            isClaimable: false
        )]
        let store = makeStore(context: context, counter: counter, statuses: ["vtxo_a": status]) { barkList }
        store.recordBlocked(vtxoId: "vtxo_a", phase: .claim, errorMessage: "Claim Fee Exceeds Output")

        await store.refresh()   // persists the live exit with its status
        barkList = []
        await store.refresh()   // bark has purged it

        let entries = try context.fetch(FetchDescriptor<PersistentExitCache>())
        let entry = try #require(entries.first { $0.vtxoId == "vtxo_a" })
        #expect(entry.isClaimed)
        #expect(!entry.isClaimable)
        #expect(entry.blockedInfoJson == nil)
        // The snapshot survives for the detail view
        #expect(store.persistedStatus(for: "vtxo_a")?.state == status.state)
    }

    @Test("Blocked records for exits gone from bark's list are pruned on refresh")
    func testBlockedPruning() async throws {
        let counter = HookCounter()
        let store = makeStore(context: nil, counter: counter) { [self] in [liveExit("vtxo_live")] }

        store.recordBlocked(vtxoId: "vtxo_gone", phase: .progression, errorMessage: "Insufficient Confirmed Funds")
        store.recordBlocked(vtxoId: "vtxo_live", phase: .progression, errorMessage: "Insufficient Confirmed Funds")

        await store.refresh()

        #expect(store.blockedInfoByVtxoId["vtxo_gone"] == nil)
        #expect(store.blockedInfoByVtxoId["vtxo_live"] != nil)
    }

    @Test("Clearing progression-phase blockage leaves a claim-phase record intact")
    func testClearRespectsPhase() {
        // Progression succeeds on every check while an exit sits at
        // Claimable; clearing the claim record would reset its debounce
        let store = ExitStore()

        store.recordBlocked(vtxoId: "vtxo_a", phase: .claim, errorMessage: "Claim Fee Exceeds Output")
        store.clearBlocked(vtxoId: "vtxo_a", phase: .progression)
        #expect(store.blockedInfoByVtxoId["vtxo_a"] != nil)

        store.clearBlocked(vtxoId: "vtxo_a", phase: .claim)
        #expect(store.blockedInfoByVtxoId["vtxo_a"] == nil)
    }

    @Test("Snapshotted statuses round-trip through persistence")
    func testSnapshotRoundTrip() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = HookCounter()

        let status = ExitTransactionStatus(
            vtxoId: "vtxo_a",
            state: .claimInProgress(
                tipHeight: 1,
                claimableSince: BlockRef(height: 1, hash: "00"),
                claimTxid: "ab"
            ),
            history: [.start(tipHeight: 0)],
            transactionCount: 1
        )
        let store = makeStore(context: context, counter: counter, statuses: ["vtxo_a": status]) { [] }

        await store.snapshotStatuses(vtxoIds: ["vtxo_a"])

        #expect(store.persistedStatus(for: "vtxo_a") == status)
        #expect(store.cachedStatus(for: "vtxo_a") == status)
    }
}
