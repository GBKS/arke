//
//  KeychainAccessibilityMigrationTests.swift
//  ArkéTests
//
//  Tests for SecurityService.migrateItemToAfterFirstUnlock — the mnemonic keychain
//  accessibility migration to kSecAttrAccessibleAfterFirstUnlock
//  (Background_Execution.md, Phase 1).
//  Created by Christoph on 7/27/26.
//

import Testing
import Foundation
import Security

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Keychain Accessibility Migration Tests")
struct KeychainAccessibilityMigrationTests {

    private let account = "mnemonic-test"

    // MARK: - Helpers

    /// Each test uses its own scratch service name so tests never touch the real
    /// wallet item and can run in parallel.
    private func uniqueService() -> String {
        "com.arke.test.migration.\(UUID().uuidString)"
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true  // Match the real item's shape
        ]
    }

    private func addItem(service: String, value: String, accessible: CFString) throws {
        var query = baseQuery(service: service)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(query as CFDictionary, nil)
        try #require(status == errSecSuccess)
    }

    private func readItem(service: String) -> (accessible: String?, value: String?) {
        var query = baseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any] else {
            return (nil, nil)
        }
        let data = item[kSecValueData as String] as? Data
        return (
            item[kSecAttrAccessible as String] as? String,
            data.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    private func deleteItem(service: String) {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    // MARK: - Tests

    @Test("No item returns noItem and adds nothing")
    func noItem() {
        let service = uniqueService()
        defer { deleteItem(service: service) }

        let result = SecurityService.migrateItemToAfterFirstUnlock(service: service, account: account)

        #expect(result == .noItem)
        #expect(readItem(service: service).value == nil)
    }

    @Test("WhenUnlocked item migrates with value intact")
    func migratesLegacyItem() throws {
        let service = uniqueService()
        defer { deleteItem(service: service) }
        try addItem(service: service, value: "abandon ability able", accessible: kSecAttrAccessibleWhenUnlocked)

        let result = SecurityService.migrateItemToAfterFirstUnlock(service: service, account: account)

        #expect(result == .migrated)
        let item = readItem(service: service)
        #expect(item.accessible == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(item.value == "abandon ability able")
    }

    @Test("Second run is a no-op")
    func idempotent() throws {
        let service = uniqueService()
        defer { deleteItem(service: service) }
        try addItem(service: service, value: "abandon ability able", accessible: kSecAttrAccessibleWhenUnlocked)

        #expect(SecurityService.migrateItemToAfterFirstUnlock(service: service, account: account) == .migrated)
        #expect(SecurityService.migrateItemToAfterFirstUnlock(service: service, account: account) == .alreadyMigrated)

        let item = readItem(service: service)
        #expect(item.accessible == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(item.value == "abandon ability able")
    }

    @Test("Item already on the new class is left alone")
    func alreadyMigratedItem() throws {
        let service = uniqueService()
        defer { deleteItem(service: service) }
        try addItem(service: service, value: "abandon ability able", accessible: kSecAttrAccessibleAfterFirstUnlock)

        let result = SecurityService.migrateItemToAfterFirstUnlock(service: service, account: account)

        #expect(result == .alreadyMigrated)
        #expect(readItem(service: service).value == "abandon ability able")
    }
}

/// Tests for WalletDataCleanupService.deleteKeychainItem — the full-wipe mnemonic
/// deletion. Regression: the previous query omitted kSecAttrSynchronizable, so it
/// silently missed the iCloud-synced mnemonic and the seed survived every deletion.
@Suite("Wallet Cleanup Keychain Deletion Tests")
struct WalletCleanupKeychainDeletionTests {

    private let account = "mnemonic-test"

    // MARK: - Helpers

    /// Scratch service names keep tests off the real wallet item and parallel-safe.
    private func uniqueService() -> String {
        "com.arke.test.cleanup.\(UUID().uuidString)"
    }

    private func addItem(service: String, synchronizable: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecValueData as String: Data("abandon ability able".utf8)
        ]
        try #require(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
    }

    private func itemExists(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func deleteItem(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Tests

    @Test("Deletes an iCloud-synced item (the real mnemonic's shape)")
    func deletesSynchronizableItem() throws {
        let service = uniqueService()
        defer { deleteItem(service: service) }
        try addItem(service: service, synchronizable: true)

        try WalletDataCleanupService.deleteKeychainItem(service: service, account: account)

        #expect(!itemExists(service: service))
    }

    @Test("Deletes a legacy non-synced item")
    func deletesLegacyItem() throws {
        let service = uniqueService()
        defer { deleteItem(service: service) }
        try addItem(service: service, synchronizable: false)

        try WalletDataCleanupService.deleteKeychainItem(service: service, account: account)

        #expect(!itemExists(service: service))
    }

    @Test("Missing item does not throw")
    func missingItemDoesNotThrow() throws {
        try WalletDataCleanupService.deleteKeychainItem(service: uniqueService(), account: account)
    }
}
