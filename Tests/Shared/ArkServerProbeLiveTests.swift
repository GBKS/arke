//
//  ArkServerProbeLiveTests.swift
//  ArkéTests
//
//  Executes `BarkWalletFFI.probeServer` against real servers. Network-bound,
//  so it is skipped unless ARKE_LIVE_PROBE is set in the test environment. The
//  variable must be in xcodebuild's own environment (the TEST_RUNNER_ prefix
//  forwards it to the test host); as a trailing argument it is a build setting
//  and the suite stays skipped:
//
//    TEST_RUNNER_ARKE_LIVE_PROBE=1 xcodebuild test ... \
//      -only-testing:ArkeMobileTests/ArkServerProbeLiveTests
//
//  This is the Phase 0 evidence for Features/Ark_Server_Selection.md: the
//  probe, not grpcurl, is what the form will run.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// .serialized: the scratch-directory test lists tmp, which a concurrent sibling probe would pollute
@Suite("Ark Server Probe (live)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ARKE_LIVE_PROBE"] != nil))
@MainActor
struct ArkServerProbeLiveTests {

    @Test("Second's signet server is detected on the second attempt")
    func secondSignetIsSignet() async throws {
        // Mainnet is tried first and must be refused by bark's network check;
        // this is the path that proves chain detection works, not just reachability.
        let result = try await BarkWalletFFI.probeServer(url: NetworkConfig.signet.arkServerURL)
        #expect(result.network == .signet)
        #expect(result.arkServerBaseURL == "https://ark.signet.2nd.dev")
    }

    @Test("Zappin is a mainnet bark server")
    func zappinIsMainnet() async throws {
        let result = try await BarkWalletFFI.probeServer(url: "ark.zappin.online")
        #expect(result.network == .mainnet)
    }

    @Test("A host that is not an Ark server fails as unreachable or incompatible")
    func nonArkHostFails() async {
        await #expect(throws: ArkServerProbeError.self) {
            _ = try await BarkWalletFFI.probeServer(url: "https://example.com")
        }
    }

    @Test("Input without a host is rejected before any network call")
    func invalidURLIsRejected() async {
        await #expect(throws: ArkServerProbeError.invalidURL) {
            _ = try await BarkWalletFFI.probeServer(url: "https://")
        }
    }

    @Test("The scratch directory is gone after a probe")
    func scratchDirectoryIsRemoved() async throws {
        _ = try? await BarkWalletFFI.probeServer(url: NetworkConfig.signet.arkServerURL)
        let tmp = FileManager.default.temporaryDirectory
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path))?
            .filter { $0.hasPrefix("arke-server-probe-") } ?? []
        #expect(leftovers.isEmpty)
    }
}
