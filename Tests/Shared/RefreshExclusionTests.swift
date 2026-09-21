//
//  RefreshExclusionTests.swift
//  ArkéTests
//
//  Unit tests for the pure refresh-exclusion filter (Guard B: mid-exit
//  VTXOs, Guard C: already-in-flight refreshes with the near-expiry safety
//  valve). See Shared/Docs/Features/Refresh_Deduplication.md.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Refresh Exclusion Tests")
struct RefreshExclusionTests {

    // MARK: - Fixtures

    private static let currentHeight = 300_000

    /// A VTXO comfortably far from expiry (well outside the safety valve).
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

    // MARK: - Passthrough

    @Test("No exclusions returns all VTXOs")
    func noExclusions() {
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: 1_000), Self.vtxo("b", blocksUntilExpiry: 2_000)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: [],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.map { $0.id } == ["a", "b"])
    }

    // MARK: - Guard B (exit exclusion)

    @Test("Mid-exit VTXOs are excluded")
    func exitExclusion() {
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: 1_000), Self.vtxo("b", blocksUntilExpiry: 1_000)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: ["a"],
            beingRefreshedIds: [],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.map { $0.id } == ["b"])
    }

    @Test("Exit exclusion has no near-expiry valve")
    func exitExclusionIgnoresValve() {
        // A mid-exit VTXO right at expiry must still be excluded — refreshing
        // it would self-cancel the exit (Exit_Refresh_Coordination.md).
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: 1)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: ["a"],
            beingRefreshedIds: [],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.isEmpty)
    }

    // MARK: - Guard C (in-flight refresh exclusion)

    @Test("In-flight VTXOs are excluded when far from expiry")
    func inFlightExclusion() {
        let farBlocks = RefreshExclusion.hardExpiryThresholdBlocks + 1
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: farBlocks), Self.vtxo("b", blocksUntilExpiry: farBlocks)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: ["a"],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.map { $0.id } == ["b"])
    }

    @Test("Safety valve: in-flight VTXO inside the hard expiry threshold is kept")
    func safetyValveOverridesInFlightExclusion() {
        // A stuck pending entry must not block a renewal this close to
        // expiry — worst case is a benign duplicate the server replaces.
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: RefreshExclusion.hardExpiryThresholdBlocks)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: ["a"],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.map { $0.id } == ["a"])
    }

    @Test("Safety valve boundary: one block above the threshold stays excluded")
    func safetyValveBoundary() {
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: RefreshExclusion.hardExpiryThresholdBlocks + 1)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: ["a"],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.isEmpty)
    }

    @Test("Safety valve applies to already-expired VTXOs")
    func safetyValveExpired() {
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: -10)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: ["a"],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.map { $0.id } == ["a"])
    }

    @Test("Unknown block height disables the valve, not the exclusion")
    func nilBlockHeightExcludesInFlight() {
        // Without a height the valve can't be evaluated; Guard C excludes
        // unconditionally (fail-safe for the double-schedule, and the next
        // check with a height re-evaluates).
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: 1), Self.vtxo("b", blocksUntilExpiry: 1)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: [],
            beingRefreshedIds: ["a"],
            currentBlockHeight: nil
        )
        #expect(result.map { $0.id } == ["b"])
    }

    @Test("Exit exclusion wins over the safety valve when both apply")
    func exitBeatsValve() {
        let vtxos = [Self.vtxo("a", blocksUntilExpiry: 1)]
        let result = RefreshExclusion.filter(
            vtxos,
            exitingIds: ["a"],
            beingRefreshedIds: ["a"],
            currentBlockHeight: Self.currentHeight
        )
        #expect(result.isEmpty)
    }
}
