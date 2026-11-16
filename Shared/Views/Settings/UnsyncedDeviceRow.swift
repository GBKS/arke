//
//  UnsyncedDeviceRow.swift
//  Arké
//
//  Created by Assistant on 09/24/26.
//

import SwiftUI
import ArkeUI

/// A device known from the account's fast iCloud KVS entry whose CloudKit
/// registry row has not reached this device, or never will.
///
/// These used to render as "Unrecognized device" with a warning icon and an
/// explainer about stores, which read as an intruder and gave the user
/// nothing to do. Since 2026-11-14 the fast entry carries the device's name
/// and platform, and its own primary flag is readable, so the row is drawn
/// like any other device (Device_Linking.md §5.2–5.3). The one honest
/// difference is the date line: "Linked …" from the entry's registration
/// timestamp, where a registry-backed row says "Last seen …". Sync state is
/// spoken only where it gates an action: the delete flow's blocker list.
struct UnsyncedDeviceRow: View {
    let device: OtherWalletDevice
    /// Offered in the row's context menu (touch and hold) when non-nil.
    var onUnlink: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // The store did not say which kind of device an old entry is, so
            // the row must not assert one
            if let platform = device.platform {
                Text(platform.icon)
                    .font(.system(size: 32))
                    .accessibilityHidden(true)
            } else {
                // Same generic glyph as the delete screen's blocker row; the
                // dashed square read as a checkbox (Christoph, 2026-11-16)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(for: device))
                    .font(.system(size: 16, weight: .medium))

                // An unnamed entry's title already carries the date
                if device.deviceName != nil {
                    HStack(spacing: 4) {
                        if let platform = device.platform {
                            Text(platform.displayName)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text(L10n.symbolBullet)
                                .foregroundColor(.secondary)
                        }
                        Text(dateLine)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                if let isPrimary = device.isPrimary {
                    MirrorRoleBadge(
                        text: isPrimary ? L10n.statusFullWallet : L10n.statusMetadataOnly,
                        color: isPrimary ? .Arke.blue : .Arke.orange
                    )
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            if let onUnlink {
                Button(role: .destructive, action: onUnlink) {
                    Label(String(localized: "settings_unlink_device", defaultValue: "Unlink Device"),
                          systemImage: "minus.circle")
                }
            }
        }
    }

    /// The entry's name, or for a pre-2026-11-14 entry without one, when it
    /// linked. Never "unrecognized": the user can act on it either way. Also
    /// the name the unlink dialog uses, so "Unlink Device linked 3 November"
    /// never becomes "Unlink this device", which names the phone in hand.
    static func title(for device: OtherWalletDevice) -> String {
        if let name = device.deviceName { return name }
        guard let registeredAt = device.registeredAt else {
            return String(localized: "linked_devices_device_linked_earlier", defaultValue: "Device linked earlier")
        }
        return String(format: String(localized: "linked_devices_device_linked_on %@", defaultValue: "Device linked %@",
                                     comment: "%@ is a date (abbreviated)"),
                      registeredAt.formatted(date: .abbreviated, time: .omitted))
    }

    /// "Linked", never "last seen": the entry's timestamp is written at
    /// registration and heartbeats never refresh it
    private var dateLine: String {
        guard let registeredAt = device.registeredAt else {
            return String(localized: "linked_devices_linked_earlier", defaultValue: "Linked earlier")
        }
        return String(format: String(localized: "linked_devices_linked_on %@", defaultValue: "Linked %@",
                                     comment: "%@ is a date (abbreviated)"),
                      registeredAt.formatted(date: .abbreviated, time: .omitted))
    }

    private var accessibilityLabel: String {
        var parts = [Self.title(for: device)]
        if let platform = device.platform { parts.append(platform.displayName) }
        if device.deviceName != nil { parts.append(dateLine) }
        if let isPrimary = device.isPrimary {
            parts.append(isPrimary ? L10n.statusFullWallet : L10n.statusMetadataOnly)
        }
        return parts.joined(separator: ", ")
    }
}

/// Role badge for the mirror-drawn row. The two app targets each have their
/// own badge view, so this file carries a private one.
private struct MirrorRoleBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

#Preview("Identity from the entry") {
    List {
        UnsyncedDeviceRow(device: OtherWalletDevice(
            deviceId: "22222222-2222-2222-2222-222222222222",
            deviceName: "iPhone 17",
            lastSeenAt: nil,
            registeredAt: Date(timeIntervalSince1970: 1_756_000_000),
            isStale: false,
            source: .kvsOnly,
            platform: .iOS,
            isPrimary: false
        ))
    }
}

#Preview("Old entry, no identity") {
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
