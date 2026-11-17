//
//  RestoreExitGuardTests.swift
//  ArkéTests
//
//  WalletManager.restoreExitBlocked — the pre-import re-check behind the
//  launch-check restore exit (Device_Linking.md §17.4, F7 on the I1 fix,
//  DECIDED 2026-11-17). Failure mode: restoring into an account that has
//  meanwhile gained a wallet again, writing this wallet's seed, hash and
//  database over the account's.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Restore Exit Guard")
struct RestoreExitGuardTests {

    @Test("Blank KVS and a definitively absent seed let the restore proceed")
    func emptyAccountProceeds() {
        #expect(!WalletManager.restoreExitBlocked(kvsHash: nil, mnemonicStatus: .notFound))
        #expect(!WalletManager.restoreExitBlocked(kvsHash: "", mnemonicStatus: .notFound))
    }

    @Test("Any KVS hash blocks, this wallet's included")
    func anyHashBlocks() {
        // Another device recreated the account's wallet: its hash arrived first
        #expect(WalletManager.restoreExitBlocked(kvsHash: "hash-Y", mnemonicStatus: .notFound))
        // The account re-synced this wallet's own hash: detection will say linked
        #expect(WalletManager.restoreExitBlocked(kvsHash: "hash-X", mnemonicStatus: .notFound))
    }

    @Test("A seed that is found or unreadable blocks")
    func seedPresenceBlocks() {
        #expect(WalletManager.restoreExitBlocked(kvsHash: nil, mnemonicStatus: .found))
        #expect(WalletManager.restoreExitBlocked(kvsHash: nil, mnemonicStatus: .unavailable(-25308)))
    }
}
