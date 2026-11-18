//
//  WalletAccessVerdictTests.swift
//  ArkéTests
//
//  The pure decision behind WalletManager.walletAccessVerdict (contract rule
//  28, Device_Linking.md §11.2): unknown is read-only, and the only path to
//  opening bark is positive evidence that this device holds primary.
//  Created by Assistant on 11/13/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Wallet Access Verdict")
struct WalletAccessVerdictTests {

    private typealias Verdict = WalletManager.AccessVerdict

    @Test("An unreadable device ID blocks, whatever else is known")
    func unreadableDeviceIdBlocks() {
        // Before: an unreadable ID returned "not blocked" and the wallet
        // opened as primary on no evidence (Read_Only_Mode.md sibling site)
        let verdict = WalletManager.accessVerdict(deviceIdReadable: false, wasDemoted: false, mirror: .primary, ownRow: .primary)
        #expect(verdict == .block(.deviceIdUnreadable))
    }

    @Test("The local demotion flag blocks first")
    func demotionFlagBlocks() {
        let verdict = WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: true, mirror: .primary, ownRow: .primary)
        #expect(verdict == .block(.demoted))
    }

    @Test("A secondary's own mirror write is a settled secondary, not a demotion")
    func ownMirrorWriteIsSecondary() {
        let verdict = WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .notPrimary(selfWritten: true), ownRow: .secondary)
        #expect(verdict == .block(.secondary))
    }

    @Test("A not-primary flag this device did not write reads as demotion")
    func foreignMirrorWriteIsDemotion() {
        let verdict = WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .notPrimary(selfWritten: false), ownRow: .primary)
        #expect(verdict == .block(.demoted))
    }

    @Test("A primary own row allows, with or without a mirror opinion")
    func primaryRowAllows() {
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: .primary) == .allow)
        // Installs predating the mirror breadcrumb, or a KVS cache not yet
        // loaded: the row is the authority when it answers
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .noOpinion, ownRow: .primary) == .allow)
    }

    @Test("A secondary own row blocks even when the mirror says primary")
    func secondaryRowBlocks() {
        // Reconciliation demoted this device in the registry; a stale mirror
        // flag must not reopen the wallet
        let verdict = WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: .secondary)
        #expect(verdict == .block(.secondary))
    }

    @Test("No row is unknown, and unknown is read-only")
    func absentRowBlocks() {
        // The 2026-11-13 device run: an ex-primary unlinked by another device
        // relaunches with no row. Before, this opened as primary.
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .noOpinion, ownRow: .absent) == .block(.noRegistration))
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: .absent) == .block(.noRegistration))
    }

    @Test("A primary row for another wallet is no evidence for this one")
    func otherWalletRowBlocks() {
        // Range review 2026-11-16, G1: wallet X's primary row must not open
        // wallet Y's database after a wipe-and-recreate elsewhere
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: .otherWallet) == .block(.noRegistration))
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .noOpinion, ownRow: .otherWallet) == .block(.noRegistration))
    }

    @Test("A registry that cannot be asked defers to a positive mirror answer only")
    func unavailableRegistryNeedsPrimaryMirror() {
        // Last resort when even the fallback container is missing (desktop):
        // the mirror's own `primary` write, which unlink and the full wipe now
        // remove, so it is only as stale as the device's last KVS sync
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .primary, ownRow: .unavailable) == .allow)
        #expect(WalletManager.accessVerdict(deviceIdReadable: true, wasDemoted: false, mirror: .noOpinion, ownRow: .unavailable) == .block(.registryUnavailable))
    }

    @Test("Settled blocks end a background wake chain, unknown ones let it retry")
    func settledVersusUnknown() {
        #expect(WalletManager.AccessBlockReason.demoted.isSettled)
        #expect(WalletManager.AccessBlockReason.secondary.isSettled)
        #expect(!WalletManager.AccessBlockReason.noRegistration.isSettled)
        #expect(!WalletManager.AccessBlockReason.deviceIdUnreadable.isSettled)
        #expect(!WalletManager.AccessBlockReason.registryUnavailable.isSettled)
    }

    @Test("Every block reports as blocking and allow does not")
    func blocksFlag() {
        #expect(Verdict.allow.blocks == false)
        #expect(Verdict.block(.noRegistration).blocks)
    }

    @Test("Deletion clears every device's demotion breadcrumb and nothing else")
    func deletionClearsDemotionBreadcrumbs() throws {
        // Device run 2026-11-18: demote → full wipe → create came up read-only
        // because layer 1 still said demoted after the wipe
        let suite = "WalletAccessVerdictTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DeviceRegistrationService.demotionBreadcrumbKey(deviceId: "A"))
        defaults.set(true, forKey: DeviceRegistrationService.demotionBreadcrumbKey(deviceId: "B"))
        defaults.set(true, forKey: DeviceRegistrationService.selfWrotePrimaryFlagKey(deviceId: "A"))

        DeviceRegistrationService.clearDemotionBreadcrumbs(in: defaults)

        #expect(defaults.object(forKey: DeviceRegistrationService.demotionBreadcrumbKey(deviceId: "A")) == nil)
        #expect(defaults.object(forKey: DeviceRegistrationService.demotionBreadcrumbKey(deviceId: "B")) == nil)
        #expect(defaults.bool(forKey: DeviceRegistrationService.selfWrotePrimaryFlagKey(deviceId: "A")))
    }
}
