//
//  FastRegistryEntryTests.swift
//  ArkéTests
//
//  The fast KVS registry entry carries the device's identity since
//  2026-11-14 (Device_Linking.md §5.2); readers must still accept the old
//  timestamp-only value, and an unreadable value must still count as a
//  device. Created by Assistant on 11/14/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Fast Registry Entry")
struct FastRegistryEntryTests {

    private static let hash = "Zm9vYmFyaGFzaA=="
    private static let me = "11111111-1111-1111-1111-111111111111"
    private static let other = "22222222-2222-2222-2222-222222222222"
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func mirrorKey(_ deviceId: String) -> String {
        "\(DeviceRegistrationService.registeredDevicesPrefix)\(hash).\(deviceId)"
    }

    private static func identityKey(_ deviceId: String) -> String {
        "\(DeviceRegistrationService.deviceIdentityPrefix)\(hash).\(deviceId)"
    }

    @Test("The registration value stays a bare timestamp, readable by every build")
    func registrationTimestamp() {
        let entry = FastRegistryEntry.parse(registered: 1_699_000_000.0, identity: nil)
        #expect(entry.registeredAt == Date(timeIntervalSince1970: 1_699_000_000))
        #expect(entry.deviceName == nil)
        #expect(entry.platform == nil)
    }

    @Test("The identity sibling adds name and platform")
    func identitySibling() {
        let entry = FastRegistryEntry.parse(registered: 1_699_000_000.0, identity: ["name": "iPhone 17", "platform": "iOS"])
        #expect(entry == FastRegistryEntry(registeredAt: Date(timeIntervalSince1970: 1_699_000_000), deviceName: "iPhone 17", platform: .iOS))
    }

    @Test("Garbage parses to empty fields, never to nothing")
    func garbageIsEmptyEntry() {
        // The registration key alone blocks a wipe; the values only decorate the row
        #expect(FastRegistryEntry.parse(registered: "not a timestamp", identity: "junk") == FastRegistryEntry(registeredAt: nil, deviceName: nil, platform: nil))
        #expect(FastRegistryEntry.parse(registered: nil, identity: nil) == FastRegistryEntry(registeredAt: nil, deviceName: nil, platform: nil))
        #expect(FastRegistryEntry.parse(registered: nil, identity: ["platform": "watchOS"]).platform == nil)
        #expect(FastRegistryEntry.parse(registered: nil, identity: ["name": ""]).deviceName == nil)
    }

    @Test("The identity encoding round-trips beside an unchanged timestamp")
    func roundTrip() {
        let entry = FastRegistryEntry(registeredAt: Self.now, deviceName: "Christoph's Mac", platform: .macOS)
        #expect(FastRegistryEntry.parse(registered: Self.now.timeIntervalSince1970, identity: entry.encodedIdentity()) == entry)
    }

    @Test("Identity keys are mirror state: removed with the device, never counted as a device")
    func identityKeysAreMirrorState() {
        let keys = [Self.mirrorKey(Self.other), Self.identityKey(Self.other), Self.identityKey(Self.me)]
        #expect(Set(DeviceRegistrationService.mirrorKeys(forDeviceId: Self.other, in: keys)) == [Self.mirrorKey(Self.other), Self.identityKey(Self.other)])
        // An identity key alone is not a registration
        #expect(DeviceRegistrationService.otherRegisteredDeviceIds(kvsKeys: [Self.identityKey(Self.other)], walletHash: Self.hash, currentDeviceId: Self.me).isEmpty)
    }

    @Test("A mirror-only device is drawn from its entry: name, platform and role")
    func reportCarriesIdentity() {
        let entries: [String: Any] = [
            Self.mirrorKey(Self.other): 1_699_000_000.0,
            Self.identityKey(Self.other): ["name": "iPhone 17", "platform": "iOS"],
            DeviceRegistrationService.primaryFlagKey(deviceId: Self.other): false
        ]
        let report = DeviceRegistrationService.otherDeviceReport(
            kvsEntries: entries, walletHash: Self.hash, registryDevices: [],
            currentDeviceId: Self.me, registryError: nil, now: Self.now
        )
        let device = try? #require(report.mirrorOnly.first)
        #expect(device?.deviceName == "iPhone 17")
        #expect(device?.platform == .iOS)
        #expect(device?.isPrimary == false)
        #expect(device?.registeredAt == Date(timeIntervalSince1970: 1_699_000_000))
    }

    @Test("A registry row's name wins over the entry's")
    func rowNameWins() {
        let entries: [String: Any] = [
            Self.mirrorKey(Self.other): 1_699_000_000.0,
            Self.identityKey(Self.other): ["name": "iPhone", "platform": "iOS"]
        ]
        let row = RegistryDeviceSnapshot(deviceId: Self.other, deviceName: "Christoph's iPhone", walletHash: Self.hash,
                                         lastSeenAt: Self.now.addingTimeInterval(-60 * 24 * 60 * 60), isActive: false)
        let report = DeviceRegistrationService.otherDeviceReport(
            kvsEntries: entries, walletHash: Self.hash, registryDevices: [row],
            currentDeviceId: Self.me, registryError: nil, now: Self.now
        )
        #expect(report.mirrorOnly.first?.deviceName == "Christoph's iPhone")
    }

    @Test("An old entry without identity still blocks and stays unnamed")
    func legacyEntryBlocksUnnamed() {
        let report = DeviceRegistrationService.otherDeviceReport(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0], walletHash: Self.hash, registryDevices: [],
            currentDeviceId: Self.me, registryError: nil, now: Self.now
        )
        #expect(report.hasOthers)
        #expect(report.mirrorOnly.first?.deviceName == nil)
        #expect(report.mirrorOnly.first?.isPrimary == nil)
    }
}
