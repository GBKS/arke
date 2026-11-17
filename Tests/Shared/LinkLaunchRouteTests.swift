//
//  LinkLaunchRouteTests.swift
//  ArkéTests
//
//  DeviceLinkStore.launchRoute — the launch decision over the link record
//  (Device_Linking.md §12.1). Replaces the tombstone routing tests.
//  Created by Assistant on 11/14/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Link Launch Route")
struct LinkLaunchRouteTests {

    private let record = DeviceLinkRecord(walletHash: "hash-A", linkedAt: Date(timeIntervalSince1970: 1_760_000_000))
    private let left = DeviceLeftRecord(walletHash: "hash-A", leftAt: Date(timeIntervalSince1970: 1_761_000_000))

    private func route(
        record: DeviceLinkRecord? = nil,
        left: DeviceLeftRecord? = nil,
        hash: String? = nil,
        seedFound: Bool = false,
        seedUnreadable: Bool = false,
        ownRow: OwnRowEvidence = .absent,
        iCloudAccount: ICloudAccountPresence = .unknown
    ) -> LinkLaunchRoute {
        DeviceLinkStore.launchRoute(record: record, left: left, accountHash: hash, seedFound: seedFound, seedUnreadable: seedUnreadable, ownRow: ownRow, iCloudAccount: iCloudAccount)
    }

    // MARK: No record

    @Test("Nothing anywhere is onboarding")
    func freshInstallOnFreshAccount() {
        #expect(route() == .noAccountWallet)
    }

    @Test("An account wallet with no record asks to link")
    func newDevice() {
        #expect(route(hash: "hash-A") == .awaitingLink(.newDevice))
        #expect(route(seedFound: true) == .awaitingLink(.newDevice))
        #expect(route(hash: "hash-A", seedFound: true) == .awaitingLink(.newDevice))
    }

    @Test("An install from before the record existed heals itself when its own row is present")
    func selfHeal() {
        // The upgrade cohort: a primary or secondary that linked months ago
        #expect(route(hash: "hash-A", seedFound: true, ownRow: .primary) == .selfHeal)
        #expect(route(hash: "hash-A", ownRow: .secondary) == .selfHeal)
    }

    @Test("A left breadcrumb beats the self-heal: a local deletion whose unregister kept the row is not undone")
    func leftBreadcrumbBeatsSelfHeal() {
        // Range review 2026-11-16, G1/D1: step 1's unregister may retain the
        // row by design; the next cold launch must still show "you removed"
        #expect(route(left: left, hash: "hash-A", seedFound: true, ownRow: .primary) == .awaitingLink(.removedHere(leftAt: left.leftAt)))
        #expect(route(left: left, hash: "hash-A", ownRow: .secondary) == .awaitingLink(.removedHere(leftAt: left.leftAt)))
        // Breadcrumb for another wallet: still no self-heal, a new device
        #expect(route(left: left, hash: "hash-B", ownRow: .primary) == .awaitingLink(.newDevice))
    }

    @Test("A row registered under another wallet never heals or links")
    func otherWalletRowIsNoEvidence() {
        // The upgrade cohort after a wipe-and-recreate elsewhere: the old
        // primary row must not write a record for the new wallet
        #expect(route(hash: "hash-B", seedFound: true, ownRow: .otherWallet) == .awaitingLink(.newDevice))
        #expect(route(record: record, hash: "hash-A", seedFound: true, ownRow: .otherWallet) == .awaitingLink(.removedByAnotherDevice))
    }

    @Test("A reinstall sees the link screen until its row has imported")
    func reinstallAsksFirst() {
        // Own row absent locally until the first CloudKit import
        #expect(route(hash: "hash-A", seedFound: true, ownRow: .absent) == .awaitingLink(.newDevice))
        #expect(route(hash: "hash-A", seedFound: true, ownRow: .unavailable) == .awaitingLink(.newDevice))
    }

    @Test("A local delete is remembered as 'you removed this wallet'")
    func removedHere() {
        #expect(route(left: left, hash: "hash-A", seedFound: true) == .awaitingLink(.removedHere(leftAt: left.leftAt)))
        // A different wallet on the account is a new device, not a return
        #expect(route(left: left, hash: "hash-B") == .awaitingLink(.newDevice))
    }

    @Test("Unreadable keychain and blank KVS on an install that held a wallet waits for iCloud")
    func waitingForICloud() {
        // The tombstone's KVS-transient job: never onboarding here
        #expect(route(left: left, seedUnreadable: true) == .awaitingLink(.waitingForICloud))
        // Without the breadcrumb it is a fresh install with a flaky keychain
        #expect(route(seedUnreadable: true) == .noAccountWallet)
    }

    // MARK: Record present

    @Test("A valid record proceeds to ordinary detection")
    func linked() {
        #expect(route(record: record, hash: "hash-A", seedFound: true, ownRow: .primary) == .linked)
        #expect(route(record: record, hash: "hash-A", ownRow: .secondary) == .linked)
        // Blank KVS with the seed present is a known transient
        #expect(route(record: record, seedFound: true, ownRow: .primary) == .linked)
    }

    @Test("A record whose own row is gone means another device unlinked this one")
    func removedByAnotherDevice() {
        #expect(route(record: record, hash: "hash-A", seedFound: true, ownRow: .absent) == .awaitingLink(.removedByAnotherDevice))
    }

    @Test("An unavailable registry never reads as unlinked")
    func unavailableIsNotUnlinked() {
        #expect(route(record: record, hash: "hash-A", seedFound: true, ownRow: .unavailable) == .linked)
    }

    @Test("A record for another wallet, or for a wallet the account no longer has, blocks on the mismatch screen")
    func walletMismatch() {
        // Never fall through to detection: that would register under the new
        // wallet and pair local files with it (S10)
        #expect(route(record: record, hash: "hash-B", seedFound: true, ownRow: .primary) == .awaitingLink(.walletMismatch(.differentAccount)))
        // Full wipe elsewhere or iCloud sign-out: hash gone and seed gone; the
        // account status tells the two apart, and its absence is said so
        #expect(route(record: record, ownRow: .absent) == .awaitingLink(.walletMismatch(.undetermined)))
        #expect(route(record: record, ownRow: .absent, iCloudAccount: .present) == .awaitingLink(.walletMismatch(.undetermined)))
        #expect(route(record: record, ownRow: .absent, iCloudAccount: .absent) == .awaitingLink(.walletMismatch(.signedOut)))
    }

    @Test("The left breadcrumb is stale once the account definitively holds nothing or another wallet")
    func leftBreadcrumbStaleness() {
        // Wipe elsewhere: the breadcrumb must go, or creation is refused forever
        #expect(DeviceLinkStore.leftBreadcrumbIsStale(left: left, accountHash: nil, seedFound: false, seedUnreadable: false))
        #expect(DeviceLinkStore.leftBreadcrumbIsStale(left: left, accountHash: "hash-B", seedFound: true, seedUnreadable: false))
        // Still the same wallet, or unknown: keep it
        #expect(!DeviceLinkStore.leftBreadcrumbIsStale(left: left, accountHash: "hash-A", seedFound: false, seedUnreadable: false))
        #expect(!DeviceLinkStore.leftBreadcrumbIsStale(left: left, accountHash: nil, seedFound: true, seedUnreadable: false))
        #expect(!DeviceLinkStore.leftBreadcrumbIsStale(left: left, accountHash: nil, seedFound: false, seedUnreadable: true))
        #expect(!DeviceLinkStore.leftBreadcrumbIsStale(left: nil, accountHash: nil, seedFound: false, seedUnreadable: false))
    }

    @Test("A record with the seed unreadable and no hash keeps the record standing")
    func unreadableKeychainWithRecord() {
        // Locked keychain is unknown, not absence: do not call the wallet changed
        #expect(route(record: record, seedUnreadable: true, ownRow: .unavailable) == .linked)
    }
}
