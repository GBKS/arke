//
//  RefreshRejectionTests.swift
//  ArkéTests
//
//  Unit tests for the pure rejection logic: classifying a server
//  `unusable_inputs` rejection (in flight vs. really unusable), parsing the
//  ids the server names, and the 24 h back-off that stops the app from
//  re-submitting rejected inputs on every launch.
//  See Docs/Features/Refresh_Deduplication.md §9.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Refresh Rejection Tests")
struct RefreshRejectionTests {

    // MARK: - Fixtures

    private static let currentHeight = 300_000
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let idA = String(repeating: "a", count: 64) + ":0"
    private static let idB = String(repeating: "b", count: 64) + ":1"
    private static let idC = String(repeating: "c", count: 64) + ":0"

    /// Shape of the server message on the deployed release
    /// (`server/src/error.rs` `UnusableInputs` Display inside the `{:#}` chain).
    private static func serverMessage(naming ids: [String]) -> String {
        "Failed to schedule delegated VTXO refresh: Error.Inner(message: \"Ark server refused: input vtxo(s) unusable: unusable inputs: [\(ids.joined(separator: ","))]\")"
    }

    private static func vtxo(_ id: String, blocksUntilExpiry: Int) -> Vtxo {
        Vtxo(
            id: id,
            amountSats: 10_000,
            expiryHeight: UInt32(currentHeight + blocksUntilExpiry),
            kind: "arkoor",
            state: .spendable,
            exitDepth: 1,
            exitTxWeightWu: 1_000,
            registered: true
        )
    }

    private struct TextError: Swift.Error, LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    // MARK: - Text match

    @Test("Both spellings of the server tag are recognised, nothing else is")
    func textMatch() {
        #expect(isUnusableInputsRejection(TextError(text: "badarg: unusable_inputs")))
        #expect(isUnusableInputsRejection(TextError(text: Self.serverMessage(naming: [Self.idA]))))
        #expect(!isUnusableInputsRejection(TextError(text: "connection refused")))
        #expect(!isUnusableInputsRejection(TextError(text: "input vtxo does not exist")))
    }

    // MARK: - Parsing

    @Test("VTXO ids are read out of the server message, lowercased")
    func parseIds() {
        let upper = String(repeating: "A", count: 64) + ":3"
        let parsed = RefreshRejection.parseVtxoIds(from: Self.serverMessage(naming: [upper, Self.idB]))
        #expect(parsed == [upper.lowercased(), Self.idB])
    }

    @Test("A message without ids parses to an empty set")
    func parseNoIds() {
        #expect(RefreshRejection.parseVtxoIds(from: "unusable inputs").isEmpty)
    }

    // MARK: - Classification

    @Test("Requested ids that entered an issued round since our check classify as in flight")
    func inFlight() {
        let verdict = RefreshRejection.classify(
            requested: [Self.idA, Self.idB],
            beingRefreshedBefore: [],
            beingRefreshedAfter: [Self.idA],
            serverMessage: Self.serverMessage(naming: [Self.idA])
        )
        #expect(verdict == .inFlight([Self.idA]))
    }

    @Test("Ids already in flight before the call do not count: a stale pending entry is a rejection")
    func stalePendingEntryIsRejected() {
        // Guard C's valve submits expired VTXOs even when a Pending refresh
        // movement claims them (F9: replaced duplicates do not self-heal).
        // The server's rejection then says the entry is stale, not that a
        // refresh is running — the old classifier looped on exactly this.
        let verdict = RefreshRejection.classify(
            requested: [Self.idA],
            beingRefreshedBefore: [Self.idA],
            beingRefreshedAfter: [Self.idA],
            serverMessage: Self.serverMessage(naming: [Self.idA])
        )
        #expect(verdict == .rejected(ids: [Self.idA], precise: true))
    }

    @Test("Nothing in flight and ids named by the server → precise rejection of those ids")
    func preciseRejection() {
        let verdict = RefreshRejection.classify(
            requested: [Self.idA, Self.idB, Self.idC],
            beingRefreshedBefore: [],
            beingRefreshedAfter: [],
            serverMessage: Self.serverMessage(naming: [Self.idB])
        )
        #expect(verdict == .rejected(ids: [Self.idB], precise: true))
    }

    @Test("Nothing in flight and no parsable ids → the whole batch is rejected, imprecisely")
    func batchRejection() {
        let verdict = RefreshRejection.classify(
            requested: [Self.idA, Self.idB],
            beingRefreshedBefore: [],
            beingRefreshedAfter: [],
            serverMessage: "unusable_inputs"
        )
        #expect(verdict == .rejected(ids: [Self.idA, Self.idB], precise: false))
    }

    @Test("Ids the server names but we did not request are ignored")
    func foreignIdsIgnored() {
        let verdict = RefreshRejection.classify(
            requested: [Self.idA],
            beingRefreshedBefore: [],
            beingRefreshedAfter: [],
            serverMessage: Self.serverMessage(naming: [Self.idC])
        )
        // Nothing named intersects the request → fall back to the batch.
        #expect(verdict == .rejected(ids: [Self.idA], precise: false))
    }

    // MARK: - Back-off

    @Test("A recorded id is held back; it is released after the TTL")
    func recordAndExpire() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: true, at: Self.now)
        let vtxo = Self.vtxo(Self.idA, blocksUntilExpiry: 1_000)

        #expect(backoff.shouldSkip(vtxo, currentBlockHeight: Self.currentHeight, now: Self.now))
        #expect(backoff.activeIds(now: Self.now) == [Self.idA])

        let later = Self.now.addingTimeInterval(RefreshRejectionBackoff.ttl)
        #expect(!backoff.shouldSkip(vtxo, currentBlockHeight: Self.currentHeight, now: later))
        #expect(backoff.activeIds(now: later).isEmpty)
    }

    @Test("Re-recording an id refreshes its timestamp")
    func rerecordRefreshes() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: true, at: Self.now)
        let halfway = Self.now.addingTimeInterval(RefreshRejectionBackoff.ttl / 2)
        backoff.record(ids: [Self.idA], precise: true, at: halfway)
        let vtxo = Self.vtxo(Self.idA, blocksUntilExpiry: 1_000)
        let justPastOriginalTTL = Self.now.addingTimeInterval(RefreshRejectionBackoff.ttl + 1)
        #expect(backoff.shouldSkip(vtxo, currentBlockHeight: Self.currentHeight, now: justPastOriginalTTL))
        #expect(backoff.entries.count == 1)
    }

    @Test("Pruning drops ids that left the spendable set and expired entries")
    func prune() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA, Self.idB], precise: true, at: Self.now)
        backoff.record(ids: [Self.idC], precise: true, at: Self.now.addingTimeInterval(-RefreshRejectionBackoff.ttl))
        // idB is no longer spendable (spent/swept); idC aged out; idA stays.
        backoff.prune(keeping: [Self.idA, Self.idC], now: Self.now)
        #expect(backoff.entries.map(\.id) == [Self.idA])
    }

    // MARK: - Near-expiry valve

    @Test("A batch entry yields inside the expiry valve: the server may have named a sibling")
    func batchEntryYieldsNearExpiry() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: false, at: Self.now)
        let nearExpiry = Self.vtxo(Self.idA, blocksUntilExpiry: RefreshExclusion.hardExpiryThresholdBlocks)
        #expect(!backoff.shouldSkip(nearExpiry, currentBlockHeight: Self.currentHeight, now: Self.now))
    }

    @Test("A batch entry holds outside the valve and past expiry")
    func batchEntryHoldsOtherwise() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: false, at: Self.now)
        let far = Self.vtxo(Self.idA, blocksUntilExpiry: RefreshExclusion.hardExpiryThresholdBlocks + 1)
        #expect(backoff.shouldSkip(far, currentBlockHeight: Self.currentHeight, now: Self.now))
        // Past expiry (the field case): retrying a refused VTXO gains nothing.
        let expired = Self.vtxo(Self.idA, blocksUntilExpiry: -10)
        #expect(backoff.shouldSkip(expired, currentBlockHeight: Self.currentHeight, now: Self.now))
    }

    @Test("A precise entry has no valve: the server named this id")
    func preciseEntryHasNoValve() {
        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: true, at: Self.now)
        let nearExpiry = Self.vtxo(Self.idA, blocksUntilExpiry: 10)
        #expect(backoff.shouldSkip(nearExpiry, currentBlockHeight: Self.currentHeight, now: Self.now))
    }

    // MARK: - Persistence

    @Test("Save and load round-trip through UserDefaults; an empty back-off removes the key")
    func persistence() throws {
        let suite = "RefreshRejectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "test.rejectedInputs"

        var backoff = RefreshRejectionBackoff()
        backoff.record(ids: [Self.idA], precise: false, at: Self.now)
        backoff.save(to: defaults, key: key)

        let loaded = RefreshRejectionBackoff.load(from: defaults, key: key)
        #expect(loaded == backoff)
        #expect(loaded.entries.first?.fromBatch == true)

        RefreshRejectionBackoff().save(to: defaults, key: key)
        #expect(defaults.data(forKey: key) == nil)
    }

    @Test("Unreadable stored data loads as an empty back-off")
    func corruptDataLoadsEmpty() throws {
        let suite = "RefreshRejectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "k")
        #expect(RefreshRejectionBackoff.load(from: defaults, key: "k").entries.isEmpty)
    }
}
