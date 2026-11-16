//
//  BackupSlotMonitor.swift
//  Arké
//
//  Created by Assistant on 11/14/26.
//

import Foundation
import OSLog

/// Watches the wallet database's iCloud Drive backup slot (Device_Linking.md
/// §4.3, §14).
///
/// `WalletBackupService` reads the slot with plain file attributes, which
/// only say what the local ubiquity cache holds. The handover needs more: the
/// old primary must know its final backup has *uploaded* before it tells the
/// user to continue elsewhere, and the new primary must see a backup *newer
/// than the handover* and *downloaded* before it restores. Both come from
/// `NSMetadataQuery` over the ubiquitous data scope.
///
/// Polling with one-shot gathers rather than live updates: the two waits are
/// bounded, a gather is cheap, and live-update bookkeeping for a query that
/// lives seconds is more code than it saves.
@MainActor
final class BackupSlotMonitor {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "BackupSlotMonitor")

    /// What a gather says about the slot file. Nil fields mean the attribute
    /// was absent.
    nonisolated struct Snapshot: Equatable, Sendable {
        let isUploaded: Bool?
        let isUploading: Bool?
        let downloadingStatus: String?
        let contentChangeDate: Date?
    }

    /// The slot file, `Backups/db.sqlite` in the ubiquity container. Nil when
    /// iCloud is unavailable.
    nonisolated static func slotURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(WalletBackupService.currentDatabaseFileName)
    }

    // MARK: - Pure predicates

    /// The demoting side's condition: the final backup left this device.
    nonisolated static func uploadComplete(_ snapshot: Snapshot, writtenAfter since: Date) -> Bool {
        guard let changed = snapshot.contentChangeDate, changed >= since else { return false }
        return snapshot.isUploaded == true && snapshot.isUploading != true
    }

    /// The promoting side's condition: a backup written after `reference` is
    /// present locally in its latest version. Only `Current` counts:
    /// `Downloaded` means "a local version exists, the latest will download
    /// as soon as possible", which is a stale copy (review 2026-11-14, F3).
    /// `reference` should be stamped by the same clock as the backup — the
    /// old primary's `demotedAt`, written by the old primary — so no skew
    /// tolerance is needed.
    nonisolated static func downloadedBackupIsNewer(_ snapshot: Snapshot, than reference: Date) -> Bool {
        guard let changed = snapshot.contentChangeDate, changed > reference else { return false }
        return snapshot.downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent
    }

    /// Whether a download request is worth issuing: the item is known to
    /// iCloud and the local copy is missing or behind
    nonisolated static func needsDownload(_ snapshot: Snapshot) -> Bool {
        snapshot.downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded
            || snapshot.downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusDownloaded
    }

    /// Asks iCloud for the slot's latest version. Harmless when current.
    func requestDownload() {
        guard let url = Self.slotURL() else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            Self.logger.warning("Backup download request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func snapshot(from item: NSMetadataItem) -> Snapshot {
        Snapshot(
            isUploaded: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool,
            isUploading: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool,
            downloadingStatus: item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
            contentChangeDate: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
        )
    }

    // MARK: - Waits

    /// Waits until the slot's backup written after `since` has uploaded.
    /// - Returns: false on timeout or when iCloud is unavailable.
    func waitForUpload(after since: Date, timeout: Duration) async -> Bool {
        await poll(timeout: timeout) { snapshot in
            Self.uploadComplete(snapshot, writtenAfter: since)
        }
    }

    /// Waits until a backup newer than `reference` is downloaded here,
    /// requesting the download whenever the item is known but not local.
    func waitForDownloadedBackup(newerThan reference: Date, timeout: Duration) async -> Bool {
        await poll(timeout: timeout) { snapshot in
            if Self.needsDownload(snapshot) { requestDownload() }
            return Self.downloadedBackupIsNewer(snapshot, than: reference)
        }
    }

    /// Branches B and C (Device_Linking.md §14.3, F4): before promoting on a
    /// device that may never have downloaded the slot, make sure the slot's
    /// latest version is local, so `restoreWalletIfNeeded` restores it rather
    /// than finding a placeholder and starting fresh. Returns false when there
    /// is no slot item at all, or the download did not finish in time.
    func ensureSlotIsLocal(timeout: Duration) async -> Bool {
        await poll(timeout: timeout) { snapshot in
            if Self.needsDownload(snapshot) { requestDownload() }
            return snapshot.downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent
        }
    }

    /// One gather now, for status lines.
    func currentSnapshot() async -> Snapshot? {
        await gather()
    }

    private func poll(timeout: Duration, until condition: (Snapshot) -> Bool) async -> Bool {
        guard Self.slotURL() != nil else {
            Self.logger.warning("iCloud container unavailable — cannot watch the backup slot")
            return false
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let snapshot = await gather(), condition(snapshot) {
                return true
            }
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return false }
        }
        Self.logger.notice("Backup slot wait timed out after \(String(describing: timeout), privacy: .public)")
        return false
    }

    /// Runs a metadata query for the slot file and returns its attributes,
    /// or nil when the file is unknown to iCloud (or the query fails).
    private func gather() async -> Snapshot? {
        guard let slotURL = Self.slotURL() else { return nil }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(
            format: "%K LIKE %@",
            NSMetadataItemPathKey,
            "*/Backups/\(WalletBackupService.currentDatabaseFileName)"
        )
        let gatherer = Gatherer(query: query, slotPath: slotURL.path)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Snapshot?, Never>) in
            gatherer.start(continuation: continuation)
        }
    }

    /// Owns one query's lifetime: the observer token, the single resume, and
    /// the result extraction. Main-actor, like the query's notifications.
    @MainActor
    private final class Gatherer {
        private let query: NSMetadataQuery
        private let slotPath: String
        private var observer: NSObjectProtocol?
        private var resumed = false

        init(query: NSMetadataQuery, slotPath: String) {
            self.query = query
            self.slotPath = slotPath
        }

        func start(continuation: CheckedContinuation<Snapshot?, Never>) {
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue (see addObserver above)
                MainActor.assumeIsolated {
                    self?.finish(continuation: continuation)
                }
            }
            if !query.start() {
                BackupSlotMonitor.logger.warning("NSMetadataQuery failed to start")
                finish(continuation: continuation, failed: true)
                return
            }
            // A gather that never finishes must not park the waiting task
            // forever (and with it a cancelled flow). Ten seconds is generous
            // for a one-file query.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish(continuation: continuation, failed: true)
            }
        }

        private func finish(continuation: CheckedContinuation<Snapshot?, Never>, failed: Bool = false) {
            guard !resumed else { return }
            resumed = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if failed {
                continuation.resume(returning: nil)
                return
            }
            query.disableUpdates()
            let items = (query.results as? [NSMetadataItem]) ?? []
            let match = items.first { ($0.value(forAttribute: NSMetadataItemPathKey) as? String) == slotPath } ?? items.first
            let snapshot = match.map(BackupSlotMonitor.snapshot(from:))
            query.stop()
            continuation.resume(returning: snapshot)
        }
    }
}
