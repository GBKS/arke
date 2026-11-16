//
//  LaunchCheckCaseTests.swift
//  ArkéTests
//
//  DeviceLinkStore.launchCheckCase and the CloudKit status mapping behind
//  the launch-check screen (Device_Linking.md §4.5, §15).
//  Created by Assistant on 11/16/26.
//

import Testing
import Foundation
import CloudKit

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Launch Check Case")
struct LaunchCheckCaseTests {

    private func decide(hash: String?, seedFound: Bool = false, account: ICloudAccountPresence, identity: Bool? = nil) -> LaunchCheckCase {
        DeviceLinkStore.launchCheckCase(recordHash: "hash-A", accountHash: hash, seedFound: seedFound, iCloudAccount: account, accountIdentityMatches: identity)
    }

    @Test("A different account hash is the account switch, whatever iCloud says about the account")
    func differentHashWins() {
        #expect(decide(hash: "hash-B", seedFound: true, account: .present) == .differentAccount)
        #expect(decide(hash: "hash-B", account: .absent) == .differentAccount)
        #expect(decide(hash: "hash-B", account: .unknown) == .differentAccount)
    }

    @Test("No hash is the wipe-elsewhere aftermath only when the link-time account identity still matches")
    func deletedElsewhere() {
        #expect(decide(hash: nil, account: .present, identity: true) == .deletedElsewhere)
        // An empty string is no hash
        #expect(decide(hash: "", account: .present, identity: true) == .deletedElsewhere)
        // A matching token proves an account is present, whatever CloudKit said
        #expect(decide(hash: nil, account: .unknown, identity: true) == .deletedElsewhere)
    }

    @Test("No hash on another account identity is the account switch, even when that account has no wallet")
    func emptyNewAccount() {
        // Review 2026-11-16, F2: an empty Apple ID looks exactly like a wipe
        // elsewhere to every account-level signal; only the stored identity
        // separates them, and the restore exit must not pair X with Y
        #expect(decide(hash: nil, account: .present, identity: false) == .differentAccount)
    }

    @Test("No hash with an account present but no identity to compare is undetermined, never deleted")
    func presentWithoutIdentity() {
        #expect(decide(hash: nil, account: .present) == .undetermined)
    }

    @Test("No hash and no account is signed out")
    func signedOut() {
        #expect(decide(hash: nil, account: .absent) == .signedOut)
    }

    @Test("A stored token with nothing current to compare against is not a match")
    func identityNeedsBothSides() {
        // The test host may or may not be signed in; with no stored data the
        // answer is nil either way
        #expect(ICloudAccountIdentity.matches(stored: nil) == nil)
        #expect(ICloudAccountIdentity.matches(stored: Data([0x00, 0x01])) == nil)
    }

    @Test("No hash and an unreadable account status is said so, not guessed")
    func undetermined() {
        // The aftermath copy claims the wallet was deleted; without the
        // account status that claim has no basis
        #expect(decide(hash: nil, account: .unknown) == .undetermined)
    }

    @Test("Only available and noAccount are evidence")
    func cloudKitStatusMapping() {
        #expect(ICloudAccountStatus.presence(of: .available) == .present)
        #expect(ICloudAccountStatus.presence(of: .noAccount) == .absent)
        #expect(ICloudAccountStatus.presence(of: .restricted) == .unknown)
        #expect(ICloudAccountStatus.presence(of: .couldNotDetermine) == .unknown)
        #expect(ICloudAccountStatus.presence(of: .temporarilyUnavailable) == .unknown)
    }
}
