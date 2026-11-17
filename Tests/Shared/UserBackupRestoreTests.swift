//
//  UserBackupRestoreTests.swift
//  ArkéTests
//
//  WalletBackupService.restoreFromUserBackup and its rollback: the database a
//  user-picked backup file replaces is parked, not removed, until the import
//  settles (range review 2026-11-16, I1). Failure modes: a failed import
//  leaving no database at all; a rollback that forgets the parked copy; a
//  success that leaves the parked copy behind. The slot restore
//  (restoreFromBackup(overwriteExisting:)) parks the same way since the D2
//  ruling of the same review; its tests sit at the end.
//

import Foundation
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("User Backup Restore Tests")
struct UserBackupRestoreTests {

    private func makeWalletDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserBackupRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A file that passes the service's SQLite header check
    private func writeSQLiteLikeFile(named name: String, payload: String, in directory: URL) throws -> URL {
        var data = Data("SQLite format 3\0".utf8)
        data.append(Data(payload.utf8))
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func contents(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    @Test("Restoring over an existing database parks it instead of removing it")
    func existingDatabaseIsParked() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet X", in: directory)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        let service = WalletBackupService(walletDirectory: directory)

        #expect(try await service.restoreFromUserBackup(sourceFileURL: picked))

        let parked = directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName)
        #expect(try contents(live) == contents(picked))
        #expect(try contents(parked).suffix(8) == Data("wallet X".utf8))
    }

    @Test("Rolling back a failed import puts the previous database back")
    func rollbackRestoresPreviousDatabase() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet X", in: directory)
        let original = try contents(live)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "wrong phrase", in: directory)
        let service = WalletBackupService(walletDirectory: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)

        try service.rollBackUserBackupRestore()

        #expect(try contents(live) == original)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName).path))
    }

    @Test("Rolling back with nothing to put back leaves no database, as before")
    func rollbackWithoutPreviousDatabase() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "fresh install", in: directory)
        let service = WalletBackupService(walletDirectory: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)

        try service.rollBackUserBackupRestore()

        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName).path))
    }

    @Test("A successful import discards the parked copy and keeps the restored one")
    func successDiscardsParkedCopy() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet X", in: directory)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "newer backup", in: directory)
        let service = WalletBackupService(walletDirectory: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)

        service.discardPreservedDatabase()

        #expect(try contents(live) == contents(picked))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName).path))
    }

    @Test("Rolling back after a crash between park and copy still puts the previous database back")
    func rollbackWithoutRestoredCopy() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parked = try writeSQLiteLikeFile(named: WalletBackupService.preservedDatabaseFileName, payload: "wallet X", in: directory)
        let original = try contents(parked)
        let service = WalletBackupService(walletDirectory: directory)

        try service.rollBackUserBackupRestore()

        let live = directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName)
        #expect(try contents(live) == original)
        #expect(!FileManager.default.fileExists(atPath: parked.path))
    }

    @Test("A stale parked copy is cleared even when no live database exists")
    func staleParkedCopyClearedWithoutLiveDatabase() async throws {
        // Otherwise a later failed import would put a seedless old database
        // back under the live name (adversarial pass 2026-11-17, F4)
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = try writeSQLiteLikeFile(named: WalletBackupService.preservedDatabaseFileName, payload: "stale", in: directory)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        let service = WalletBackupService(walletDirectory: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        try service.rollBackUserBackupRestore()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName).path))
    }

    @Test("A hot journal is parked with its database and comes back with it")
    func journalTravelsWithDatabase() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet X", in: directory)
        let journal = directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName + "-journal")
        try Data("hot journal".utf8).write(to: journal)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        let service = WalletBackupService(walletDirectory: directory)

        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)
        // The restored copy has no journal of its own
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName + "-journal").path))

        try service.rollBackUserBackupRestore()
        #expect(try contents(live).suffix(8) == Data("wallet X".utf8))
        #expect(try contents(journal) == Data("hot journal".utf8))
        #expect(!service.hasStrandedParkedDatabase)
    }

    @Test("A stale parked copy from an earlier attempt is replaced, not kept")
    func staleParkedCopyIsReplaced() async throws {
        let directory = try makeWalletDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try writeSQLiteLikeFile(named: WalletBackupService.preservedDatabaseFileName, payload: "stale", in: directory)
        _ = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet X", in: directory)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        let service = WalletBackupService(walletDirectory: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)

        let parked = directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName)
        #expect(try contents(parked).suffix(8) == Data("wallet X".utf8))
    }

    // MARK: - Slot restore (range review 2026-11-16, D2)

    private func makeSlotDirectory(payload: String) throws -> URL {
        let slot = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserBackupRestoreTests-slot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        _ = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: payload, in: slot)
        return slot
    }

    @Test("A slot restore over an existing database parks it instead of removing it")
    func slotRestoreParksExistingDatabase() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)

        #expect(await service.restoreFromBackup(overwriteExisting: true))

        let parked = directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName)
        #expect(try contents(live).suffix(9) == Data("slot copy".utf8))
        #expect(try contents(parked).suffix(8) == Data("wallet Y".utf8))
    }

    @Test("A slot copy that does not open is rolled back to the parked database")
    func slotRestoreRollbackPutsOwnDatabaseBack() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let original = try contents(live)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)
        _ = await service.restoreFromBackup(overwriteExisting: true)

        try service.rollBackUserBackupRestore()

        #expect(try contents(live) == original)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName).path))
    }

    @Test("A slot restore without overwrite leaves an existing database and parks nothing")
    func slotRestoreWithoutOverwriteIsANoOp() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let original = try contents(live)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)

        #expect(await service.restoreFromBackup(overwriteExisting: false) == false)

        #expect(try contents(live) == original)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName).path))
    }

    @Test("A slot copy never confirmed by an open leaves the parked database stranded until it is put back")
    func unconfirmedSlotRestoreIsStranded() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let original = try contents(live)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)
        _ = await service.restoreFromBackup(overwriteExisting: true)

        // Killed between the copy and the open: a new launch sees this
        #expect(service.hasStrandedParkedDatabase)
        try service.rollBackUserBackupRestore()
        #expect(try contents(live) == original)
        #expect(!service.hasStrandedParkedDatabase)
    }

    @Test("A confirmed slot copy and a backup-file import's park are not stranded")
    func confirmedSlotCopyAndImportParkAreOwned() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        _ = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)
        _ = await service.restoreFromBackup(overwriteExisting: true)
        service.discardPreservedDatabase()
        #expect(!service.hasStrandedParkedDatabase)

        // An import's parked database with the restored copy beside it belongs
        // to the running import, not to the launch guard
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)
        #expect(!service.hasStrandedParkedDatabase)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(WalletBackupService.currentDatabaseFileName))
        #expect(service.hasStrandedParkedDatabase)
    }

    @Test("A slot restore refuses to clear a parked database an import still owns")
    func slotRestoreRefusesOverImportPark() async throws {
        let directory = try makeWalletDirectory()
        let slot = try makeSlotDirectory(payload: "slot copy")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: slot) }
        let live = try writeSQLiteLikeFile(named: WalletBackupService.currentDatabaseFileName, payload: "wallet Y", in: directory)
        let picked = try writeSQLiteLikeFile(named: "picked.sqlite", payload: "backup file", in: directory)
        let service = WalletBackupService(walletDirectory: directory, backupDirectory: slot)
        _ = try await service.restoreFromUserBackup(sourceFileURL: picked)  // the import's park: wallet Y parked, backup file live

        #expect(await service.restoreFromBackup(overwriteExisting: true) == false)

        #expect(try contents(live) == contents(picked))
        #expect(try contents(directory.appendingPathComponent(WalletBackupService.preservedDatabaseFileName)).suffix(8) == Data("wallet Y".utf8))
        try service.rollBackUserBackupRestore()
        #expect(try contents(live).suffix(8) == Data("wallet Y".utf8))
    }
}
