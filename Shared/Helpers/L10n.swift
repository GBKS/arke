//
//  L10n.swift
//  Arké
//
//  Single definition point for localized strings used at 3+ call sites
//  (decision D2 in Shared/Docs/Localization/Default_Value_Migration_Plan.md).
//  Keeping one defaultValue per key prevents copy drift between call sites
//  and extraction conflicts in Localizable.xcstrings.
//
//  Grows batch by batch during the defaultValue migration; keep alphabetical.
//  Computed properties (not stored) so lookups respect the current locale.
//

import Foundation

enum L10n {

    static var buttonCancel: String {
        String(localized: "button_cancel", defaultValue: "Cancel")
    }

    static var buttonUnlink: String {
        String(localized: "button_unlink", defaultValue: "Unlink")
    }

    static var sectionDeviceRole: String {
        String(localized: "section_device_role", defaultValue: "Device Role")
    }

    static var settingsDangerZone: String {
        String(localized: "settings_danger_zone", defaultValue: "Danger Zone")
    }

    static var settingsLinkedDevices: String {
        String(localized: "settings_linked_devices", defaultValue: "Devices")
    }

    static var settingsThisDeviceParentheses: String {
        String(localized: "settings_this_device_parentheses", defaultValue: "(This Device)")
    }

    static var statusFullWallet: String {
        String(localized: "status_full_wallet", defaultValue: "Primary")
    }

    static var statusMetadataOnly: String {
        String(localized: "status_metadata_only", defaultValue: "Secondary")
    }

    static var symbolBullet: String {
        String(localized: "symbol_bullet", defaultValue: "•")
    }
}
