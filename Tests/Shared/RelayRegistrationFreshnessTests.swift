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

/// Pins the stale-wake decision for `mailbox_auth_refresh` pushes
/// (SWIFT_AUTH_WAKE_SPEC.md work item 2): a wake for the current wallet's
/// mailbox re-registers; a wake for any other mailbox unregisters the
/// orphaned pair. The relay lowercases mailbox ids, so the match must be
/// case-insensitive — a hex-case difference must never be mistaken for a
/// replaced wallet.
@Suite("Stale Wake Decision Tests")
struct StaleWakeDecisionTests {

    @Test("An identical mailbox id is the current mailbox")
    func exactMatchIsCurrent() {
        #expect(RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "a3f09b2c11dd44ee",
            currentMailboxId: "a3f09b2c11dd44ee"
        ))
    }

    @Test("The match is case-insensitive in both directions")
    func matchIsCaseInsensitive() {
        #expect(RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "a3f09b2c11dd44ee",
            currentMailboxId: "A3F09B2C11DD44EE"
        ))
        #expect(RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "A3F09B2C11DD44EE",
            currentMailboxId: "a3f09b2c11dd44ee"
        ))
    }

    @Test("A different mailbox id is stale")
    func differentIdIsStale() {
        #expect(!RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "deadbeef00000000",
            currentMailboxId: "a3f09b2c11dd44ee"
        ))
    }

    @Test("A truncated or extended id is stale, not a prefix match")
    func prefixIsNotAMatch() {
        #expect(!RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "a3f09b2c",
            currentMailboxId: "a3f09b2c11dd44ee"
        ))
        #expect(!RelayRegistrationService.isWakeForCurrentMailbox(
            payloadMailboxId: "a3f09b2c11dd44ee00",
            currentMailboxId: "a3f09b2c11dd44ee"
        ))
    }
}
