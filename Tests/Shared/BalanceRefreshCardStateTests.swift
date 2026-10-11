//
//  BalanceRefreshCardStateTests.swift
//  ArkéTests
//
//  The balance card's one decision: which state the refresh row shows and
//  whether it offers a CTA. Tests the choices, not the arithmetic.
//  See Docs/Features/Refresh_Deduplication.md §10.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Balance Refresh Card State Tests")
struct BalanceRefreshCardStateTests {

    private static let minimum = 330

    private static func resolve(
        hasActiveRefresh: Bool = false,
        candidates: (amount: Int, count: Int) = (0, 0),
        heldBack: (amount: Int, count: Int) = (0, 0),
        blocksUntilPpmFree: Int? = nil
    ) -> BalanceRefreshCardState {
        BalanceRefreshCardState.resolve(
            hasActiveRefresh: hasActiveRefresh,
            candidateAmountSats: candidates.amount,
            candidateCount: candidates.count,
            heldBackAmountSats: heldBack.amount,
            heldBackCount: heldBack.count,
            blocksUntilPpmFree: blocksUntilPpmFree,
            minimumSats: minimum
        )
    }

    @Test("Every candidate refused by the server: refused state, no CTA, never 'no refresh needed'")
    func allHeldBackIsRefused() {
        // The divergence incident: three refused VTXOs, nothing submittable,
        // ppm-free height in the past (so no countdown either).
        let state = Self.resolve(heldBack: (19_995, 3), blocksUntilPpmFree: -500)
        #expect(state == .refused(amountSats: 19_995))
        #expect(!state.showsAction)
    }

    @Test("A sub-floor sibling does not mask the refusal")
    func dustSiblingDoesNotMaskRefused() {
        // bark lists dust VTXOs alongside must-refresh ones, so the refused
        // wallet commonly carries a sub-floor candidate too. Nothing can be
        // scheduled either way; the refusal is what the user needs to hear.
        let state = Self.resolve(candidates: (200, 1), heldBack: (19_995, 3))
        #expect(state == .refused(amountSats: 19_995))
        #expect(!state.showsAction)
    }

    @Test("Candidates under bark's dust floor get no CTA and say why")
    func belowFloorIsTooSmall() {
        let state = Self.resolve(candidates: (200, 1))
        #expect(state == .tooSmall(amountSats: 200, minimumSats: Self.minimum))
        #expect(!state.showsAction)
    }

    @Test("At the floor the CTA shows")
    func atFloorIsRefreshNow() {
        let state = Self.resolve(candidates: (Self.minimum, 1))
        #expect(state == .refreshNow(amountSats: Self.minimum))
        #expect(state.showsAction)
    }

    @Test("Mixed set: the submittable part wins and keeps the CTA")
    func mixedSetKeepsAction() {
        // One fresh VTXO plus refused ones: the user can still refresh the
        // fresh one; the held-back amount travels alongside in the data.
        let state = Self.resolve(candidates: (5_000, 1), heldBack: (19_995, 3))
        #expect(state == .refreshNow(amountSats: 5_000))
    }

    @Test("A refresh in flight outranks a refusal")
    func refreshingOutranksRefused() {
        let state = Self.resolve(hasActiveRefresh: true, heldBack: (19_995, 3))
        #expect(state == .refreshing)
    }

    @Test("Nothing submittable and nothing held back falls through to the countdown, then idle")
    func countdownAndIdle() {
        #expect(Self.resolve(blocksUntilPpmFree: 42) == .countdown(blocks: 42))
        #expect(Self.resolve(blocksUntilPpmFree: 0) == .idle)
        #expect(Self.resolve() == .idle)
    }
}
