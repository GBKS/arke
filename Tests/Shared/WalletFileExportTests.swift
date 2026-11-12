//
//  WalletFileExportTests.swift
//  ArkéTests
//
//  The shareable copy of the live wallet database that the delete flow's
//  export step hands to the share sheet. Failure modes: the wrong file
//  picked up, the legacy name missed, the live file handed out instead of
//  a copy.
//

import Foundation
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Wallet File Export Tests")
struct WalletFileExportTests {

    private func makeWalletDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalletFileExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("The live database is copied, not handed out")
    func liveDatabaseIsCopied() throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName)
        let bytes = Data("live wallet state".utf8)
        try bytes.write(to: live)

        let shared = try #require(WalletBackupService(walletDirectory: directory).getShareableWalletFileURL())
        defer { try? FileManager.default.removeItem(at: shared) }

        #expect(shared.standardizedFileURL != live.standardizedFileURL)
        #expect(try Data(contentsOf: shared) == bytes)
        #expect(shared.pathExtension == "sqlite")
    }

    @Test("A legacy-named database is still exported")
    func legacyNameIsExported() throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("legacy wallet state".utf8)
        try bytes.write(to: directory.appendingPathComponent(WalletBackupService.legacyDatabaseFileName))

        let shared = try #require(WalletBackupService(walletDirectory: directory).getShareableWalletFileURL())
        defer { try? FileManager.default.removeItem(at: shared) }

        #expect(try Data(contentsOf: shared) == bytes)
    }

    // The newest-wins rule between the local file and the iCloud slot. The
    // slot itself cannot be placed in a test, so the rule is tested on its
    // own; `getShareableWalletFileURL` feeds it the two candidates.

    @Test("The local file wins unless the slot file is strictly newer")
    func newestWinsBetweenLocalAndSlot() throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = directory.appendingPathComponent("local.sqlite")
        let slot = directory.appendingPathComponent("slot.sqlite")
        try Data("local".utf8).write(to: local)
        try Data("slot".utf8).write(to: slot)

        let older = Date(timeIntervalSinceNow: -3600)
        let newer = Date()
        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: local.path)
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: slot.path)
        #expect(WalletBackupService.newerFile(preferred: local, other: slot) == local)

        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: local.path)
        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: slot.path)
        #expect(WalletBackupService.newerFile(preferred: local, other: slot) == slot)

        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: local.path)
        #expect(WalletBackupService.newerFile(preferred: local, other: slot) == local, "tie keeps the local file")
    }

    @Test("A missing candidate on either side yields the other, none yields nil")
    func missingCandidates() throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = directory.appendingPathComponent("local.sqlite")
        try Data("local".utf8).write(to: local)

        #expect(WalletBackupService.newerFile(preferred: local, other: nil) == local)
        #expect(WalletBackupService.newerFile(preferred: nil, other: local) == local)
        #expect(WalletBackupService.newerFile(preferred: nil, other: nil) == nil)
        // An unreadable date on the other side keeps the preferred file
        let ghost = directory.appendingPathComponent("ghost.sqlite")
        #expect(WalletBackupService.newerFile(preferred: local, other: ghost) == local)
    }

    @Test("The live file wins over the legacy one when both exist")
    func liveFileWinsOverLegacy() throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let liveBytes = Data("live".utf8)
        try liveBytes.write(to: directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName))
        try Data("legacy".utf8).write(to: directory.appendingPathComponent(WalletBackupService.legacyDatabaseFileName))

        let shared = try #require(WalletBackupService(walletDirectory: directory).getShareableWalletFileURL())
        defer { try? FileManager.default.removeItem(at: shared) }

        #expect(try Data(contentsOf: shared) == liveBytes)
    }
}
