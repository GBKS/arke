//
//  LiveUnlinkDemotionTests.swift
//  ArkéTests
//
//  DeviceRegistrationService.liveDemotionVerdict — a running primary whose
//  own registry row disappears was unlinked or wiped by another device and
//  must close bark now, not at the next launch (Device_Linking.md §11.6).
//  Created by Assistant on 11/14/26.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Live Unlink Demotion")
struct LiveUnlinkDemotionTests {

    @Test("A primary whose own row vanished is demoted")
    func primaryWithRowGoneDemotes() {
        // The 2026-11-14 device run: B unlinked A, A's log showed only B's
        // row, and A kept bark open until relaunch
        #expect(DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: true, ownRow: .absent, deletionInProgress: false))
    }

    @Test("A row that is still there, in either role, is not a demotion")
    func presentRowDoesNotDemote() {
        #expect(!DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: true, ownRow: .primary, deletionInProgress: false))
        // A row flipped to secondary is reconciliation's business, handled by
        // the self-demotion path with its own breadcrumb
        #expect(!DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: true, ownRow: .secondary, deletionInProgress: false))
    }

    @Test("An unavailable registry is not evidence of a missing row")
    func unavailableDoesNotDemote() {
        // The F3 lesson: a fetch error must never read as "another device
        // unlinked you"
        #expect(!DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: true, ownRow: .unavailable, deletionInProgress: false))
    }

    @Test("A device that was never primary has nothing to close")
    func secondaryNeverDemotes() {
        #expect(!DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: false, ownRow: .absent, deletionInProgress: false))
    }

    @Test("A deletion in progress deletes its own row and must not trigger a second shutdown")
    func deletionInProgressSuppresses() {
        // The full wipe forbids the backup a migration shutdown writes
        // (contract rule 17); the deletion flow owns the teardown
        #expect(!DeviceRegistrationService.liveDemotionVerdict(ownRowWasPrimary: true, ownRow: .absent, deletionInProgress: true))
    }
}
