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
/// create, import and the link screen (replacing any record) and by
/// `DeviceRegistrationService.registerCurrentDevice` (only when no record
/// exists or the hash matches); cleared by `WalletDataCleanupService` on
/// every deletion.
nonisolated struct DeviceLinkRecord: Equatable, Sendable {
    /// Hash of the wallet this install linked (the same PBKDF2 hash the KVS
    /// wallet-hash key carries)
    let walletHash: String
    let linkedAt: Date
}

/// Survives a local-only deletion: the wallet this install last held and
/// when it left. Two jobs (Device_Linking.md §2.1, §6.4): the "you removed
/// this wallet" copy on the link screen, and routing to the link screen's
/// waiting variant instead of onboarding when the keychain is unreadable
/// and KVS is transiently blank. Cleared by the full wipe and by every link.
nonisolated struct DeviceLeftRecord: Equatable, Sendable {
    let walletHash: String
    let leftAt: Date
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

/// Why the link screen is being shown (Device_Linking.md §4.2). The screen
/// picks its copy from this plus what it learns after the first import.
nonisolated enum LinkPromptReason: Equatable, Sendable {
    /// No record, account has a wallet: a new device or a reinstall
    case newDevice
    /// The user removed the wallet from this install on `leftAt`
    case removedHere(leftAt: Date)
    /// Record present but this device's own row is gone: another device
    /// unlinked or wiped this one
    case removedByAnotherDevice
    /// Keychain unreadable and KVS blank, but this install held a wallet
    /// before: wait for iCloud instead of offering onboarding
    case waitingForICloud
    /// The record names a wallet the account no longer holds, or a different
    /// one: the wallet was deleted from another device, or this device is
    /// signed in to another iCloud account. No adoption, no registration, no
    /// bark; step 5 splits the two cases and adds the exits.
    case walletMismatch
}

/// The launch decision over the link record (Device_Linking.md §12.1).
nonisolated enum LinkLaunchRoute: Equatable, Sendable {
    /// No account wallet signal anywhere: onboarding
    case noAccountWallet
    /// The account has a wallet this install has not linked: the link screen
    case awaitingLink(LinkPromptReason)
    /// No record, but this device's own row exists: an install from before
    /// the record existed. Write the record silently and proceed.
    case selfHeal
    /// Record valid: proceed with the ordinary detection
    case linked
}

nonisolated enum DeviceLinkStore {
    static let walletHashKey = "com.arke.link.walletHash"
    static let linkedAtKey = "com.arke.link.linkedAt"
    static let leftWalletHashKey = "com.arke.link.leftWalletHash"
    static let leftAtKey = "com.arke.link.leftAt"

    // MARK: Link record

    static func record(defaults: UserDefaults = .standard) -> DeviceLinkRecord? {
        guard let hash = defaults.string(forKey: walletHashKey), !hash.isEmpty else { return nil }
        let seconds = defaults.double(forKey: linkedAtKey)
        let linkedAt = seconds > 0 ? Date(timeIntervalSince1970: seconds) : .distantPast
        return DeviceLinkRecord(walletHash: hash, linkedAt: linkedAt)
    }

    /// Records that this install linked `walletHash`.
    ///
    /// - Parameter replacingExisting: `true` for the explicit link writers
    ///   (create, import, the link screen). `false` for the registration
    ///   choke point, which must never re-point an install at another
    ///   wallet: with a record for a different hash present, nothing is
    ///   written and the caller's log line says so.
    /// - Returns: whether a record was written.
    @discardableResult
    static func recordLink(
        walletHash: String,
        replacingExisting: Bool,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let existing = record(defaults: defaults) {
            if existing.walletHash == walletHash { return false }
            if !replacingExisting { return false }
        }
        defaults.set(walletHash, forKey: walletHashKey)
        defaults.set(now.timeIntervalSince1970, forKey: linkedAtKey)
        // A link supersedes any memory of having left
        clearLeft(defaults: defaults)
        return true
    }

    static func clearLink(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: walletHashKey)
        defaults.removeObject(forKey: linkedAtKey)
    }

    // MARK: Left breadcrumb

    static func left(defaults: UserDefaults = .standard) -> DeviceLeftRecord? {
        guard let hash = defaults.string(forKey: leftWalletHashKey), !hash.isEmpty else { return nil }
        let seconds = defaults.double(forKey: leftAtKey)
        let leftAt = seconds > 0 ? Date(timeIntervalSince1970: seconds) : .distantPast
        return DeviceLeftRecord(walletHash: hash, leftAt: leftAt)
    }

    static func recordLeft(walletHash: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(walletHash, forKey: leftWalletHashKey)
        defaults.set(now.timeIntervalSince1970, forKey: leftAtKey)
    }

    static func clearLeft(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: leftWalletHashKey)
        defaults.removeObject(forKey: leftAtKey)
    }

    // MARK: Decisions

    /// Pure validity decision, extracted for testability.
    ///
    /// A blank `accountHash` is not proof the account wallet is gone: KVS is
    /// transiently empty after an iCloud sign-in and before its first sync.
    /// While the seed is present the record stands; only a *different* hash
    /// contradicts it. The own-row check applies only when the registry
    /// actually answered.
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

    /// The launch decision (Device_Linking.md §12.1), pure.
    ///
    /// - Parameters:
    ///   - seedFound / seedUnreadable: the two non-"not found" outcomes of the
    ///     keychain probe. Unreadable means "unknown", never "no wallet".
    static func launchRoute(
        record: DeviceLinkRecord?,
        left: DeviceLeftRecord?,
        accountHash: String?,
        seedFound: Bool,
        seedUnreadable: Bool,
        ownRow: OwnRowEvidence
    ) -> LinkLaunchRoute {
        let hashPresent = !(accountHash ?? "").isEmpty
        let accountHasWallet = hashPresent || seedFound
        let ownRowPresent = ownRow == .primary || ownRow == .secondary

        guard let record else {
            if !accountHasWallet {
                // The keychain could not be read and KVS is blank: for an
                // install that held a wallet before, that is "not yet", not
                // "nothing". Onboarding here could offer creating a second
                // wallet on the account (the creation guard still refuses).
                if seedUnreadable, left != nil { return .awaitingLink(.waitingForICloud) }
                return .noAccountWallet
            }
            if ownRowPresent { return .selfHeal }
            if let left, hashPresent, left.walletHash == accountHash {
                return .awaitingLink(.removedHere(leftAt: left.leftAt))
            }
            return .awaitingLink(.newDevice)
        }

        switch validity(record: record, accountHash: accountHash, seedPresent: seedFound || seedUnreadable, ownRow: ownRow) {
        case .valid:
            return .linked
        case .ownRowMissing:
            return .awaitingLink(.removedByAnotherDevice)
        case .walletChanged:
            // Never fall through to detection here: it would register this
            // device under the account's new wallet and pair local files with
            // it (S10). The screen blocks until step 5 adds the exits.
            return .awaitingLink(.walletMismatch)
        case .noRecord:
            return .awaitingLink(.newDevice)  // unreachable: record is non-nil
        }
    }

    /// Whether the left breadcrumb has outlived the wallet it remembers and
    /// must be cleared, or it would make the creation guard refuse forever
    /// (adversarial pass 2026-11-14, F1). Stale when the account definitively
    /// holds nothing (no hash, seed `.notFound`) or holds a different wallet.
    /// An unreadable keychain is unknown and keeps it.
    static func leftBreadcrumbIsStale(
        left: DeviceLeftRecord?,
        accountHash: String?,
        seedFound: Bool,
        seedUnreadable: Bool
    ) -> Bool {
        guard let left else { return false }
        if let accountHash, !accountHash.isEmpty { return accountHash != left.walletHash }
        return !seedFound && !seedUnreadable
    }
}
