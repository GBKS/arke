//
//  MnemonicChecksumTests.swift
//  ArkéTests
//
//  Pins, by execution, how a BIP39 mnemonic with a bad checksum or a
//  non-wordlist word is treated by (a) bark's `validateMnemonic`,
//  (b) the app's `SecurityService.isValidBIP39` pre-check, and
//  (c) bark's `OnchainWallet.default` constructor.
//
//  Observed 2026-10-09 against bark-ffi-bindings v0.25.0+bark-0.7.1
//  (157b0fc) on the iPhone 17 Pro simulator; the assertions below pin
//  that behaviour. (c) throws locally in ~0.3–1.2 s without touching
//  the network, so it is safe to run with invalid phrases only.
//
//  Created by Christoph on 10/9/26.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Mnemonic Checksum Tests")
struct MnemonicChecksumTests {

    // MARK: - Fixtures

    /// Valid 12-word phrase (the canonical BIP39 test vector).
    static let validPhrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    /// All wordlist words, but the checksum is wrong (12 × "abandon").
    static let badChecksumPhrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"

    /// Twelve words, last one is not in the BIP39 wordlist.
    static let nonWordlistPhrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zzzzz"

    private static func freshTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MnemonicChecksumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs `OnchainWallet.default` against a fresh temp datadir and returns the
    /// `Bark.Error.Inner` message, or nil if the call unexpectedly succeeded or
    /// threw a different error type.
    private static func onchainWalletDefaultErrorMessage(for phrase: String) async throws -> String? {
        let dir = try freshTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await OnchainWallet.default(
                network: .signet,
                mnemonic: phrase,
                config: BarkWalletFFI.makeConfig(from: .signet),
                datadir: dir.path
            )
            return nil
        } catch let error as Bark.Error {
            guard case let .Inner(message) = error else {
                Issue.record("Unexpected Bark.Error case: \(error)")
                return nil
            }
            return message
        }
    }

    // MARK: - (a) Bark validateMnemonic

    @Test("bark validateMnemonic accepts a valid phrase")
    func barkValidateMnemonicAcceptsValid() throws {
        #expect(try validateMnemonic(mnemonic: Self.validPhrase) == true)
    }

    @Test("bark validateMnemonic returns false (does not throw) for a bad checksum")
    func barkValidateMnemonicRejectsBadChecksum() throws {
        #expect(try validateMnemonic(mnemonic: Self.badChecksumPhrase) == false)
    }

    @Test("bark validateMnemonic returns false (does not throw) for a non-wordlist word")
    func barkValidateMnemonicRejectsNonWordlist() throws {
        #expect(try validateMnemonic(mnemonic: Self.nonWordlistPhrase) == false)
    }

    // MARK: - (b) App pre-check

    @Test("SecurityService.isValidBIP39 only checks word count: passes all three phrases")
    @MainActor
    func appValidatorIsWordCountOnly() {
        let service = SecurityService(taskManager: TaskDeduplicationManager())
        #expect(service.isValidBIP39(Self.validPhrase) == true)
        // Pinned gap: the app pre-check does NOT catch a bad checksum or an unknown word.
        #expect(service.isValidBIP39(Self.badChecksumPhrase) == true)
        #expect(service.isValidBIP39(Self.nonWordlistPhrase) == true)
    }

    // MARK: - (c) OnchainWallet.default with invalid phrases only

    @Test("OnchainWallet.default rejects a bad-checksum phrase before any network use", .timeLimit(.minutes(1)))
    func onchainWalletDefaultRejectsBadChecksum() async throws {
        let message = try await Self.onchainWalletDefaultErrorMessage(for: Self.badChecksumPhrase)
        #expect(message == "invalid mnemonic: the mnemonic has an invalid checksum")
    }

    @Test("OnchainWallet.default rejects a non-wordlist phrase before any network use", .timeLimit(.minutes(1)))
    func onchainWalletDefaultRejectsNonWordlist() async throws {
        let message = try await Self.onchainWalletDefaultErrorMessage(for: Self.nonWordlistPhrase)
        #expect(message == "invalid mnemonic: mnemonic contains an unknown word (word 11)")
    }
}
