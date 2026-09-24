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

// MARK: - Informed Override

/// The wallet could not be deleted from the account at all: a mirror entry with
/// no staleness cutoff blocked the full wipe indefinitely and S7's override was
/// never built (2026-09-23). These pin that the override is the only door from
/// `.localOnly` to a full wipe, so no error path can wander into one.
@Suite("Full Wipe Override")
struct FullWipeOverrideTests {

    @Test("The last device wipes everything without needing an override")
    func lastDeviceIncludesCloudData() {
        #expect(WalletDataCleanupService.includesCloudData(strategy: .promptForCloudData, overrideConfirmed: false))
    }

    @Test("Blocked deletion stays local unless overridden")
    func blockedDeletionStaysLocal() {
        #expect(!WalletDataCleanupService.includesCloudData(strategy: .localOnly, overrideConfirmed: false))
    }

    @Test("The override is what turns a blocked deletion into a full wipe")
    func overrideUnlocksFullWipe() {
        #expect(WalletDataCleanupService.includesCloudData(strategy: .localOnly, overrideConfirmed: true))
    }

    @Test("An override is never needed to reach the safe outcome")
    func overrideNeverDowngradesAFullWipe() {
        // Overriding a genuine last-device verdict must not somehow spare data
        #expect(WalletDataCleanupService.includesCloudData(strategy: .promptForCloudData, overrideConfirmed: true))
    }

    @Test("Only an explicit override can wipe shared state under a local-only verdict")
    func fullWipeUnderLocalOnlyHasExactlyOneCause() {
        // Over every strategy: with no override, .promptForCloudData is the sole
        // input that touches the account's seed. An error path that produced a
        // new strategy and defaulted to a wipe would fail here.
        let wipingWithoutOverride = [DeletionStrategy.localOnly, .promptForCloudData]
            .filter { WalletDataCleanupService.includesCloudData(strategy: $0, overrideConfirmed: false) }
        #expect(wipingWithoutOverride == [.promptForCloudData])
    }
}

// MARK: - Mirror key selection (ghost cleanup)

/// `unregisterCurrentDevice` only cleared the mirror when a registry row
/// existed, so a fresh adopt or an already-deduped row left an entry that
/// outlived the device and blocked every remaining device's full wipe forever.
@Suite("Mirror Key Selection")
struct MirrorKeySelectionTests {

    private static let prefix = DeviceRegistrationService.registeredDevicesPrefix
    private static let me = "11111111-1111-1111-1111-111111111111"
    private static let other = "22222222-2222-2222-2222-222222222222"

    @Test("A device's entries are found across every wallet hash")
    func findsEntriesForAllWallets() {
        // Leaving here means leaving: a row's hash and the account's hash can
        // disagree, and clearing only one of them recreates the ghost
        let keys = [
            "\(Self.prefix)Zm9vYmFyaGFzaA==.\(Self.me)",
            "\(Self.prefix)b3RoZXJoYXNo.\(Self.me)",
            "\(Self.prefix)Zm9vYmFyaGFzaA==.\(Self.other)"
        ]
        let found = DeviceRegistrationService.mirrorKeys(forDeviceId: Self.me, in: keys)

        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.hasSuffix(Self.me) })
    }

    @Test("Other devices' entries are never touched")
    func leavesOtherDevicesAlone() {
        // Removing a live device's entry would tell the remaining device it is
        // alone, which unlocks the wipe that destroys the shared seed
        let keys = ["\(Self.prefix)Zm9vYmFyaGFzaA==.\(Self.other)"]
        #expect(DeviceRegistrationService.mirrorKeys(forDeviceId: Self.me, in: keys).isEmpty)
    }

    @Test("Non-registry keys are never removed")
    func ignoresForeignKeys() {
        let keys = [
            "com.arke.wallet.mnemonicHash",
            "device_\(Self.me)_isPrimary",
            "device_\(Self.me)_selfWroteIsPrimary"
        ]
        #expect(DeviceRegistrationService.mirrorKeys(forDeviceId: Self.me, in: keys).isEmpty)
    }

    @Test("An empty device ID matches nothing")
    func emptyDeviceIdMatchesNothing() {
        // Otherwise the suffix check degenerates to "any key ending in a dot"
        let keys = ["\(Self.prefix)Zm9vYmFyaGFzaA==.\(Self.me)", "\(Self.prefix)Zm9vYmFyaGFzaA==."]
        #expect(DeviceRegistrationService.mirrorKeys(forDeviceId: "", in: keys).isEmpty)
    }

    @Test("A device ID that suffixes another is not matched")
    func doesNotMatchBySubstring() {
        // "...-2222" must not match a device whose id ends with those characters
        let keys = ["\(Self.prefix)Zm9vYmFyaGFzaA==.aaaa\(Self.other)"]
        #expect(DeviceRegistrationService.mirrorKeys(forDeviceId: Self.other, in: keys).isEmpty)
    }
}

// MARK: - Layer 2: the KVS primary-flag mirror

/// `shouldBlockWalletAccess` layer 2 reads a flag that only this device ever
/// writes, so a fresh secondary read back its own registration's `false` and
/// logged "🛑 Blocked: iCloud KV store indicates demotion" — right outcome,
/// wrong reason. These pin that the outcome is unchanged while the claim is not.
@Suite("Mirror Primary Verdict")
struct MirrorPrimaryVerdictTests {

    @Test("No flag written means the mirror has no opinion, and must not block")
    func absentFlagIsNotEvidence() {
        // bool(forKey:) collapses absent into false; treating that as "not
        // primary" would put every pre-registration launch into read-only
        let verdict = WalletManager.mirrorPrimaryVerdict(mirrorValue: nil, selfWroteValue: nil)

        #expect(verdict == .noOpinion)
        #expect(!verdict.blocksWalletAccess)
    }

    @Test("A primary flag does not block")
    func primaryDoesNotBlock() {
        let verdict = WalletManager.mirrorPrimaryVerdict(mirrorValue: true, selfWroteValue: true)

        #expect(verdict == .primary)
        #expect(!verdict.blocksWalletAccess)
    }

    @Test("A secondary's own registration write is not a demotion")
    func ownRegistrationWriteIsNotDemotion() {
        // The defect: a fresh adopt registers non-primary, mirrors false, then
        // reads it back one layer later
        let verdict = WalletManager.mirrorPrimaryVerdict(mirrorValue: false, selfWroteValue: false)

        #expect(verdict == .notPrimary(selfWritten: true))
        #expect(verdict.blocksWalletAccess)
    }

    @Test("A false flag this device did not write is reported as such")
    func flagWrittenElsewhereIsDistinguished() {
        let verdict = WalletManager.mirrorPrimaryVerdict(mirrorValue: false, selfWroteValue: true)

        #expect(verdict == .notPrimary(selfWritten: false))
        #expect(verdict.blocksWalletAccess)
    }

    @Test("A missing breadcrumb is not read as a self-write")
    func missingBreadcrumbDoesNotClaimSelfWrite() {
        // Installs predating the breadcrumb have no record; guessing "we wrote
        // it" would relabel a real demotion as routine
        let verdict = WalletManager.mirrorPrimaryVerdict(mirrorValue: false, selfWroteValue: nil)

        #expect(verdict == .notPrimary(selfWritten: false))
        #expect(verdict.blocksWalletAccess)
    }

    @Test("Every not-primary verdict blocks, however it was reached")
    func blockingIsUnchangedByTheReason() {
        // The reason is for the log and the copy; it must never change the gate
        for selfWrote in [true, false, nil] {
            #expect(WalletManager.mirrorPrimaryVerdict(mirrorValue: false, selfWroteValue: selfWrote).blocksWalletAccess)
        }
    }
}

// MARK: - Other-Device Report (the two registries merged)

/// The deletion decision reads two stores that disagree in practice — the KVS
/// mirror converges in seconds, the CloudKit-backed registry in minutes or never
/// — and the 2026-09-23 dead end was the result: the delete dialog said "your
/// other devices keep access" (mirror) while Linked Devices said "1 device"
/// (registry). These pin which store wins each question, and in particular that
/// the *blocking set* is unchanged from the boolean this report replaced.
@Suite("Other Device Report")
struct OtherDeviceReportTests {

    private static let prefix = DeviceRegistrationService.registeredDevicesPrefix
    private static let hash = "Zm9vYmFyaGFzaA=="
    private static let me = "11111111-1111-1111-1111-111111111111"
    private static let other = "22222222-2222-2222-2222-222222222222"
    private static let third = "33333333-3333-3333-3333-333333333333"

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let fresh = now.addingTimeInterval(-3600)
    private static let longAgo = now.addingTimeInterval(-40 * 24 * 60 * 60)

    private struct RegistryUnreadable: Error {}

    private static func mirrorKey(_ deviceId: String, walletHash: String = hash) -> String {
        "\(prefix)\(walletHash).\(deviceId)"
    }

    private static func snapshot(
        _ deviceId: String,
        name: String = "Christoph's iPhone",
        walletHash: String = hash,
        lastSeenAt: Date = fresh,
        isActive: Bool = true
    ) -> RegistryDeviceSnapshot {
        RegistryDeviceSnapshot(
            deviceId: deviceId,
            deviceName: name,
            walletHash: walletHash,
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }

    private static func report(
        kvsEntries: [String: Any] = [:],
        walletHash: String? = hash,
        registryDevices: [RegistryDeviceSnapshot] = [],
        registryError: Error? = nil
    ) -> OtherDeviceReport {
        DeviceRegistrationService.otherDeviceReport(
            kvsEntries: kvsEntries,
            walletHash: walletHash,
            registryDevices: registryDevices,
            currentDeviceId: me,
            registryError: registryError,
            now: now
        )
    }

    // MARK: The mirror-only ghost — the case with no remedy in the delete flow

    @Test("A mirror entry with no registry row blocks, unnamed and not unlinkable")
    func mirrorOnlyGhostBlocks() {
        let result = Self.report(kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0])

        #expect(result.hasOthers)
        #expect(result.others.count == 1)
        #expect(result.mirrorOnly.map(\.deviceId) == [Self.other])
        // Nothing can be shown but the ID, and unlinkDevice would throw
        // deviceNotFound — hence the need for an override valve
        #expect(result.unlinkable.isEmpty)
        #expect(result.others.first?.deviceName == nil)
        #expect(result.others.first?.registeredAt == Date(timeIntervalSince1970: 1_699_000_000))
    }

    @Test("A mirror entry with an unreadable timestamp still blocks")
    func mirrorEntryWithoutUsableTimestampStillBlocks() {
        // Never drop a blocker because its bookkeeping value was unexpected
        let result = Self.report(kvsEntries: [Self.mirrorKey(Self.other): "not a timestamp"])

        #expect(result.hasOthers)
        #expect(result.others.first?.registeredAt == nil)
        #expect(result.others.first?.source == .kvsOnly)
    }

    @Test("A mirror-only device is named when any row knows it, without becoming unlinkable")
    func mirrorOnlyGhostBorrowsAName() {
        // An inactive row can't reach this function in production
        // (getOtherDevices filters isActive), but the naming contract shouldn't
        // depend on that: a name we have is better than "Unknown device"
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.other, name: "Old iPhone", isActive: false)]
        )

        #expect(result.others.first?.deviceName == "Old iPhone")
        #expect(result.others.first?.source == .kvsOnly)
        #expect(result.unlinkable.isEmpty)
    }

    // MARK: Blocking set identical to the boolean it replaced

    @Test("A fresh registry row blocks on its own")
    func freshRegistryRowBlocks() {
        let result = Self.report(registryDevices: [Self.snapshot(Self.other)])

        #expect(result.hasOthers)
        #expect(result.others.first?.source == .registry)
        #expect(result.others.first?.deviceName == "Christoph's iPhone")
        #expect(result.others.first?.isStale == false)
        #expect(result.unlinkable.count == 1)
    }

    @Test("A stale registry row alone does not block")
    func staleRegistryRowDoesNotBlock() {
        // Matches the pre-existing `others.contains { !$0.isStale }`: the
        // registry side has always applied the 30-day cutoff
        let result = Self.report(registryDevices: [Self.snapshot(Self.other, lastSeenAt: Self.longAgo)])

        #expect(!result.hasOthers)
    }

    @Test("A stale registry row blocks when the mirror corroborates it, and keeps its name")
    func staleRowWithMirrorEntryBlocks() {
        // The mirror has no staleness cutoff by design, so it wins the blocking
        // question — but the row still wins the naming question
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.other, name: "Sold iPhone", lastSeenAt: Self.longAgo)]
        )

        #expect(result.others.count == 1)
        #expect(result.others.first?.source == .registry)
        #expect(result.others.first?.deviceName == "Sold iPhone")
        #expect(result.others.first?.isStale == true)
        #expect(result.others.first?.lastSeenAt == Self.longAgo)
    }

    @Test("A device in both stores is reported once")
    func noDuplicateAcrossStores() {
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.other)]
        )

        #expect(result.others.count == 1)
        #expect(result.others.first?.source == .registry)
        // Both timestamps survive the merge: heartbeat and registration date
        #expect(result.others.first?.lastSeenAt == Self.fresh)
        #expect(result.others.first?.registeredAt == Date(timeIntervalSince1970: 1_699_000_000))
    }

    // MARK: The only state that may unlock a full wipe

    @Test("This device alone in both stores is the last device")
    func aloneInBothStores() {
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.me): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.me)]
        )

        #expect(!result.hasOthers)
        #expect(!result.registryUnreadable)
    }

    @Test("Another wallet's devices are ignored on both sides")
    func scopedToWalletHash() {
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other, walletHash: "b3RoZXJoYXNo"): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.third, walletHash: "b3RoZXJoYXNo")]
        )

        #expect(!result.hasOthers)
    }

    @Test("Unrelated KVS keys are not devices")
    func ignoresForeignKeys() {
        let result = Self.report(kvsEntries: [
            "com.arke.wallet.mnemonicHash": Self.hash,
            "com.arke.wallet.networkConfigId": "signet",
            "device_\(Self.other)_isPrimary": false
        ])

        #expect(!result.hasOthers)
    }

    // MARK: "I don't know" must never read as "I am alone"

    @Test("An unreadable registry still reports the mirror's blockers")
    func unreadableRegistryKeepsMirrorEvidence() {
        // This is why the report tolerates the failure instead of throwing: the
        // mirror's proof that others exist is the one that must not be lost
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0],
            registryError: RegistryUnreadable()
        )

        #expect(result.hasOthers)
        #expect(result.registryUnreadable)
        #expect(result.mirrorOnly.count == 1)
    }

    @Test("An unreadable registry with an empty mirror is ignorance, not solitude")
    func unreadableRegistryWithEmptyMirrorIsNotEvidence() {
        // hasOthers is false here, which is exactly why the caller must rethrow
        // rather than pass this to the strategy as .noneFound — the flag is the
        // only thing distinguishing it from a genuine last device
        let result = Self.report(registryError: RegistryUnreadable())

        #expect(!result.hasOthers)
        #expect(result.registryUnreadable)
    }

    // MARK: Account wallet unknown (iCloud sign-out, S10)

    @Test("Without a wallet hash the mirror is unusable and the registry is read unscoped")
    func nilWalletHashFallsBackToUnscopedRegistry() {
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.other): 1_699_000_000.0],
            walletHash: nil,
            registryDevices: [Self.snapshot(Self.third, walletHash: "b3RoZXJoYXNo")]
        )

        // Mirror keys can't be addressed without the hash; the foreign-wallet
        // row counts, which is the documented pre-2026-09-21 behaviour
        #expect(result.others.map(\.deviceId) == [Self.third])
        #expect(result.others.first?.source == .registry)
    }

    // MARK: Presentation contract

    @Test("Blockers are ordered by how recently they were heard from")
    func orderedByRecency() {
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.third): Self.now.addingTimeInterval(-7200).timeIntervalSince1970],
            registryDevices: [
                Self.snapshot(Self.other, lastSeenAt: Self.now.addingTimeInterval(-60))
            ]
        )

        #expect(result.others.map(\.deviceId) == [Self.other, Self.third])
    }

    @Test("Blockers partition into unlinkable and mirror-only with nothing lost")
    func partitionCoversEveryBlocker() {
        // Phase 3 offers a different remedy per partition, so a blocker in
        // neither bucket would be a blocker with no way out at all
        let result = Self.report(
            kvsEntries: [Self.mirrorKey(Self.third): 1_699_000_000.0],
            registryDevices: [Self.snapshot(Self.other)]
        )

        #expect(result.others.count == 2)
        #expect(result.unlinkable.count + result.mirrorOnly.count == result.others.count)
        #expect(result.unlinkable.map(\.deviceId) == [Self.other])
        #expect(result.mirrorOnly.map(\.deviceId) == [Self.third])
    }
}
