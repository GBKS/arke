//
//  DefaultDataSeedingDecisionTests.swift
//  Arke
//
//  Default-data seeding used to run whenever the local store looked empty —
//  briefly true on ANY fresh install of an existing account, including a
//  reinstalled primary, which seeded account-wide duplicate tags/contacts
//  (2026-09-24 review finding; the role-based guard only covered
//  secondaries). The decision is now: created wallets seed immediately
//  (creation refuses when any account wallet signal exists, so there is
//  provably nothing to import), read-only devices never seed, everything
//  else waits for the first completed CloudKit import.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Default Data Seeding Decision")
struct DefaultDataSeedingDecisionTests {

    @Test("A created wallet seeds immediately")
    func createdWalletSeedsImmediately() {
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: false, origin: .created, firstImportCompleted: false
        ) == .seedNow)
    }

    @Test("An imported wallet waits for the first import")
    func importedWalletWaitsForFirstImport() {
        // The import path may be a rejoin of an account that already has the
        // defaults — its store just hasn't imported them yet
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: false, origin: .imported, firstImportCompleted: false
        ) == .waitForFirstImport)
    }

    @Test("An imported wallet seeds once the import completed")
    func importedWalletSeedsOnceImportCompleted() {
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: false, origin: .imported, firstImportCompleted: true
        ) == .seedNow)
    }

    @Test("An ordinary launch with no import yet waits")
    func ordinaryLaunchWithEmptyStoreWaits() {
        // nil origin is every non-onboarding launch — including the
        // reinstall-with-silently-synced-keychain-seed case, which is exactly
        // the case that must wait
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: false, origin: nil, firstImportCompleted: false
        ) == .waitForFirstImport)
    }

    @Test("An ordinary launch after the import seeds")
    func ordinaryLaunchAfterImportSeeds() {
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: false, origin: nil, firstImportCompleted: true
        ) == .seedNow)
    }

    @Test("A read-only device never seeds")
    func readOnlyDeviceNeverSeeds() {
        for origin in [WalletManager.FreshWalletOrigin.created, .imported] {
            for imported in [true, false] {
                #expect(WalletManager.defaultDataSeedingDecision(
                    isReadOnlyMode: true, origin: origin, firstImportCompleted: imported
                ) == .doNotSeed)
            }
        }
        #expect(WalletManager.defaultDataSeedingDecision(
            isReadOnlyMode: true, origin: nil, firstImportCompleted: true
        ) == .doNotSeed)
    }

    @Test("Only a finished, successful import opens the gate")
    func gateOpensOnlyOnFinishedSuccessfulImport() {
        // The full truth table over the event filter: setup/export events say
        // nothing about remote data, an unfinished import may still deliver
        // rows, a failed one delivered nothing
        for isImport in [true, false] {
            for finished in [true, false] {
                for succeeded in [true, false] {
                    let expected = isImport && finished && succeeded
                    #expect(CloudKitFirstImportGate.opensGate(
                        eventTypeIsImport: isImport, finished: finished, succeeded: succeeded
                    ) == expected)
                }
            }
        }
    }

    @Test("The gate wait returns immediately once latched, and times out otherwise")
    @MainActor
    func gateWaitBehavior() async {
        let gate = CloudKitFirstImportGate()

        // Not latched: a tiny timeout elapses and reports the gate closed
        let timedOut = await gate.waitForFirstImport(timeout: .milliseconds(50))
        #expect(!timedOut)
        #expect(!gate.firstImportCompleted)
    }
}
