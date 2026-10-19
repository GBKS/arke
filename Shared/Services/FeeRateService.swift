//
//  FeeRateService.swift
//  Arké
//
//  App-wide onchain fee rate estimation, fetched from the configured
//  Esplora backend's /fee-estimates endpoint.
//
//  Tier mapping mirrors Bark's own chain source (bark chain.rs:
//  FEE_RATE_TARGET_CONF_FAST/REGULAR/SLOW = 1/3/6 blocks), so estimates
//  shown in the UI agree with the rates Bark actually broadcasts at when
//  it resolves a nil fee rate internally.
//

import Foundation
import ArkeUI
import os

/// Service responsible for fetching and caching onchain fee rates
@MainActor
@Observable
class FeeRateService {

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "FeeRateService")

    // MARK: - Published Properties

    /// Latest known fee rates. Starts at the hardcoded fallback defaults
    /// and is replaced by live Esplora data after the first successful fetch.
    private(set) var feeRates: OnchainFeeRates = .default

    /// When the rates were last fetched successfully; nil means `feeRates`
    /// still holds the fallback defaults.
    private(set) var lastUpdated: Date?

    /// True once live (non-fallback) rates are available
    var isLive: Bool {
        lastUpdated != nil
    }

    // MARK: - Dependencies

    private let taskManager: TaskDeduplicationManager
    private let esploraBaseURL: @MainActor () -> String?
    private let maxRateSatPerVb: @MainActor () -> UInt64

    /// Esplora confirmation targets (in blocks) for each priority tier,
    /// matching Bark's fast/regular/slow targets.
    private nonisolated static let fastTarget = 1
    private nonisolated static let mediumTarget = 3
    private nonisolated static let slowTarget = 6

    /// Sanity cap for networks whose coins are worthless (signet/regtest):
    /// spam with enormous attached fees regularly drives their estimators to
    /// six-digit sat/vB, which would block exits and sends entirely. High
    /// enough to be invisible when the network is quiet.
    nonisolated static let nonMainnetMaxRateSatPerVb: UInt64 = 50

    /// Sanity ceiling for mainnet. Not a policy cap: a real fee spike is
    /// information and must stay visible, and the highest next-block
    /// estimates ever seen on mainnet are a small fraction of this. It
    /// exists so that a poisoned or buggy estimator cannot hand the app a
    /// number its fee arithmetic cannot hold — the destination ranker's
    /// `Int(feeRate * vBytes)` and the exit cost estimate's `UInt64`
    /// products trap on overflow, and neither checks (Tier 0 item,
    /// 2026-10-19). Every rate the app computes with is bounded by one of
    /// these two constants; no other code constructs `OnchainFeeRates`.
    nonisolated static let mainnetMaxRateSatPerVb: UInt64 = 10_000

    // MARK: - Initialization

    /// - Parameters:
    ///   - taskManager: Shared deduplication manager
    ///   - esploraBaseURL: Provider for the currently active Esplora base URL,
    ///     evaluated on every fetch so runtime network switches are picked up
    ///   - maxRateSatPerVb: Provider for the network-dependent sanity cap on
    ///     all tiers, evaluated on every fetch. There is no uncapped mode;
    ///     the default is the mainnet ceiling.
    init(
        taskManager: TaskDeduplicationManager,
        esploraBaseURL: @escaping @MainActor () -> String?,
        maxRateSatPerVb: @escaping @MainActor () -> UInt64 = { FeeRateService.mainnetMaxRateSatPerVb }
    ) {
        self.taskManager = taskManager
        self.esploraBaseURL = esploraBaseURL
        self.maxRateSatPerVb = maxRateSatPerVb
    }

    // MARK: - Access

    /// Returns cached rates when fresh, otherwise refreshes first.
    /// Never throws: on fetch failure the last-known-good rates (or the
    /// fallback defaults) are returned.
    func currentRates(maxAge: TimeInterval = 300) async -> OnchainFeeRates {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge {
            return feeRates
        }
        await refresh()
        return feeRates
    }

    /// Fetch fresh rates from Esplora (deduplicated). Keeps the previous
    /// rates on failure.
    func refresh() async {
        await taskManager.execute(key: "feeRates") {
            await self.fetchAndStore()
        }
    }

    // MARK: - Fetching

    private func fetchAndStore() async {
        guard let baseURL = esploraBaseURL(), let url = URL(string: "\(baseURL)/fee-estimates") else {
            Self.logger.warning("No Esplora URL available for fee estimation")
            return
        }
        // Read alongside the URL, before the request: both come from the
        // network config, and a config switch during the 15 s request must
        // not pair one network's rates with the other's cap
        let maxRate = maxRateSatPerVb()

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                Self.logger.warning("Fee estimates request failed with status \(httpResponse.statusCode)")
                return
            }

            let estimates = try JSONDecoder().decode([String: Double].self, from: data)

            guard let rates = Self.parse(esploraEstimates: estimates, maxRate: maxRate) else {
                Self.logger.warning("Fee estimates response could not be parsed into rates")
                return
            }

            feeRates = rates
            lastUpdated = Date()
            Self.logger.info("Fee rates updated: fast \(rates.fast), medium \(rates.medium), slow \(rates.slow) sat/vB")
            if rates.fast == maxRate {
                // Routine on signet under fee spam; on mainnet it means the
                // estimator handed back something no real mempool produces
                // Host stays private like every other Esplora-URL log line:
                // a custom network's host is the user's own
                Self.logger.warning("Fee rate estimate clamped to the \(maxRate) sat/vB cap; the Esplora estimator at \(baseURL) is reporting higher")
            }

        } catch {
            Self.logger.warning("Failed to fetch fee estimates: \(error.localizedDescription)")
            // Keep last-known-good rates (or defaults)
        }
    }

    // MARK: - Parsing

    /// Convert an Esplora /fee-estimates response (confirmation target in
    /// blocks → sat/vB) into tiered rates.
    ///
    /// For each tier the largest available target ≤ the desired one is used
    /// (erring on the side of a higher rate); if none exists, the smallest
    /// available target. Rates are rounded up and clamped to ≥ 1 sat/vB.
    ///
    /// Tiers are clamped to fast ≥ medium ≥ slow: a longer confirmation
    /// target can never legitimately cost more than a shorter one, but
    /// esplora estimators have been observed returning garbage for
    /// individual targets (e.g. signet reporting 27k sat/vB at target 6
    /// while targets 1-3 sit at 1.8).
    ///
    /// `maxRate` additionally caps every tier — the monotonic clamp can't
    /// help when ALL targets are garbage (signet fee spam pushing even
    /// target 1 to six-digit sat/vB). It is never absent: the default is
    /// the mainnet ceiling, so a caller that forgets it gets the loosest
    /// bound the fee arithmetic downstream can still hold.
    nonisolated static func parse(esploraEstimates: [String: Double], maxRate: UInt64 = mainnetMaxRateSatPerVb) -> OnchainFeeRates? {
        let entries = esploraEstimates
            .compactMap { key, value -> (target: Int, rate: Double)? in
                // UInt64(exactly:) drops a rate too large to represent, which
                // would trap the conversion in rate(forTarget:)
                guard let target = Int(key), target > 0, value > 0, value.isFinite,
                      UInt64(exactly: value.rounded(.up)) != nil else { return nil }
                return (target, value)
            }
            .sorted { $0.target < $1.target }

        guard !entries.isEmpty else { return nil }

        func rate(forTarget target: Int) -> UInt64 {
            let entry = entries.last { $0.target <= target } ?? entries[0]
            let rounded = max(1, UInt64(entry.rate.rounded(.up)))
            return min(rounded, maxRate)
        }

        let fast = rate(forTarget: fastTarget)
        let medium = min(rate(forTarget: mediumTarget), fast)
        let slow = min(rate(forTarget: slowTarget), medium)

        return OnchainFeeRates(fast: fast, medium: medium, slow: slow)
    }
}
