//
//  ArkBalanceTotalsTests.swift
//  ArkéTests
//
//  What the Ark balance totals mean after bark 0.8.0 split `needs_refresh`
//  out of `spendable` (bindings v0.26.0). These pin decisions, not the
//  mapping: the response and the persisted model must agree, the total
//  must count every bucket bark counts, and spendable must stay what can
//  be sent right now.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Ark Balance Totals")
@MainActor
struct ArkBalanceTotalsTests {

    /// One sat per bucket, distinct powers of ten so a missing or doubled
    /// bucket shows up in the sum.
    private let response = ArkBalanceResponse(
        spendableSat: 1,
        needsRefreshSat: 10,
        pendingLightningSendSat: 100,
        claimableLightningReceiveSat: 1_000,
        pendingInRoundSat: 10_000,
        pendingExitSat: 100_000,
        pendingBoardSat: 1_000_000,
        pendingArkoorSendSat: 10_000_000,
        pendingOffboardSat: 100_000_000
    )

    @Test("Total counts spendable, needs-refresh and every pending bucket (bark's Balance::total)")
    func totalCountsEveryBucket() {
        #expect(response.totalSat == 111_111_111)
    }

    @Test("Pending is bark's pending(): seven buckets, needs-refresh excluded")
    func pendingExcludesNeedsRefresh() {
        #expect(response.totalPendingSat == 111_111_100)
    }

    @Test("Held is what the card shows as Pending: needs-refresh plus pending, so Available + Pending == Total")
    func heldClosesTheCardArithmetic() {
        #expect(response.heldSat == response.totalSat - response.spendableSat)
    }

    @Test("Spendable is untouched by needs-refresh: an expired VTXO lowers nothing a send cap reads")
    func spendableIgnoresNeedsRefresh() {
        let expired = ArkBalanceResponse(
            spendableSat: 5_000,
            needsRefreshSat: 19_995,
            pendingLightningSendSat: 0,
            claimableLightningReceiveSat: 0,
            pendingInRoundSat: 0,
            pendingExitSat: 0,
            pendingBoardSat: 0,
            pendingArkoorSendSat: 0,
            pendingOffboardSat: 0
        )
        #expect(expired.spendableSat == 5_000)
        #expect(expired.totalSat == 24_995)
    }

    @Test("The persisted model agrees with the response for the same input")
    func modelMirrorsResponse() {
        let model = ArkBalanceModel(from: response)
        #expect(model.totalSat == response.totalSat)
        #expect(model.totalPendingSat == response.totalPendingSat)
        #expect(model.heldSat == response.heldSat)

        let updated = ArkBalanceModel(spendableSat: 0, pendingLightningSendSat: 0,
                                      pendingInRoundSat: 0, pendingExitSat: 0, pendingBoardSat: 0)
        updated.update(from: response)
        #expect(updated.totalSat == response.totalSat)
        #expect(updated.heldSat == response.heldSat)
    }

    @Test("A model built with the pre-0.26 initializer reports zero for the four new buckets")
    func legacyInitDefaultsToZero() {
        let legacy = ArkBalanceModel(spendableSat: 2_980, pendingLightningSendSat: 0,
                                     pendingInRoundSat: 0, pendingExitSat: 0, pendingBoardSat: 0)
        #expect(legacy.needsRefreshSat == 0)
        #expect(legacy.claimableLightningReceiveSat == 0)
        #expect(legacy.pendingArkoorSendSat == 0)
        #expect(legacy.pendingOffboardSat == 0)
        #expect(legacy.totalSat == 2_980)
    }
}
