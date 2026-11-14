//
//  DeviceLinkValidityTests.swift
//  ArkéTests
//
//  The per-install link record and its validity rule (Device_Linking.md §2).
//  Created by Assistant on 11/13/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Device Link Validity")
struct DeviceLinkValidityTests {

    private let record = DeviceLinkRecord(walletHash: "hash-A", linkedAt: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("No record means this install has not linked anything")
    func noRecord() {
        #expect(DeviceLinkStore.validity(record: nil, accountHash: "hash-A", seedPresent: true, ownRow: .primary) == .noRecord)
    }

    @Test("Matching hash with an own row is valid, whatever the role")
    func matchingHashIsValid() {
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-A", seedPresent: true, ownRow: .primary) == .valid)
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-A", seedPresent: false, ownRow: .secondary) == .valid)
    }

    @Test("A different account hash means the wallet changed")
    func differentHashIsWalletChanged() {
        // iCloud account switched, or the account wallet was replaced: local
        // files must never be paired with another wallet's data (S10)
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-B", seedPresent: true, ownRow: .primary) == .walletChanged)
    }

    @Test("A blank KVS hash with the seed present keeps the record valid")
    func blankHashWithSeedIsTransient() {
        // KVS is empty after an iCloud sign-in and before its first sync; the
        // seed corroborates the record (same lesson as tombstoneRouting)
        #expect(DeviceLinkStore.validity(record: record, accountHash: nil, seedPresent: true, ownRow: .primary) == .valid)
        #expect(DeviceLinkStore.validity(record: record, accountHash: "", seedPresent: true, ownRow: .unavailable) == .valid)
    }

    @Test("A blank KVS hash without the seed does not pass as linked")
    func blankHashWithoutSeedIsNotValid() {
        // Signed out of iCloud, or the wallet was wiped elsewhere: nothing
        // corroborates the record, so it must not open anything
        #expect(DeviceLinkStore.validity(record: record, accountHash: nil, seedPresent: false, ownRow: .unavailable) == .walletChanged)
    }

    @Test("A record whose own row is gone means another device unlinked this one")
    func missingOwnRow() {
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-A", seedPresent: true, ownRow: .absent) == .ownRowMissing)
    }

    @Test("An unavailable registry is not evidence of a missing row")
    func unavailableRegistryIsNotMissing() {
        // Headless launches never configure the registry's model context
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-A", seedPresent: true, ownRow: .unavailable) == .valid)
    }

    @Test("Hash mismatch wins over a missing row")
    func walletChangedBeatsOwnRowMissing() {
        #expect(DeviceLinkStore.validity(record: record, accountHash: "hash-B", seedPresent: true, ownRow: .absent) == .walletChanged)
    }

    @Test("Recording a link is idempotent for the same hash and replaces for a new one")
    func storeRoundTrip() throws {
        let suite = "com.arke.test.link.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(DeviceLinkStore.record(defaults: defaults) == nil)

        let first = Date(timeIntervalSince1970: 1_760_000_000)
        DeviceLinkStore.recordLink(walletHash: "hash-A", now: first, defaults: defaults)
        #expect(DeviceLinkStore.record(defaults: defaults) == DeviceLinkRecord(walletHash: "hash-A", linkedAt: first))

        // A repeat registration for the same wallet keeps the original date
        DeviceLinkStore.recordLink(walletHash: "hash-A", now: first.addingTimeInterval(3_600), defaults: defaults)
        #expect(DeviceLinkStore.record(defaults: defaults)?.linkedAt == first)

        // A different wallet replaces the record
        let second = first.addingTimeInterval(86_400)
        DeviceLinkStore.recordLink(walletHash: "hash-B", now: second, defaults: defaults)
        #expect(DeviceLinkStore.record(defaults: defaults) == DeviceLinkRecord(walletHash: "hash-B", linkedAt: second))

        DeviceLinkStore.clearLink(defaults: defaults)
        #expect(DeviceLinkStore.record(defaults: defaults) == nil)
    }
}
