//
//  PrimaryDeviceReconciliationTests.swift
//  ArkéTests
//
//  Unit tests for the deterministic primary-conflict winner rule that drives
//  DeviceRegistrationService.reconcilePrimaryConflicts(). Every device must
//  independently pick the same winner from the same candidate set, or the
//  self-demotion protocol would not converge.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Primary Device Reconciliation Tests")
struct PrimaryDeviceReconciliationTests {

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + offset)
    }

    @Test("Earliest becamePrimaryAt wins")
    func earliestClaimWins() {
        let winner = DeviceRegistrationService.primaryConflictWinner(candidates: [
            PrimaryDeviceCandidate(deviceId: "B", becamePrimaryAt: date(100), registeredAt: date(0)),
            PrimaryDeviceCandidate(deviceId: "A", becamePrimaryAt: date(200), registeredAt: date(0))
        ])
        #expect(winner == "B")
    }

    @Test("Legacy records without becamePrimaryAt fall back to registeredAt")
    func registeredAtFallback() {
        let winner = DeviceRegistrationService.primaryConflictWinner(candidates: [
            PrimaryDeviceCandidate(deviceId: "legacy", becamePrimaryAt: nil, registeredAt: date(50)),
            PrimaryDeviceCandidate(deviceId: "new", becamePrimaryAt: date(100), registeredAt: date(90))
        ])
        #expect(winner == "legacy")
    }

    @Test("Identical dates break ties by deviceId for a total order")
    func deviceIdTiebreak() {
        let winner = DeviceRegistrationService.primaryConflictWinner(candidates: [
            PrimaryDeviceCandidate(deviceId: "ZZZ", becamePrimaryAt: date(100), registeredAt: date(0)),
            PrimaryDeviceCandidate(deviceId: "AAA", becamePrimaryAt: date(100), registeredAt: date(0))
        ])
        #expect(winner == "AAA")
    }

    @Test("All devices agree regardless of candidate order")
    func orderIndependent() {
        let candidates = [
            PrimaryDeviceCandidate(deviceId: "mac", becamePrimaryAt: date(10), registeredAt: date(0)),
            PrimaryDeviceCandidate(deviceId: "iphone", becamePrimaryAt: date(20), registeredAt: date(0)),
            PrimaryDeviceCandidate(deviceId: "ipad", becamePrimaryAt: nil, registeredAt: date(30))
        ]
        let forward = DeviceRegistrationService.primaryConflictWinner(candidates: candidates)
        let reversed = DeviceRegistrationService.primaryConflictWinner(candidates: candidates.reversed())
        #expect(forward == "mac")
        #expect(forward == reversed)
    }

    @Test("Single candidate wins, empty set has no winner")
    func degenerateCases() {
        let single = DeviceRegistrationService.primaryConflictWinner(candidates: [
            PrimaryDeviceCandidate(deviceId: "only", becamePrimaryAt: nil, registeredAt: date(0))
        ])
        #expect(single == "only")
        #expect(DeviceRegistrationService.primaryConflictWinner(candidates: []) == nil)
    }
}
