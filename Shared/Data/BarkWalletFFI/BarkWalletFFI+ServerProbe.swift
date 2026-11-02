//
//  BarkWalletFFI+ServerProbe.swift
//  Arke
//
//  Probe a user-entered Ark server before any wallet exists: is it reachable,
//  does it speak our protocol range, does bark consider its parameters safe,
//  and which chain does it run on. Features/Ark_Server_Selection.md §4.4.
//
//  bark never answers "which chain are you": `ServerConnection` takes the chain
//  as input and refuses with a network mismatch when the server differs. So the
//  chain is detected by trying mainnet first, then signet. The FFI call used is
//  the free function `initWallet`, which is `Wallet::create` alone (connect,
//  handshake, ArkInfo, chain check, safety check, one properties row) and needs
//  neither an Esplora nor an onchain wallet. It runs against a scratch directory
//  with a throwaway phrase, never the real datadir or the keychain.
//
//  Cancellation: a uniffi async call cannot be interrupted (the bindings trap on
//  `CALL_CANCELLED`), and bark sets no connect timeout. So the ceiling and the
//  caller's cancellation are implemented as a race: the probe result is handed
//  back through a continuation that whichever side finishes first resumes.
//  An attempt still in flight at that point is orphaned; it removes its own
//  scratch directory when the FFI eventually returns, and the attempts task is
//  cancelled so no second chain is tried.
//

import Foundation
import Bark
import ArkeUI
import OSLog

/// What a successful probe learned about a server.
nonisolated struct ArkServerProbeResult: Equatable, Sendable {
    /// Chain the server runs on.
    let network: BitcoinNetwork
    /// The server URL in its canonical stored form (`NetworkConfig.canonicalServerURL`).
    let arkServerBaseURL: String
}

nonisolated enum ArkServerProbeError: Swift.Error, LocalizedError, Equatable, Sendable {
    /// The input has no host.
    case invalidURL
    /// Neither chain accepted the server: unreachable, not a bark server,
    /// incompatible protocol, or bark judged its ArkInfo unsafe. Carries
    /// bark's own text for the log and the form.
    case unreachableOrIncompatible(String)
    /// The whole probe exceeded `BarkWalletFFI.serverProbeTimeout`.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "server_probe_invalid_url", defaultValue: "Enter a server address like ark.example.com.")
        case .unreachableOrIncompatible:
            return String(localized: "server_probe_unreachable", defaultValue: "Could not connect to an Ark server at this address.")
        case .timedOut:
            return String(localized: "server_probe_timed_out", defaultValue: "The server did not answer in time.")
        }
    }
}

/// First-finisher-wins hand-off between the attempts task, the timeout task
/// and the caller's cancellation. Thread-safe; resumes the continuation once.
private final class ProbeRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ArkServerProbeResult, Swift.Error>?

    func arm(_ continuation: CheckedContinuation<ArkServerProbeResult, Swift.Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ result: Result<ArkServerProbeResult, Swift.Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

extension BarkWalletFFI {

    /// Ceiling for the whole probe, both chain attempts included.
    static let serverProbeTimeout: Duration = .seconds(20)

    /// Chains tried, in order. Mainnet first: it is the default and the common case.
    private static let serverProbeChains: [(ffi: Network, app: BitcoinNetwork)] = [
        (.bitcoin, .mainnet),
        (.signet, .signet),
    ]

    /// Probe an Ark server URL. Throws `ArkServerProbeError` or
    /// `CancellationError`; succeeds with the chain the server runs on. Safe to
    /// call with no wallet open and no wallet on disk; touches only a scratch
    /// directory under `tmp/`.
    static func probeServer(url rawURL: String) async throws -> ArkServerProbeResult {
        guard let serverURL = NetworkConfig.canonicalServerURL(rawURL) else {
            throw ArkServerProbeError.invalidURL
        }
        Self.logger.info("🔎 [Probe] Probing Ark server \(serverURL, privacy: .public)")

        let race = ProbeRace()

        let attempts = Task {
            var messages: [String] = []
            for chain in serverProbeChains {
                try Task.checkCancellation()
                do {
                    try await probeAttempt(serverURL: serverURL, network: chain.ffi)
                    Self.logger.info("🔎 [Probe] \(serverURL, privacy: .public) answered on \(chain.app.rawValue, privacy: .public)")
                    return ArkServerProbeResult(network: chain.app, arkServerBaseURL: serverURL)
                } catch is CancellationError {
                    throw CancellationError()
                } catch Bark.Error.Inner(let message) {
                    // bark's own text, not the enum's debug description
                    messages.append(message)
                    Self.logger.notice("🔎 [Probe] \(serverURL, privacy: .public) refused as \(chain.app.rawValue, privacy: .public): \(message, privacy: .public)")
                } catch {
                    messages.append(error.localizedDescription)
                    Self.logger.notice("🔎 [Probe] \(serverURL, privacy: .public) refused as \(chain.app.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            throw ArkServerProbeError.unreachableOrIncompatible(Self.probeFailureDetail(messages))
        }

        let timeout = Task {
            try await Task.sleep(for: serverProbeTimeout)
        }

        defer {
            timeout.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ArkServerProbeResult, Swift.Error>) in
                race.arm(continuation)
                Task {
                    do {
                        race.finish(.success(try await attempts.value))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                Task {
                    do {
                        try await timeout.value
                    } catch {
                        return // attempts finished first and cancelled the timeout
                    }
                    Self.logger.notice("🔎 [Probe] \(serverURL, privacy: .public) timed out after \(Self.serverProbeTimeout.components.seconds) s; an attempt may still be in flight")
                    attempts.cancel()
                    race.finish(.failure(ArkServerProbeError.timedOut))
                }
            }
        } onCancel: {
            // Caller gave up (address edited, form left): answer immediately;
            // the attempts task stops before its next chain
            attempts.cancel()
            race.finish(.failure(CancellationError()))
        }
    }

    /// The message shown under the failure headline. Each attempt that is
    /// refused for the *wrong chain* says so and nothing else, so prefer the
    /// attempt that failed for a real reason (unreachable, incompatible,
    /// unsafe) over a "network mismatch" line.
    static func probeFailureDetail(_ messages: [String]) -> String {
        messages.last(where: { !$0.localizedCaseInsensitiveContains("network mismatch") })
            ?? messages.last
            ?? ""
    }

    /// One `Wallet::create` against a scratch directory. Throws whatever bark
    /// throws (network mismatch, connection, protocol, unsafe ArkInfo).
    private static func probeAttempt(serverURL: String, network: Network) async throws {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arke-server-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }

        // Throwaway phrase: lives in this frame only, never stored or logged.
        let mnemonic = try Bark.generateMnemonic()

        let config = Config(
            serverAddress: serverURL,
            serverAccessToken: nil,
            esploraAddress: nil,          // create() never touches the chain source
            bitcoindAddress: nil,
            bitcoindCookiefile: nil,
            bitcoindUser: nil,
            bitcoindPass: nil,
            vtxoRefreshExpiryThreshold: nil,
            vtxoExitMargin: nil,
            htlcRecvClaimDelta: nil,
            fallbackFeeRate: defaultFallbackFeeRateSatPerVb,
            roundTxRequiredConfirmations: nil,
            daemonSyncIntervalSecs: nil,
            offboardRequiredConfirmations: nil,
            daemonManualSync: nil,
            lightningReceiveClaimRetries: nil,
            userAgent: userAgent,
            vtxoKeyGapLimit: nil
        )

        try await Bark.initWallet(
            network: network,
            mnemonicOrSeed: mnemonic,
            config: config,
            datadir: scratchDir.path,
            allowUnreachableServer: false
        )
    }
}
