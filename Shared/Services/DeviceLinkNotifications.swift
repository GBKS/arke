//
//  DeviceLinkNotifications.swift
//  Arké
//
//  Created by Assistant on 11/14/26.
//

import Foundation
import UserNotifications
import OSLog

/// The receiving end of a link (Device_Linking.md §4.2, DECIDED 2026-10-10):
/// when another device links the wallet, every existing device gets a local
/// notification. It is the only visibility a user has of an iCloud-account
/// compromise, and the confirmation for an honest new device.
nonisolated enum DeviceLinkNotifications {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "DeviceLinkNotifications")

    static func notifyDeviceLinked(deviceName: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            logger.info("New-device notification skipped: notifications not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification_device_linked_title", defaultValue: "New device linked")
        content.body = String(format: String(localized: "notification_device_linked_body %@",
                                             defaultValue: "%@ now shows your wallet. If that wasn't you, check Settings › Devices."),
                              deviceName)
        content.sound = .default
        content.categoryIdentifier = "DEVICE_LINKED"

        let request = UNNotificationRequest(
            identifier: "device-linked-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            logger.notice("Posted new-device notification for \(deviceName, privacy: .public)")
        } catch {
            logger.warning("New-device notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
