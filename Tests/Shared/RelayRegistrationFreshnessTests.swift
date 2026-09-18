//
//  RelayRegistrationFreshnessTests.swift
//  Arke
//
//  Pins the launch-time registration dedupe (journal finding 2026-09-18:
//  launch flow + APNs token observer both register within seconds, each
//  minting a new token the hash dedupe can't catch). A registration is
//  fresh only when recent, unexpired, and made with the SAME device token —
//  a changed token must always re-register immediately.
//

import Foundation
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Relay Registration Freshness Tests")
struct RelayRegistrationFreshnessTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let window: TimeInterval = 3600

    private func fresh(
        registeredSecondsAgo: TimeInterval?,
        expiresInSeconds: TimeInterval?,
        registeredToken: String? = "token-a",
        currentToken: String? = "token-a"
    ) -> Bool {
        RelayRegistrationService.isRegistrationFresh(
            registeredAt: registeredSecondsAgo.map { now.addingTimeInterval(-$0) },
            expiresAt: expiresInSeconds.map { now.addingTimeInterval($0) },
            registeredDeviceToken: registeredToken,
            currentDeviceToken: currentToken,
            now: now,
            window: window
        )
    }

    @Test("A recent, unexpired registration with the same token is fresh")
    func recentRegistrationIsFresh() {
        #expect(fresh(registeredSecondsAgo: 60, expiresInSeconds: 23 * 3600))
    }

    @Test("Older than the window is stale")
    func oldRegistrationIsStale() {
        #expect(!fresh(registeredSecondsAgo: 2 * 3600, expiresInSeconds: 21 * 3600))
        // Boundary: exactly the window is stale (strict <)
        #expect(!fresh(registeredSecondsAgo: window, expiresInSeconds: 23 * 3600))
    }

    @Test("An expired token is never fresh, regardless of age")
    func expiredTokenIsStale() {
        #expect(!fresh(registeredSecondsAgo: 60, expiresInSeconds: -1))
    }

    @Test("A changed device token defeats freshness")
    func changedTokenDefeatsFreshness() {
        #expect(!fresh(registeredSecondsAgo: 60, expiresInSeconds: 23 * 3600,
                       registeredToken: "token-a", currentToken: "token-b"))
    }

    @Test("Missing state is never fresh")
    func missingStateIsStale() {
        #expect(!fresh(registeredSecondsAgo: nil, expiresInSeconds: 23 * 3600))
        #expect(!fresh(registeredSecondsAgo: 60, expiresInSeconds: nil))
        #expect(!fresh(registeredSecondsAgo: 60, expiresInSeconds: 23 * 3600, currentToken: nil))
        #expect(!fresh(registeredSecondsAgo: 60, expiresInSeconds: 23 * 3600, registeredToken: nil))
    }
}
