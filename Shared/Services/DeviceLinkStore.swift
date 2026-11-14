//
//  DeviceLinkStore.swift
//  Arké
//
//  Created by Assistant on 11/13/26.
//

import Foundation

/// This install's link to the account's wallet (Device_Linking.md §2.1).
///
/// Per-install state in UserDefaults: deleting the app removes it, and its
/// absence means "this install has not linked the account's wallet", which
/// is exactly what the link screen asks about. Never synced. Written by
/// `DeviceRegistrationService.registerCurrentDevice` (create, import and,
/// until the link screen lands, the detection-path registration), cleared by
/// `WalletDataCleanupService` on every deletion.
nonisolated struct DeviceLinkRecord: Equatable, Sendable {
    /// Hash of the wallet this install linked (the same PBKDF2 hash the KVS
    /// wallet-hash key carries)
    let walletHash: String
    let linkedAt: Date
}

/// Why a link record does or does not stand (Device_Linking.md §2.2).
nonisolated enum LinkValidity: Equatable, Sendable {
    /// Record present, hash matches the account (or KVS is blank while the
    /// seed is present), own registry row present
    case valid
    /// No record: a fresh install, a reinstall, or an install that removed
    /// the wallet locally
    case noRecord
    /// The account now holds a different wallet than the one this install
    /// linked (iCloud account switched, or the wallet was replaced)
    case walletChanged
    /// Record present but this device's own registry row is gone. Rows are
    /// written locally at registration and deleted only by the registry
    /// service or the cleanup service, so this means another device
    /// unlinked this one.
    case ownRowMissing
}

/// What the launch path knows about this device's own registry row when the
/// link record is evaluated.
nonisolated enum OwnRowEvidence: Equatable, Sendable {
    case primary
    case secondary
    /// The registry answered and has no row for this device
    case absent
    /// The registry could not be asked: no model context (headless launch)
    /// or a fetch error. Not evidence either way.
    case unavailable
}

nonisolated enum DeviceLinkStore {
    static let walletHashKey = "com.arke.link.walletHash"
    static let linkedAtKey = "com.arke.link.linkedAt"

    static func record(defaults: UserDefaults = .standard) -> DeviceLinkRecord? {
        guard let hash = defaults.string(forKey: walletHashKey), !hash.isEmpty else { return nil }
        let seconds = defaults.double(forKey: linkedAtKey)
        let linkedAt = seconds > 0 ? Date(timeIntervalSince1970: seconds) : .distantPast
        return DeviceLinkRecord(walletHash: hash, linkedAt: linkedAt)
    }

    /// Records that this install linked `walletHash`. Idempotent: a repeat
    /// for the same hash keeps the original link date.
    static func recordLink(walletHash: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        if let existing = record(defaults: defaults), existing.walletHash == walletHash {
            return
        }
        defaults.set(walletHash, forKey: walletHashKey)
        defaults.set(now.timeIntervalSince1970, forKey: linkedAtKey)
    }

    static func clearLink(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: walletHashKey)
        defaults.removeObject(forKey: linkedAtKey)
    }

    /// Pure validity decision, extracted for testability.
    ///
    /// A blank `accountHash` is not proof the account wallet is gone: KVS is
    /// transiently empty after an iCloud sign-in and before its first sync
    /// (the same lesson as `tombstoneRouting`). While the seed is present the
    /// record stands; only a *different* hash contradicts it. The own-row
    /// check applies only when the registry actually answered.
    static func validity(
        record: DeviceLinkRecord?,
        accountHash: String?,
        seedPresent: Bool,
        ownRow: OwnRowEvidence
    ) -> LinkValidity {
        guard let record else { return .noRecord }

        if let accountHash, !accountHash.isEmpty {
            if accountHash != record.walletHash { return .walletChanged }
        } else if !seedPresent {
            // No hash and no seed: nothing corroborates the record. Treated
            // as changed rather than valid so an install signed out of iCloud
            // does not pass as linked; the launch check (step 5) gives this
            // case its own screen.
            return .walletChanged
        }

        if case .absent = ownRow { return .ownRowMissing }
        return .valid
    }
}
