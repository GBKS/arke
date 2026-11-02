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
//  Since 2026-10-29 a config can also name a custom Ark server, which only
//  resolves through the full config stored beside the id; the second suite
//  covers that model (Features/Ark_Server_Selection.md).
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Network Config Reconciliation Tests")
@MainActor
struct NetworkConfigReconciliationTests {

    private func decide(wallet: String, cached: String?, stored: NetworkConfig? = nil) -> NetworkConfigPersistence.Reconciliation {
        NetworkConfigPersistence.reconciliation(walletNetworkId: wallet, cachedConfigId: cached, storedConfig: stored)
    }

    private static let zappin = NetworkConfig.custom(
        arkServerURL: "ark.zappin.online",
        esploraURL: NetworkConfig.mainnet.esploraURL,
        network: .mainnet
    )

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

    @Test("The dropped testnet preset no longer resolves")
    func testnetIdIsNotUsable() {
        // Installed devices never had a testnet wallet (the preset had no server),
        // so an old "testnet" id must fall to no-decision, not to a preset.
        #expect(decide(wallet: "signet", cached: "testnet") == .noUsableConfig)
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

    // MARK: Custom servers

    @Test("A custom id resolves only through a stored config with the same id")
    func customIdNeedsMatchingStoredConfig() throws {
        let zappin = try #require(Self.zappin)
        // Stored full config present: the account's custom server wins over the
        // wallet object built on the mainnet default.
        #expect(decide(wallet: "mainnet", cached: zappin.id, stored: zappin) == .reapply(zappin))
        // Same id on the wallet already: nothing to do.
        #expect(decide(wallet: zappin.id, cached: zappin.id, stored: zappin) == .inSync)
    }

    @Test("A custom id with no stored config, or a foreign one, is unusable")
    func customIdWithoutStoredConfigIsNotUsable() throws {
        let zappin = try #require(Self.zappin)
        let other = try #require(NetworkConfig.custom(
            arkServerURL: "ark.coinos.io",
            esploraURL: NetworkConfig.mainnet.esploraURL,
            network: .mainnet
        ))
        #expect(decide(wallet: "mainnet", cached: zappin.id, stored: nil) == .noUsableConfig)
        // A stored blob for a different server never answers for this id
        #expect(decide(wallet: "mainnet", cached: zappin.id, stored: other) == .noUsableConfig)
    }

    @Test("A stored custom config never shadows a preset id")
    func storedConfigDoesNotShadowPresets() throws {
        let zappin = try #require(Self.zappin)
        // A stale custom blob left in the cache while the id says "signet" must
        // resolve to Second's signet, not to the blob.
        #expect(NetworkConfigPersistence.resolve(id: "signet", stored: zappin) == .signet)
    }
}

@Suite("Network Config Custom Server Model Tests")
@MainActor
struct NetworkConfigCustomServerTests {

    @Test("The custom id is deterministic and normalises scheme, case and trailing slash")
    func customIdIsDeterministic() throws {
        let plain = try #require(NetworkConfig.custom(arkServerURL: "ark.zappin.online", esploraURL: "x", network: .mainnet))
        let dressed = try #require(NetworkConfig.custom(arkServerURL: "HTTPS://Ark.Zappin.Online/", esploraURL: "x", network: .mainnet))
        #expect(plain.id == "custom:mainnet:ark.zappin.online")
        #expect(plain.id == dressed.id)
        // The stored URL is normalised too, so the sheet, the cover label and
        // the id never disagree on casing (device look 2026-10-29)
        #expect(dressed.arkServerBaseURL == "https://ark.zappin.online")
        #expect(dressed == plain)
    }

    @Test("The chain is part of the id, so the same host on another chain is another server")
    func chainIsPartOfId() throws {
        let mainnet = try #require(NetworkConfig.custom(arkServerURL: "ark.example.com", esploraURL: "x", network: .mainnet))
        let signet = try #require(NetworkConfig.custom(arkServerURL: "ark.example.com", esploraURL: "x", network: .signet))
        #expect(mainnet.id != signet.id)
        #expect(mainnet.isMainnet)
        #expect(!signet.isMainnet)
        #expect(signet.networkType == "signet")
    }

    @Test("A port is kept in the id; a URL without a host is rejected")
    func portAndInvalidHost() {
        #expect(NetworkConfig.serverHost("ark.example.com:3535") == "ark.example.com:3535")
        #expect(NetworkConfig.serverHost("https://ark.example.com:3535/") == "ark.example.com:3535")
        #expect(NetworkConfig.custom(arkServerURL: "   ", esploraURL: "x", network: .mainnet) == nil)
        #expect(NetworkConfig.custom(arkServerURL: "https://", esploraURL: "x", network: .mainnet) == nil)
    }

    @Test("A blank display name falls back to the host")
    func nameFallsBackToHost() throws {
        let unnamed = try #require(NetworkConfig.custom(arkServerURL: "ark.zappin.online", esploraURL: "x", network: .mainnet, name: "  "))
        let named = try #require(NetworkConfig.custom(arkServerURL: "ark.zappin.online", esploraURL: "x", network: .mainnet, name: "Zappin"))
        #expect(unnamed.name == "ark.zappin.online")
        #expect(named.name == "Zappin")
    }

    @Test("A custom config survives a JSON round trip, which is how it is persisted")
    func codableRoundTrip() throws {
        let config = try #require(NetworkConfig.custom(
            arkServerURL: "ark.zappin.online",
            esploraURL: NetworkConfig.mainnet.esploraURL,
            network: .mainnet,
            name: "Zappin"
        ))
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(NetworkConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.serverKind == .custom)
        #expect(decoded.isMainnet)
    }

    @Test("Presets keep their persisted ids and carry Second as the server")
    func presetsKeepIds() {
        // These ids are in UserDefaults and iCloud KVS on every installed device.
        #expect(NetworkConfig.mainnet.id == "mainnet")
        #expect(NetworkConfig.signet.id == "signet")
        #expect(NetworkConfig.mainnet.serverKind == .secondMainnet)
        #expect(NetworkConfig.signet.serverKind == .secondSignet)
        #expect(NetworkConfig.preset(byId: "testnet") == nil)
        #expect(NetworkConfig.presets.count == 2)
    }

    @Test("The prefilled Esplora follows the detected chain")
    func defaultEsploraFollowsChain() {
        #expect(NetworkConfig.defaultEsploraURL(for: .mainnet) == "https://mempool.second.tech/api")
        #expect(NetworkConfig.defaultEsploraURL(for: .signet) == "https://esplora.signet.2nd.dev")
    }
}

@Suite("Network Config Reapply Guard Tests")
@MainActor
struct NetworkConfigReapplyGuardTests {

    // Adversarial passes 2026-10-29/30, findings F1 and R3: the account can
    // name a different server on the same chain (an older build imported the
    // phrase onto Second, or a second device imported it onto a custom
    // server). bark pins the server key at creation, so re-pointing an
    // existing database to another server on its chain breaks a working
    // wallet. The guard is symmetric, but only for a config that was resolved
    // from this device's cache: load()'s mainnet fallback must still yield.

    private static let zappin = NetworkConfig.custom(
        arkServerURL: "ark.zappin.online", esploraURL: "x", network: .mainnet)
    private static let coinos = NetworkConfig.custom(
        arkServerURL: "ark.coinos.io", esploraURL: "x", network: .mainnet)

    private func decide(current: NetworkConfig, resolved: Bool = true, cached: NetworkConfig, db: Bool) -> NetworkConfigPersistence.ReapplyDecision {
        NetworkConfigPersistence.reapplyDecision(
            current: current, currentResolvedFromCache: resolved, cached: cached, walletDatabaseExists: db)
    }

    private func isKeep(_ decision: NetworkConfigPersistence.ReapplyDecision) -> Bool {
        if case .keepCurrent = decision { return true }
        return false
    }

    @Test("A custom-server device with a database is not re-pointed to another server on its chain")
    func customDeviceKeepsItsServer() throws {
        let zappin = try #require(Self.zappin)
        let coinos = try #require(Self.coinos)
        #expect(isKeep(decide(current: zappin, cached: .mainnet, db: true)))
        #expect(isKeep(decide(current: zappin, cached: coinos, db: true)))
    }

    @Test("A Second device with a database is not re-pointed to a custom server on its chain either")
    func presetDeviceKeepsItsServer() throws {
        let zappin = try #require(Self.zappin)
        // Mirror of F1 (second pass, R3): the Second-pinned database would be
        // pointed at Zappin and bark would refuse every call
        #expect(isKeep(decide(current: .mainnet, cached: zappin, db: true)))
    }

    @Test("load()'s mainnet fallback is not a fact about the database and yields to the account")
    func fallbackYieldsToAccount() throws {
        let zappin = try #require(Self.zappin)
        // Local cache unresolvable (custom JSON missing), account resolvable:
        // this is how a reinstall or a late-synced device finds its server
        #expect(decide(current: .mainnet, resolved: false, cached: zappin, db: true) == .reapply)
        #expect(decide(current: .mainnet, resolved: false, cached: .signet, db: true) == .reapply)
    }

    @Test("Without a database the account wins, custom or not")
    func noDatabaseMeansAccountWins() throws {
        let zappin = try #require(Self.zappin)
        #expect(decide(current: zappin, cached: .mainnet, db: false) == .reapply)
        #expect(decide(current: .mainnet, cached: zappin, db: false) == .reapply)
    }

    @Test("A chain change is still re-applied; only same-chain server swaps are refused")
    func chainChangeIsReapplied() throws {
        let zappin = try #require(Self.zappin)
        #expect(decide(current: zappin, cached: .signet, db: true) == .reapply)
        #expect(decide(current: .mainnet, cached: .signet, db: true) == .reapply)
    }

    @Test("A custom id the account names is pending until some copy of its details resolves it")
    func pendingCustomServer() throws {
        let zappin = try #require(Self.zappin)
        let coinos = try #require(Self.coinos)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: zappin.id, candidates: [nil, nil]) == zappin.id)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: zappin.id, candidates: [nil, coinos]) == zappin.id)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: zappin.id, candidates: [zappin, nil]) == nil)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: zappin.id, candidates: [nil, zappin]) == nil)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: "mainnet", candidates: [nil]) == nil)
        #expect(NetworkConfigPersistence.pendingCustomServerId(accountId: nil, candidates: []) == nil)
        #expect(NetworkConfig.hostFromCustomId(zappin.id) == "ark.zappin.online")
        #expect(NetworkConfig.hostFromCustomId("mainnet") == nil)
    }

    @Test("The probe and the stored config use one canonical server URL")
    func canonicalServerURL() {
        #expect(NetworkConfig.canonicalServerURL("HTTPS://Ark.Example.com/ark/") == "https://ark.example.com")
        #expect(NetworkConfig.canonicalServerURL("ark.example.com:3535") == "https://ark.example.com:3535")
        #expect(NetworkConfig.canonicalServerURL("http://localhost:3535") == "http://localhost:3535")
        #expect(NetworkConfig.canonicalServerURL("   ") == nil)
    }

    @Test("The failure detail prefers a real refusal over a wrong-chain line")
    func failureDetailPrefersRealReason() {
        let mismatch = "network mismatch. Expected: signet, Got: bitcoin"
        #expect(BarkWalletFFI.probeFailureDetail(["unsafe ArkInfo", mismatch]) == "unsafe ArkInfo")
        #expect(BarkWalletFFI.probeFailureDetail([mismatch, "unsafe ArkInfo"]) == "unsafe ArkInfo")
        #expect(BarkWalletFFI.probeFailureDetail(["connect failed", "connect failed too"]) == "connect failed too")
        #expect(BarkWalletFFI.probeFailureDetail([]) == "")
    }
}
