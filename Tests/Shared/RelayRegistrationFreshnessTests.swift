//
//  RelayRegistrationFreshnessTests.swift
//  Arke
//
//  Pins the proactive-renewal rule for the relay's mailbox authorization
//  (Migrations/Bark-0.24.0-to-0.25.0, Phase 2): tokens live 30 days and are
//  renewed once past the midpoint of their ACTUAL life. The unsolicited paths
//  (launch, foreground, APNs token observer) all fire every launch, so the
//  rule is what keeps them from minting a fresh token each time. A changed
//  device token or a different mailbox must always renew immediately.
//

import Foundation
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Relay Registration Renewal Tests")
struct RelayRegistrationRenewalTests {

    private let day: TimeInterval = 86_400
    private let registeredAt = Date(timeIntervalSince1970: 1_000_000)

    /// A 30-day token registered at `registeredAt`, asked about `elapsed`
    /// seconds later.
    private func needsRenewal(
        elapsed: TimeInterval,
        lifetime: TimeInterval = 30 * 86_400,
        registeredToken: String? = "token-a",
        currentToken: String? = "token-a",
        registeredMailbox: String? = "a3f09b2c11dd44ee",
        currentMailbox: String = "a3f09b2c11dd44ee"
    ) -> Bool {
        RelayRegistrationService.needsRenewal(
            registeredAt: registeredAt,
            expiresAt: registeredAt.addingTimeInterval(lifetime),
            registeredDeviceToken: registeredToken,
            currentDeviceToken: currentToken,
            registeredMailboxId: registeredMailbox,
            currentMailboxId: currentMailbox,
            now: registeredAt.addingTimeInterval(elapsed)
        )
    }

    @Test("The renewal date is the midpoint of the token's actual life")
    func renewalDateIsMidpoint() {
        let expiresAt = registeredAt.addingTimeInterval(30 * day)
        let renewal = RelayRegistrationService.renewalDate(registeredAt: registeredAt, expiresAt: expiresAt)
        #expect(renewal == registeredAt.addingTimeInterval(15 * day))
    }

    @Test("A fresh 30-day token is not renewed on subsequent launches")
    func freshTokenIsNotRenewed() {
        #expect(!needsRenewal(elapsed: 60))
        #expect(!needsRenewal(elapsed: 1 * day))
        #expect(!needsRenewal(elapsed: 14 * day))
    }

    @Test("Renewal starts exactly at the midpoint, not a second before")
    func midpointBoundary() {
        #expect(!needsRenewal(elapsed: 15 * day - 1))
        #expect(needsRenewal(elapsed: 15 * day))
        #expect(needsRenewal(elapsed: 29 * day))
    }

    @Test("An expired token is renewed")
    func expiredTokenIsRenewed() {
        #expect(needsRenewal(elapsed: 40 * day))
    }

    /// The midpoint follows the relay-reported lifetime, not the 30-day
    /// constant: a relay that capped the token to 24h must not read as
    /// "less than half remains" on every launch.
    @Test("A relay-capped 24h token renews at 12h, not on every launch")
    func cappedTokenUsesActualLifetime() {
        #expect(!needsRenewal(elapsed: 60, lifetime: day))
        #expect(!needsRenewal(elapsed: 11 * 3600, lifetime: day))
        #expect(needsRenewal(elapsed: 12 * 3600, lifetime: day))
    }

    @Test("A changed device token renews immediately")
    func changedTokenRenews() {
        #expect(needsRenewal(elapsed: 60, registeredToken: "token-a", currentToken: "token-b"))
    }

    @Test("A registration for another wallet's mailbox renews immediately")
    func otherMailboxRenews() {
        #expect(needsRenewal(elapsed: 60, registeredMailbox: "deadbeef00000000"))
    }

    @Test("Mailbox ids compare case-insensitively")
    func mailboxCaseInsensitive() {
        #expect(!needsRenewal(elapsed: 60, registeredMailbox: "A3F09B2C11DD44EE"))
    }

    @Test("Missing state always renews")
    func missingStateRenews() {
        let now = registeredAt.addingTimeInterval(60)
        let expiresAt = registeredAt.addingTimeInterval(30 * day)

        #expect(RelayRegistrationService.needsRenewal(
            registeredAt: nil, expiresAt: expiresAt,
            registeredDeviceToken: "token-a", currentDeviceToken: "token-a",
            registeredMailboxId: "m", currentMailboxId: "m", now: now))
        #expect(RelayRegistrationService.needsRenewal(
            registeredAt: registeredAt, expiresAt: nil,
            registeredDeviceToken: "token-a", currentDeviceToken: "token-a",
            registeredMailboxId: "m", currentMailboxId: "m", now: now))
        #expect(needsRenewal(elapsed: 60, currentToken: nil))
        #expect(needsRenewal(elapsed: 60, registeredToken: nil))
        #expect(needsRenewal(elapsed: 60, registeredMailbox: nil))
    }
}

/// Pins the UserDefaults round trip of the persisted registration: what a
/// cold launch reads back must be what the last successful registration
/// wrote, and clearing must leave nothing behind that a new wallet could
/// inherit.
@Suite("Relay Registration Persistence Tests")
struct RelayRegistrationPersistenceTests {

    private func isolatedDefaults() -> UserDefaults {
        let suite = "RelayRegistrationPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Nothing persisted reads as an empty registration")
    func emptyByDefault() {
        let defaults = isolatedDefaults()
        #expect(RelayRegistrationService.load(from: defaults) == .empty)
    }

    @Test("A registration survives the round trip with second precision")
    func roundTrip() {
        let defaults = isolatedDefaults()
        let registration = RelayRegistrationService.PersistedRegistration(
            authHash: "abc123",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            registeredAt: Date(timeIntervalSince1970: 1_697_408_000),
            deviceToken: "device-token",
            mailboxId: "a3f09b2c11dd44ee"
        )

        RelayRegistrationService.persist(registration, to: defaults)

        #expect(RelayRegistrationService.load(from: defaults) == registration)
    }

    @Test("Persisting .empty removes every key")
    func emptyClearsKeys() {
        let defaults = isolatedDefaults()
        RelayRegistrationService.persist(
            RelayRegistrationService.PersistedRegistration(
                authHash: "abc123",
                expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                registeredAt: Date(timeIntervalSince1970: 1_697_408_000),
                deviceToken: "device-token",
                mailboxId: "a3f09b2c11dd44ee"
            ),
            to: defaults
        )

        RelayRegistrationService.persist(.empty, to: defaults)

        for key in UserDefaults.relayRegistrationKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) should be removed")
        }
        #expect(RelayRegistrationService.load(from: defaults) == .empty)
    }

    /// The wipe path removes the keys directly (no service instance around);
    /// the key list it iterates must be the same one the service writes.
    @Test("The wipe key list covers every persisted field")
    func wipeKeyListIsComplete() {
        let defaults = isolatedDefaults()
        RelayRegistrationService.persist(
            RelayRegistrationService.PersistedRegistration(
                authHash: "h", expiresAt: Date(), registeredAt: Date(),
                deviceToken: "t", mailboxId: "m"
            ),
            to: defaults
        )

        for key in UserDefaults.relayRegistrationKeys {
            defaults.removeObject(forKey: key)
        }

        #expect(RelayRegistrationService.load(from: defaults) == .empty)
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
