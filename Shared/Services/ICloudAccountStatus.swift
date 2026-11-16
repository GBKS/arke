//
//  ICloudAccountStatus.swift
//  Arké
//
//  Created by Assistant on 11/16/26.
//

import Foundation
import CloudKit
import OSLog

/// Whether this device has an iCloud account, for the launch check
/// (Device_Linking.md §4.5, §15). Apple's guidance for CloudKit clients is
/// `CKContainer.accountStatus()`, not the ubiquity identity token.
enum ICloudAccountStatus {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ICloudAccountStatus")

    /// The app's CloudKit container, the same one the model container syncs to
    static let containerIdentifier = "iCloud.gbks.sigma"

    /// Mapped conservatively: only `.available` and `.noAccount` are evidence
    nonisolated static func presence(of status: CKAccountStatus) -> ICloudAccountPresence {
        switch status {
        case .available: return .present
        case .noAccount: return .absent
        default: return .unknown
        }
    }

    static func presence() async -> ICloudAccountPresence {
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            let presence = presence(of: status)
            logger.info("iCloud account status \(status.rawValue) → \(String(describing: presence), privacy: .public)")
            return presence
        } catch {
            logger.warning("iCloud account status unavailable: \(error.localizedDescription, privacy: .public)")
            return .unknown
        }
    }
}

/// The iCloud account identity for the launch check (Device_Linking.md
/// §4.5, §15.4 F2). `ubiquityIdentityToken` is Apple's signal for "did the
/// iCloud account change" for apps that use iCloud Drive and KVS, which Arké
/// does for the backup slot and the wallet-hash key; it is opaque, local and
/// synchronous. Stored archived at link time, compared with `isEqual` at
/// launch. CloudKit's own account status stays the sign-out signal.
enum ICloudAccountIdentity {
    /// The current token, archived for storage. Nil when signed out or when
    /// archiving fails.
    nonisolated static func currentTokenData() -> Data? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    }

    /// Whether the stored link-time identity is the current one. Nil when
    /// nothing was stored, nothing is current (signed out), or the stored
    /// data does not unarchive: never a guess.
    nonisolated static func matches(stored: Data?) -> Bool? {
        guard let stored, let current = FileManager.default.ubiquityIdentityToken else { return nil }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: stored) else { return nil }
        unarchiver.requiresSecureCoding = false
        guard let storedToken = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) else { return nil }
        unarchiver.finishDecoding()
        return current.isEqual(storedToken)
    }
}

