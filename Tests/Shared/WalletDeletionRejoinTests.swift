//
//  WalletDeletionRejoinTests.swift
//  ArkéTests
//
//  Tests for the one-wallet-per-iCloud-account enforcement introduced in
//  Wallet_Deletion_And_Rejoin.md: the local-deletion tombstone routing, the
//  wallet-creation guard, and the wipe-coverage inventory that keeps
//  WalletDataCleanupService in sync with the app schema.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// MARK: - Tombstone Routing

@Suite("Tombstone Routing")
struct TombstoneRoutingTests {

    @Test("No tombstone routes to normal detection regardless of other signals")
    func noTombstone() {
        #expect(SecurityService.tombstoneRouting(tombstoneHash: nil, currentAccountHash: nil, mnemonicStatus: .notFound) == .none)
        #expect(SecurityService.tombstoneRouting(tombstoneHash: nil, currentAccountHash: "abc", mnemonicStatus: .found) == .none)
    }

    @Test("Tombstone matching the account hash offers rejoin")
    func matchingTombstone() {
        #expect(SecurityService.tombstoneRouting(tombstoneHash: "abc", currentAccountHash: "abc", mnemonicStatus: .found) == .rejoin)
    }

    @Test("Tombstone is stale only when hash AND seed are definitively gone")
    func staleTombstoneWalletFullyWiped() {
        // Full wipe elsewhere removes both the KVS hash and the synced seed
        #expect(SecurityService.tombstoneRouting(tombstoneHash: "abc", currentAccountHash: nil, mnemonicStatus: .notFound) == .stale)
    }

    @Test("Missing hash with the seed still present is a KVS transient — keep rejoining")
    func kvsTransientDoesNotClearTombstone() {
        // KVS cache can be momentarily blank (post sign-out/in, pre-initial-sync);
        // the still-synced seed proves the wallet exists — never resurrect, never clear
        #expect(SecurityService.tombstoneRouting(tombstoneHash: "abc", currentAccountHash: nil, mnemonicStatus: .found) == .rejoin)
    }

    @Test("Missing hash with an unreadable keychain keeps the tombstone")
    func unreadableKeychainDoesNotClearTombstone() {
        // Unknown is not evidence — low confidence must never clear or resurrect
        #expect(SecurityService.tombstoneRouting(tombstoneHash: "abc", currentAccountHash: nil, mnemonicStatus: .unavailable(-25308)) == .rejoin)
    }

    @Test("Tombstone is stale when the account wallet was replaced")
    func staleTombstoneDifferentWallet() {
        // A different hash is affirmative evidence of a new wallet (KVS transients
        // produce nil, not wrong values) — clear regardless of keychain state
        #expect(SecurityService.tombstoneRouting(tombstoneHash: "abc", currentAccountHash: "def", mnemonicStatus: .found) == .stale)
    }
}

// MARK: - Tombstone Persistence

@Suite("Tombstone Persistence", .serialized)
struct TombstonePersistenceTests {

    @Test("Record, read, and clear roundtrip")
    func roundtrip() {
        // Preserve any real tombstone on the developer's machine
        let original = SecurityService.localDeletionTombstoneHash()
        defer {
            if let original {
                SecurityService.recordLocalDeletionTombstone(walletHash: original)
            } else {
                SecurityService.clearLocalDeletionTombstone()
            }
        }

        SecurityService.recordLocalDeletionTombstone(walletHash: "test-hash-123")
        #expect(SecurityService.localDeletionTombstoneHash() == "test-hash-123")

        SecurityService.clearLocalDeletionTombstone()
        #expect(SecurityService.localDeletionTombstoneHash() == nil)
    }
}

// MARK: - Wallet Creation Guard

@Suite("Account Wallet Signals (creation guard)")
struct AccountWalletSignalsTests {

    @Test("Clean account allows creation")
    func cleanAccount() {
        #expect(!WalletManager.accountHasWalletSignals(
            kvsHashPresent: false, mnemonicStatus: .notFound, tombstonePresent: false))
    }

    @Test("KVS hash alone refuses creation")
    func kvsHash() {
        #expect(WalletManager.accountHasWalletSignals(
            kvsHashPresent: true, mnemonicStatus: .notFound, tombstonePresent: false))
    }

    @Test("Synced mnemonic alone refuses creation")
    func mnemonicFound() {
        #expect(WalletManager.accountHasWalletSignals(
            kvsHashPresent: false, mnemonicStatus: .found, tombstonePresent: false))
    }

    @Test("Tombstone alone refuses creation")
    func tombstone() {
        #expect(WalletManager.accountHasWalletSignals(
            kvsHashPresent: false, mnemonicStatus: .notFound, tombstonePresent: true))
    }

    @Test("Unreadable keychain alone does NOT refuse creation")
    func unavailableKeychainIsNoSignal() {
        // A transiently broken keychain on a genuinely fresh install must not
        // brick onboarding; KVS hash and tombstone still guard dangerous cases
        #expect(!WalletManager.accountHasWalletSignals(
            kvsHashPresent: false, mnemonicStatus: .unavailable(-25308), tombstonePresent: false))
    }
}

// MARK: - Wipe Coverage

@Suite("Wallet Wipe Coverage")
struct WalletWipeCoverageTests {

    private var coveredIdentifiers: Set<ObjectIdentifier> {
        Set(
            (WalletWipeCoverage.directlyWiped
             + WalletWipeCoverage.cascadeWiped
             + WalletWipeCoverage.exempt)
            .map { ObjectIdentifier($0) }
        )
    }

    @Test("Every schema model has a declared deletion fate")
    func schemaFullyCovered() {
        let covered = coveredIdentifiers
        for model in SwiftDataHelper.appSchemaModels {
            #expect(
                covered.contains(ObjectIdentifier(model)),
                "\(model) is in the app schema but has no deletion fate — add it to WalletWipeCoverage (directlyWiped, cascadeWiped, or exempt with a reason)"
            )
        }
    }

    @Test("Coverage lists contain no types outside the schema")
    func noPhantomCoverage() {
        let schema = Set(SwiftDataHelper.appSchemaModels.map { ObjectIdentifier($0) })
        for model in WalletWipeCoverage.directlyWiped + WalletWipeCoverage.cascadeWiped + WalletWipeCoverage.exempt {
            #expect(
                schema.contains(ObjectIdentifier(model)),
                "\(model) is listed in WalletWipeCoverage but absent from SwiftDataHelper.appSchemaModels — stale entry?"
            )
        }
    }

    @Test("No model is listed with two different fates")
    func noDoubleCoverage() {
        let all = (WalletWipeCoverage.directlyWiped
                   + WalletWipeCoverage.cascadeWiped
                   + WalletWipeCoverage.exempt)
            .map { ObjectIdentifier($0) }
        #expect(all.count == Set(all).count, "A model appears in more than one WalletWipeCoverage list")
    }

    @Test("Shared-state inventory is non-empty and has unique keys")
    func sharedStateInventoryConsistent() {
        let entries = SharedStateWipeCoverage.entries
        #expect(!entries.isEmpty)
        let keys = entries.map(\.key)
        #expect(keys.count == Set(keys).count, "Duplicate key in SharedStateWipeCoverage")
    }

    @Test("The seed, wallet hash, and network config are full-wipe-only")
    func criticalSharedStateIsFullWipeOnly() {
        // The two incident keys plus the seed: a device-scoped deletion must
        // never destroy these (2026-08-19 seed, 2026-08-20 network config)
        let fullWipeKeys = SharedStateWipeCoverage.entries
            .filter { if case .fullWipeOnly = $0.scope { return true }; return false }
            .map(\.key)
        #expect(fullWipeKeys.contains("com.arke.wallet / mnemonic"))
        #expect(fullWipeKeys.contains("com.arke.wallet.mnemonicHash"))
        #expect(fullWipeKeys.contains("com.arke.wallet.networkConfigId"))
    }
}

// MARK: - Deletion Strategy

@Suite("Deletion Strategy Evidence")
struct DeletionStrategyTests {

    @Test("Other devices present keeps the deletion local")
    func othersPresentIsLocalOnly() {
        #expect(WalletDataCleanupService.deletionStrategy(for: .othersPresent) == .localOnly)
    }

    @Test("A readable, empty registry unlocks the full wipe")
    func noneFoundPromptsForCloudData() {
        #expect(WalletDataCleanupService.deletionStrategy(for: .noneFound) == .promptForCloudData)
    }

    @Test("An unreadable registry must never offer the full wipe")
    func undeterminedIsConservative() {
        // The asymmetry that makes this the only safe default: a wrong "last
        // device" deletes the synchronizable seed account-wide and is
        // unrecoverable without a written phrase, while a wrong "local only"
        // just leaves data to clean up later
        #expect(WalletDataCleanupService.deletionStrategy(for: .undetermined) == .localOnly)
    }

    @Test("Only a definitively empty registry maps to the destructive strategy")
    func fullWipeHasExactlyOnePrecondition() {
        // Over allCases, not a hand-listed array: a newly added evidence kind
        // that falls through to .promptForCloudData must fail here
        let destructive = WalletDataCleanupService.OtherDeviceEvidence.allCases
            .filter { WalletDataCleanupService.deletionStrategy(for: $0) == .promptForCloudData }
        #expect(destructive == [.noneFound])
    }
}

// MARK: - Fast Device Registry (KVS mirror)

@Suite("KVS Device Registry Scan")
struct KVSDeviceRegistryTests {

    private static let prefix = DeviceRegistrationService.registeredDevicesPrefix
    private static let hash = "Zm9vYmFyaGFzaA=="   // base64, as the real PBKDF2 hash is
    private static let me = "11111111-1111-1111-1111-111111111111"
    private static let other = "22222222-2222-2222-2222-222222222222"

    @Test("A sibling device registration is seen")
    func findsOtherDevice() {
        let keys = [
            "\(Self.prefix)\(Self.hash).\(Self.me)",
            "\(Self.prefix)\(Self.hash).\(Self.other)"
        ]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: Self.hash, currentDeviceId: Self.me)
        #expect(found == [Self.other])
    }

    @Test("This device alone reads as no others — the only case that unlocks a full wipe")
    func excludesSelf() {
        let keys = ["\(Self.prefix)\(Self.hash).\(Self.me)"]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: Self.hash, currentDeviceId: Self.me)
        #expect(found.isEmpty)
    }

    @Test("Registrations for another wallet are ignored")
    func scopedToWalletHash() {
        let keys = ["\(Self.prefix)b3RoZXJoYXNo.\(Self.other)"]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: Self.hash, currentDeviceId: Self.me)
        #expect(found.isEmpty)
    }

    @Test("Unrelated KVS keys are ignored")
    func ignoresForeignKeys() {
        let keys = [
            "com.arke.wallet.mnemonicHash",
            "com.arke.wallet.networkConfigId",
            "device_\(Self.other)_isPrimary",
            "\(Self.prefix)\(Self.hash).\(Self.other)"
        ]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: Self.hash, currentDeviceId: Self.me)
        #expect(found == [Self.other])
    }

    @Test("A prefix with no device ID is not a device")
    func ignoresEmptyDeviceId() {
        let keys = ["\(Self.prefix)\(Self.hash)."]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: Self.hash, currentDeviceId: Self.me)
        #expect(found.isEmpty)
    }

    @Test("A wallet hash that prefixes another wallet's hash doesn't leak")
    func prefixCollisionIsScoped() {
        // "abc" must not match keys belonging to wallet "abcdef"
        let keys = ["\(Self.prefix)abcdef.\(Self.other)"]
        let found = DeviceRegistrationService.otherRegisteredDeviceIds(
            kvsKeys: keys, walletHash: "abc", currentDeviceId: Self.me)
        #expect(found.isEmpty)
    }
}
