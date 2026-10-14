//
//  DeletionForfeitWarningTests.swift
//  ArkéTests
//
//  The Delete wallet screen's funds warning: when it shows, which copy, and
//  whether it claims a deadline. Tests the decisions and the failure modes
//  (unknown height, past expiry, read-only fallback), not the arithmetic.
//

import Testing
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Deletion Forfeit Warning Tests")
struct DeletionForfeitWarningTests {

    private static func vtxo(_ amount: Int, expiry: Int, state: VTXOState = .spendable) -> VTXOModel {
        VTXOModel(id: "\(amount):\(expiry):\(state.rawValue)", amountSat: amount, expiryHeight: expiry, kind: .pubkey, state: state)
    }

    // MARK: - Whether the box shows

    @Test("No VTXOs: no warning, whatever the strategy")
    func noVtxosNoWarning() {
        let summary = DeletionForfeitWarning.summarize([])
        #expect(DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 100) == nil)
        #expect(DeletionForfeitWarning.resolve(strategy: .localOnly, summary: summary, currentBlockHeight: 100) == nil)
    }

    @Test("Spent and exited VTXOs cannot be forfeited and never trigger the box")
    func spentAndExitedIgnored() {
        let summary = DeletionForfeitWarning.summarize([
            Self.vtxo(5_000, expiry: 150, state: .spent),
            Self.vtxo(7_000, expiry: 120, state: .exited)
        ])
        #expect(summary.amountSat == 0)
        #expect(DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 100) == nil)
    }

    @Test("Locked VTXOs (how bark reports pending boards and round inputs) still sit under an expiry and count")
    func lockedAndBoardsCount() {
        let summary = DeletionForfeitWarning.summarize([
            Self.vtxo(1_000, expiry: 200, state: .locked),
            Self.vtxo(2_000, expiry: 180, state: .registeredBoard),
            Self.vtxo(3_000, expiry: 160, state: .pending)
        ])
        #expect(summary.amountSat == 6_000)
        #expect(summary.earliestExpiryHeight == 160)
    }

    // MARK: - Which copy

    @Test("Last device maps to the forfeit copy; other devices (and an unreadable registry) to the refresh-elsewhere copy")
    func scopeFollowsStrategy() {
        let summary = DeletionForfeitWarning.summarize([Self.vtxo(19_995, expiry: 3_900)])

        let last = DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 100)
        #expect(last?.scope == .lastDevice)

        let others = DeletionForfeitWarning.resolve(strategy: .localOnly, summary: summary, currentBlockHeight: 100)
        #expect(others?.scope == .otherDevices)
    }

    @Test("Override offered (unreadable registry or doubtful blockers): last-device copy, not 'open another device'")
    func overrideOfferedUsesLastDeviceCopy() {
        let summary = DeletionForfeitWarning.summarize([Self.vtxo(19_995, expiry: 3_900)])
        let state = DeletionForfeitWarning.resolve(strategy: .localOnly, overrideOffered: true, summary: summary, currentBlockHeight: 100)
        #expect(state?.scope == .lastDevice)

        // Irrelevant on a genuine last device, which is already that copy
        let last = DeletionForfeitWarning.resolve(strategy: .promptForCloudData, overrideOffered: false, summary: summary, currentBlockHeight: 100)
        #expect(last?.scope == .lastDevice)
    }

    // MARK: - The deadline

    @Test("Deadline is the earliest expiry across at-risk VTXOs, amount is their sum")
    func earliestExpiryWins() {
        let summary = DeletionForfeitWarning.summarize([
            Self.vtxo(10_000, expiry: 500),
            Self.vtxo(5_000, expiry: 300),
            Self.vtxo(4_995, expiry: 800)
        ])
        let state = DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 100)
        #expect(state == .init(scope: .lastDevice, amountSat: 19_995, blocksUntilExpiry: 200))
    }

    @Test("Unknown block height: amount shown, no deadline claimed")
    func unknownHeightDropsDeadline() {
        let summary = DeletionForfeitWarning.summarize([Self.vtxo(10_000, expiry: 500)])
        let state = DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: nil)
        #expect(state?.amountSat == 10_000)
        #expect(state?.blocksUntilExpiry == nil)
    }

    @Test("Expiry already reached: no deadline, since the app cannot tell whether the sweep happened")
    func pastExpiryDropsDeadline() {
        let summary = DeletionForfeitWarning.summarize([Self.vtxo(10_000, expiry: 500)])
        #expect(DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 500)?.blocksUntilExpiry == nil)
        #expect(DeletionForfeitWarning.resolve(strategy: .promptForCloudData, summary: summary, currentBlockHeight: 900)?.blocksUntilExpiry == nil)
    }

    @Test("Expiry 0 means unknown: counted in the amount, left out of the deadline")
    func zeroExpiryIsUnknown() {
        let summary = DeletionForfeitWarning.summarize([
            Self.vtxo(1_000, expiry: 0),
            Self.vtxo(2_000, expiry: 400)
        ])
        #expect(summary.amountSat == 3_000)
        #expect(summary.earliestExpiryHeight == 400)

        let onlyUnknown = DeletionForfeitWarning.summarize([Self.vtxo(1_000, expiry: 0)])
        #expect(onlyUnknown.earliestExpiryHeight == nil)
        #expect(DeletionForfeitWarning.resolve(strategy: .localOnly, summary: onlyUnknown, currentBlockHeight: 100)?.blocksUntilExpiry == nil)
    }

    @Test("Read-only fallback: a synced amount with no expiry still warns, without a deadline")
    func readOnlyFallback() {
        let summary = DeletionForfeitWarning.Summary(amountSat: 12_000, earliestExpiryHeight: nil)
        let state = DeletionForfeitWarning.resolve(strategy: .localOnly, summary: summary, currentBlockHeight: 100)
        #expect(state == .init(scope: .otherDevices, amountSat: 12_000, blocksUntilExpiry: nil))
    }
}
