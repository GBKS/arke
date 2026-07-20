//
//  FeeRateServiceTests.swift
//  ArkéTests
//
//  Unit tests for FeeRateService's Esplora /fee-estimates parsing
//  Created by Christoph on 7/8/26.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Fee Rate Service Tests")
struct FeeRateServiceTests {

    // MARK: - Tier Mapping

    @Test("Exact targets 1/3/6 map to fast/medium/slow")
    func testExactTargets() {
        let estimates = ["1": 42.0, "3": 20.0, "6": 8.0, "144": 1.5]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 42)
        #expect(rates?.medium == 20)
        #expect(rates?.slow == 8)
    }

    @Test("Missing target falls back to largest smaller target")
    func testMissingTargetUsesSmallerTarget() {
        // No "3" and no "6": medium should use target 2, slow should use target 4
        let estimates = ["1": 50.0, "2": 30.0, "4": 10.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 50)
        #expect(rates?.medium == 30)
        #expect(rates?.slow == 10)
    }

    @Test("Targets all above desired fall back to smallest available")
    func testAllTargetsAboveDesired() {
        // Only far-out targets available: everything uses the smallest (10)
        let estimates = ["10": 5.0, "144": 1.2]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 5)
        #expect(rates?.medium == 5)
        #expect(rates?.slow == 5)
    }

    @Test("Non-monotonic estimator data clamps to fast >= medium >= slow")
    func testNonMonotonicDataClamped() {
        // Observed on signet: targets 1-3 sane, targets 4+ garbage (27k sat/vB)
        let estimates = ["1": 1.828, "2": 1.828, "3": 1.828, "4": 27145.273, "6": 27145.273, "144": 1.828]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 2)
        #expect(rates?.medium == 2)
        #expect(rates?.slow == 2)
    }

    // MARK: - Rounding & Clamping

    @Test("Fractional rates round up")
    func testFractionalRatesRoundUp() {
        let estimates = ["1": 12.1, "3": 5.9, "6": 2.5]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 13)
        #expect(rates?.medium == 6)
        #expect(rates?.slow == 3)
    }

    @Test("Sub-1 rates clamp to 1 sat/vB")
    func testSub1RatesClampTo1() {
        // Typical signet response: everything at ~1 sat/vB or below
        let estimates = ["1": 1.0, "3": 0.9, "6": 0.5]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 1)
        #expect(rates?.medium == 1)
        #expect(rates?.slow == 1)
    }

    // MARK: - Sanity Cap

    @Test("Cap clamps all tiers when every target is garbage")
    func testCapClampsAllTiers() {
        // Observed on signet under fee spam: even target 1 reports six digits
        let estimates = ["1": 314697.0, "3": 314697.0, "6": 250000.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates, maxRate: 50)

        #expect(rates?.fast == 50)
        #expect(rates?.medium == 50)
        #expect(rates?.slow == 50)
    }

    @Test("Cap leaves sane rates untouched")
    func testCapLeavesSaneRatesUntouched() {
        let estimates = ["1": 42.0, "3": 20.0, "6": 8.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates, maxRate: 50)

        #expect(rates?.fast == 42)
        #expect(rates?.medium == 20)
        #expect(rates?.slow == 8)
    }

    @Test("Cap applies per tier when only some targets are garbage")
    func testCapAppliesPerTier() {
        let estimates = ["1": 120000.0, "3": 30.0, "6": 8.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates, maxRate: 50)

        #expect(rates?.fast == 50)
        #expect(rates?.medium == 30)
        #expect(rates?.slow == 8)
    }

    @Test("Nil cap (mainnet) passes high rates through")
    func testNilCapPassesHighRatesThrough() {
        let estimates = ["1": 800.0, "3": 500.0, "6": 300.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates, maxRate: nil)

        #expect(rates?.fast == 800)
        #expect(rates?.medium == 500)
        #expect(rates?.slow == 300)
    }

    // MARK: - Invalid Input

    @Test("Empty map returns nil")
    func testEmptyMapReturnsNil() {
        #expect(FeeRateService.parse(esploraEstimates: [:]) == nil)
    }

    @Test("Garbage keys and values are ignored")
    func testGarbageEntriesIgnored() {
        let estimates = ["abc": 10.0, "-1": 20.0, "0": 30.0, "3": -5.0, "6": Double.nan]
        #expect(FeeRateService.parse(esploraEstimates: estimates) == nil)
    }

    @Test("Valid entries survive alongside garbage entries")
    func testValidEntriesSurviveGarbage() {
        let estimates = ["abc": 10.0, "1": 25.0, "6": -1.0]
        let rates = FeeRateService.parse(esploraEstimates: estimates)

        #expect(rates?.fast == 25)
        #expect(rates?.medium == 25)
        #expect(rates?.slow == 25)
    }
}
