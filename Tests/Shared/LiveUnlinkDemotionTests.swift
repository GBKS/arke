//
//  LiveUnlinkDemotionTests.swift
//  ArkéTests
//
//  DeviceRegistrationService.liveUnlinkVerdict — a running device whose own
//  registry row disappears was unlinked or wiped by another device: a
//  primary closes bark now, not at the next launch, and every role leaves
//  the wallet UI for the link screen (Device_Linking.md §11.6).
//  Created by Assistant on 11/14/26.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Live Unlink Verdict")
struct LiveUnlinkDemotionTests {

    private typealias Action = DeviceRegistrationService.LiveUnlinkAction

    private func verdict(present: Bool = true, primary: Bool, ownRow: OwnRowEvidence, deleting: Bool = false) -> Action {
        DeviceRegistrationService.liveUnlinkVerdict(ownRowWasPresent: present, ownRowWasPrimary: primary, ownRow: ownRow, deletionInProgress: deleting)
    }

    @Test("A primary whose own row vanished closes the wallet and re-routes")
    func primaryWithRowGoneCloses() {
        // The 2026-11-14 device run: B unlinked A, A's log showed only B's
        // row, and A kept bark open until relaunch
        #expect(verdict(primary: true, ownRow: .absent) == .closeWalletAndReroute)
    }

    @Test("A secondary whose own row vanished re-routes without closing anything")
    func secondaryWithRowGoneReroutes() {
        // Found on device 2026-11-14: the first build only watched primaries,
        // so an unlinked secondary stayed in the wallet UI
        #expect(verdict(primary: false, ownRow: .absent) == .reroute)
    }

    @Test("A row that is still there, in either role, is nothing")
    func presentRowDoesNothing() {
        #expect(verdict(primary: true, ownRow: .primary) == .none)
        // A row flipped to secondary is reconciliation's business, handled by
        // the self-demotion path with its own breadcrumb
        #expect(verdict(primary: true, ownRow: .secondary) == .none)
        #expect(verdict(primary: false, ownRow: .secondary) == .none)
    }

    @Test("An unavailable registry is not evidence of a missing row")
    func unavailableDoesNothing() {
        // The F3 lesson: a fetch error must never read as "another device
        // unlinked you"
        #expect(verdict(primary: true, ownRow: .unavailable) == .none)
        #expect(verdict(primary: false, ownRow: .unavailable) == .none)
    }

    @Test("A row that was never seen cannot vanish")
    func neverPresentDoesNothing() {
        // Fresh install before linking, or a link whose registration failed
        #expect(verdict(present: false, primary: false, ownRow: .absent) == .none)
    }

    @Test("A deletion in progress deletes its own row and must not trigger a second shutdown")
    func deletionInProgressSuppresses() {
        // The full wipe forbids the backup a migration shutdown writes
        // (contract rule 17); the deletion flow owns the teardown
        #expect(verdict(primary: true, ownRow: .absent, deleting: true) == .none)
        #expect(verdict(primary: false, ownRow: .absent, deleting: true) == .none)
    }
}
