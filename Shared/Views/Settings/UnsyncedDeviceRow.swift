//
//  UnsyncedDeviceRow.swift
//  Arké
//
//  Created by Assistant on 09/24/26.
//

import SwiftUI
import ArkeUI

/// A device the account's fast iCloud KVS mirror knows about, but the
/// CloudKit-backed registry does not.
///
/// These used to be invisible, which is what made the 2026-09-23 dead end
/// undiagnosable: Linked Devices read the registry and said "1 device" while the
/// delete flow read the mirror and refused the full wipe, with nothing on screen
/// to reconcile the two. An entry the user cannot see is an entry they cannot
/// act on — and a mirror-only entry is precisely the kind that has no registry
/// row for `unlinkDevice` to remove.
///
/// Deliberately not a `DeviceRow`: there is no platform, no primary status and
/// no heartbeat to show, and borrowing that row's shape would imply we know more
/// than we do.
struct UnsyncedDeviceRow: View {
    let device: OtherWalletDevice

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// A mirror entry carries no name of its own. One is shown only when some
    /// other registry row happens to know this device id.
    private var title: String {
        device.deviceName
            ?? String(localized: "linked_devices_unsynced_device", defaultValue: "Unrecognized device")
    }

    private var subtitle: String {
        guard let registeredAt = device.registeredAt else {
            return String(localized: "linked_devices_unsynced_device_description",
                          defaultValue: "Registered to this wallet on this iCloud account. Its details haven't reached this device.")
        }

        // "Registered", never "last seen": the mirror's timestamp is written at
        // registration and heartbeats never refresh it
        return String(format: String(localized: "linked_devices_unsynced_device_registered %@",
                                     defaultValue: "Registered %@. Its details haven't reached this device."),
                      registeredAt.formatted(date: .abbreviated, time: .omitted))
    }
}

#Preview("Named") {
    List {
        UnsyncedDeviceRow(device: OtherWalletDevice(
            deviceId: "22222222-2222-2222-2222-222222222222",
            deviceName: "Old iPhone",
            lastSeenAt: nil,
            registeredAt: Date(timeIntervalSince1970: 1_756_000_000),
            isStale: false,
            source: .kvsOnly
        ))
    }
}

#Preview("Unnamed, no timestamp") {
    List {
        UnsyncedDeviceRow(device: OtherWalletDevice(
            deviceId: "22222222-2222-2222-2222-222222222222",
            deviceName: nil,
            lastSeenAt: nil,
            registeredAt: nil,
            isStale: false,
            source: .kvsOnly
        ))
    }
}
