//
//  HandoverReadinessTests.swift
//  ArkéTests
//
//  Flow 4.3 branch A's wait (Device_Linking.md §14): promote only when the
//  old primary's row has flipped AND its final backup, written after the
//  flip, has been downloaded here. Created by Assistant on 11/14/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Handover Readiness")
struct HandoverReadinessTests {

    @Test("Nothing has happened on the other device yet")
    func waiting() {
        #expect(HandoverReadiness.evaluate(otherFlag: true, otherRowIsPrimary: true, backupReady: false) == .waitingForHandover)
        #expect(HandoverReadiness.evaluate(otherFlag: nil, otherRowIsPrimary: true, backupReady: false) == .waitingForHandover)
    }

    @Test("The fast flag flips before the row: started, not ready")
    func flagBeforeRow() {
        // Promotion would still be refused while the row says primary
        #expect(HandoverReadiness.evaluate(otherFlag: false, otherRowIsPrimary: true, backupReady: false) == .handoverStarted)
    }

    @Test("Row flipped but the backup has not arrived: wait, never promote")
    func rowBeforeBackup() {
        // Promoting here would restore whatever stale copy the slot holds —
        // the funds-visibility hazard the two-condition wait exists for
        #expect(HandoverReadiness.evaluate(otherFlag: false, otherRowIsPrimary: false, backupReady: false) == .waitingForBackup)
        #expect(HandoverReadiness.evaluate(otherFlag: nil, otherRowIsPrimary: false, backupReady: false) == .waitingForBackup)
    }

    @Test("Row flipped and the newer backup is here: ready")
    func ready() {
        #expect(HandoverReadiness.evaluate(otherFlag: false, otherRowIsPrimary: false, backupReady: true) == .ready)
    }

    @Test("A backup alone never makes it ready while the row says primary")
    func backupWithoutRowIsNotReady() {
        #expect(HandoverReadiness.evaluate(otherFlag: true, otherRowIsPrimary: true, backupReady: true) == .waitingForHandover)
    }
}

@Suite("Backup Slot Monitor Predicates")
struct BackupSlotMonitorTests {

    private let flip = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(uploaded: Bool? = nil, uploading: Bool? = nil, status: String? = nil, changed: Date? = nil) -> BackupSlotMonitor.Snapshot {
        BackupSlotMonitor.Snapshot(isUploaded: uploaded, isUploading: uploading, downloadingStatus: status, contentChangeDate: changed)
    }

    @Test("Upload is complete only for a backup written after the demotion that iCloud reports uploaded")
    func uploadComplete() {
        #expect(BackupSlotMonitor.uploadComplete(snapshot(uploaded: true, changed: flip.addingTimeInterval(10)), writtenAfter: flip))
        // An older upload is the previous backup, not the final one
        #expect(!BackupSlotMonitor.uploadComplete(snapshot(uploaded: true, changed: flip.addingTimeInterval(-10)), writtenAfter: flip))
        #expect(!BackupSlotMonitor.uploadComplete(snapshot(uploaded: false, changed: flip.addingTimeInterval(10)), writtenAfter: flip))
        #expect(!BackupSlotMonitor.uploadComplete(snapshot(uploaded: true, uploading: true, changed: flip.addingTimeInterval(10)), writtenAfter: flip))
        #expect(!BackupSlotMonitor.uploadComplete(snapshot(uploaded: true), writtenAfter: flip))
    }

    @Test("Only a current local copy of a backup written after the demotion counts")
    func downloadedBackupIsNewer() {
        let current = NSMetadataUbiquitousItemDownloadingStatusCurrent
        #expect(BackupSlotMonitor.downloadedBackupIsNewer(snapshot(status: current, changed: flip.addingTimeInterval(30)), than: flip))
        // Older than the demotion: the previous backup. Both dates come from
        // the old primary's clock, so there is no tolerance to hide behind.
        #expect(!BackupSlotMonitor.downloadedBackupIsNewer(snapshot(status: current, changed: flip.addingTimeInterval(-1)), than: flip))
        // Known to iCloud but not local: not usable yet
        #expect(!BackupSlotMonitor.downloadedBackupIsNewer(snapshot(status: NSMetadataUbiquitousItemDownloadingStatusNotDownloaded, changed: flip.addingTimeInterval(30)), than: flip))
        // "Downloaded" is a stale local copy with a newer version pending — not usable (F3)
        #expect(!BackupSlotMonitor.downloadedBackupIsNewer(snapshot(status: NSMetadataUbiquitousItemDownloadingStatusDownloaded, changed: flip.addingTimeInterval(30)), than: flip))
        #expect(!BackupSlotMonitor.downloadedBackupIsNewer(snapshot(changed: flip.addingTimeInterval(30)), than: flip))
    }

    @Test("A download is requested for missing and stale local copies, not for current ones")
    func needsDownload() {
        #expect(BackupSlotMonitor.needsDownload(snapshot(status: NSMetadataUbiquitousItemDownloadingStatusNotDownloaded)))
        #expect(BackupSlotMonitor.needsDownload(snapshot(status: NSMetadataUbiquitousItemDownloadingStatusDownloaded)))
        #expect(!BackupSlotMonitor.needsDownload(snapshot(status: NSMetadataUbiquitousItemDownloadingStatusCurrent)))
        #expect(!BackupSlotMonitor.needsDownload(snapshot()))
    }
}
