//
//  NetworkConfigReconciliationTests.swift
//  ArkéTests
//
//  Unit tests for the decision behind WalletManager's step 0-pre: given the
//  network a wallet object was built on and the id in the local config cache,
//  should the wallet be re-pointed before anything opens its database?
//
//  A wrong answer here is expensive in both directions. Failing to re-point runs
//  a whole session against the wrong chain and leaves a wrong-network database
//  that the next launch refuses to open (2026-08-20 incident; Launch_Sequence_
//  Contract rules 21/22). Re-pointing when we shouldn't does the same damage to
//  a wallet that was running correctly.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Network Config Reconciliation Tests")
@MainActor
struct NetworkConfigReconciliationTests {

    private func decide(wallet: String, cached: String?) -> NetworkConfigPersistence.Reconciliation {
        NetworkConfigPersistence.reconciliation(walletNetworkId: wallet, cachedConfigId: cached)
    }

    @Test("A wallet built on mainnet while the account says signet is re-pointed")
    func staleMainnetWalletIsRepointed() {
        #expect(decide(wallet: "mainnet", cached: "signet") == .reapply(.signet))
    }

    @Test("A wallet already on the cached network is left alone")
    func matchingNetworkIsInSync() {
        #expect(decide(wallet: "signet", cached: "signet") == .inSync)
    }

    @Test("No cached config means no decision to act on")
    func missingCacheIsNotUsable() {
        #expect(decide(wallet: "mainnet", cached: nil) == .noUsableConfig)
    }

    @Test("An unresolvable cached id never re-points a running wallet to mainnet")
    func unknownCachedIdIsNotUsable() {
        // load() answers mainnet for an id it can't resolve, so reconciling through
        // it would move a correct signet wallet to mainnet. The decision must not.
        #expect(decide(wallet: "signet", cached: "custom_ABC123") == .noUsableConfig)
    }

    @Test("Reconciliation has no mainnet bias — signet to mainnet re-points too")
    func mainnetCacheRepointsSignetWallet() {
        #expect(decide(wallet: "signet", cached: "mainnet") == .reapply(.mainnet))
    }

    @Test("Testnet is reconciled like any other known network")
    func testnetCacheRepointsSignetWallet() {
        #expect(decide(wallet: "testnet", cached: "signet") == .reapply(.signet))
        #expect(decide(wallet: "signet", cached: "testnet") == .reapply(.testnet))
    }

    @Test("An empty cached id is treated as unusable, not as a network")
    func emptyCachedIdIsNotUsable() {
        #expect(decide(wallet: "signet", cached: "") == .noUsableConfig)
    }

    @Test("The re-applied config carries the matching network endpoints")
    func reappliedConfigCarriesEndpoints() {
        // The whole point of re-pointing is which chain we talk to: a mismatch here
        // is how a signet wallet ends up fetching mainnet block heights.
        guard case .reapply(let config) = decide(wallet: "mainnet", cached: "signet") else {
            Issue.record("Expected a re-apply decision")
            return
        }
        #expect(config.networkType == "signet")
        #expect(config.isMainnet == false)
        #expect(config.esploraBaseURL.contains("signet"))
    }
}
