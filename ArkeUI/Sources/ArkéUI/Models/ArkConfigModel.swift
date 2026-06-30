//
//  ArkConfigModel.swift
//  ArkéUI
//
//  Created by Christoph on 10/20/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark). Localized strings use `bundle: .module`.
//

import Foundation

public struct ArkConfigModel: Codable, Sendable {
    // Required fields
    public let serverAddress: String  // Previously "ark" - matches FFI Config.serverAddress

    // Optional connection settings
    public let esploraAddress: String?
    public let bitcoindAddress: String?
    public let bitcoindCookiefile: String?
    public let bitcoindUser: String?
    public let bitcoindPass: String?

    // Network configuration
    public let network: String  // "bitcoin", "testnet", "signet", "regtest"

    // VTXO and round settings (all optional with defaults in Rust)
    public let vtxoRefreshExpiryThreshold: UInt32?
    public let vtxoExitMargin: UInt16?
    public let htlcRecvClaimDelta: UInt16?
    public let fallbackFeeRate: UInt64?  // In sat/vB
    public let roundTxRequiredConfirmations: UInt32?

    // Daemon settings (new in v0.6.3)
    public let daemonSyncIntervalSecs: UInt64?  // Unified sync interval (replaces fast/slow intervals)
    public let offboardRequiredConfirmations: UInt32?
    public let daemonManualSync: Bool?
    public let lightningReceiveClaimRetries: UInt8?

    enum CodingKeys: String, CodingKey {
        case serverAddress = "server_address"
        case esploraAddress = "esplora_address"
        case bitcoindAddress = "bitcoind_address"
        case bitcoindCookiefile = "bitcoind_cookiefile"
        case bitcoindUser = "bitcoind_user"
        case bitcoindPass = "bitcoind_pass"
        case network
        case vtxoRefreshExpiryThreshold = "vtxo_refresh_expiry_threshold"
        case vtxoExitMargin = "vtxo_exit_margin"
        case htlcRecvClaimDelta = "htlc_recv_claim_delta"
        case fallbackFeeRate = "fallback_fee_rate"
        case roundTxRequiredConfirmations = "round_tx_required_confirmations"
        case daemonSyncIntervalSecs = "daemon_sync_interval_secs"
        case offboardRequiredConfirmations = "offboard_required_confirmations"
        case daemonManualSync = "daemon_manual_sync"
        case lightningReceiveClaimRetries = "lightning_receive_claim_retries"
    }

    public init(serverAddress: String, esploraAddress: String? = nil, bitcoindAddress: String? = nil, bitcoindCookiefile: String? = nil, bitcoindUser: String? = nil, bitcoindPass: String? = nil, network: String, vtxoRefreshExpiryThreshold: UInt32? = nil, vtxoExitMargin: UInt16? = nil, htlcRecvClaimDelta: UInt16? = nil, fallbackFeeRate: UInt64? = nil, roundTxRequiredConfirmations: UInt32? = nil, daemonSyncIntervalSecs: UInt64? = nil, offboardRequiredConfirmations: UInt32? = nil, daemonManualSync: Bool? = nil, lightningReceiveClaimRetries: UInt8? = nil) {
        self.serverAddress = serverAddress
        self.esploraAddress = esploraAddress
        self.bitcoindAddress = bitcoindAddress
        self.bitcoindCookiefile = bitcoindCookiefile
        self.bitcoindUser = bitcoindUser
        self.bitcoindPass = bitcoindPass
        self.network = network
        self.vtxoRefreshExpiryThreshold = vtxoRefreshExpiryThreshold
        self.vtxoExitMargin = vtxoExitMargin
        self.htlcRecvClaimDelta = htlcRecvClaimDelta
        self.fallbackFeeRate = fallbackFeeRate
        self.roundTxRequiredConfirmations = roundTxRequiredConfirmations
        self.daemonSyncIntervalSecs = daemonSyncIntervalSecs
        self.offboardRequiredConfirmations = offboardRequiredConfirmations
        self.daemonManualSync = daemonManualSync
        self.lightningReceiveClaimRetries = lightningReceiveClaimRetries
    }

    // MARK: - Computed Properties

    // Legacy property aliases for backward compatibility
    public var ark: String { serverAddress }
    public var esplora: String? { esploraAddress }
    public var bitcoind: String? { bitcoindAddress }
    public var bitcoindCookie: String? { bitcoindCookiefile }

    public var hasArkEndpoint: Bool {
        !serverAddress.isEmpty
    }

    public var hasEsploraEndpoint: Bool {
        esploraAddress != nil && !esploraAddress!.isEmpty
    }

    public var hasBitcoindConnection: Bool {
        bitcoindAddress != nil && !bitcoindAddress!.isEmpty
    }

    public var arkURL: URL? {
        URL(string: serverAddress)
    }

    public var esploraURL: URL? {
        guard let esploraAddress = esploraAddress else { return nil }
        return URL(string: esploraAddress)
    }

    public var bitcoindURL: URL? {
        guard let bitcoindAddress = bitcoindAddress else { return nil }
        return URL(string: bitcoindAddress)
    }

    // Formatted fallback fee rate in sat/vB (direct value, not kvb)
    public var fallbackFeeRateSatPerVB: UInt64 {
        fallbackFeeRate ?? 10  // Default to 10 sat/vB if not set
    }

    // Formatted VTXO refresh threshold with default
    public var vtxoRefreshThresholdBlocks: UInt32 {
        vtxoRefreshExpiryThreshold ?? 144  // Default to 144 blocks if not set
    }

    // Check if using signet endpoints (based on common signet domain patterns or network field)
    public var isSignetConfig: Bool {
        if network.lowercased() == "signet" {
            return true
        }

        let signetKeywords = ["signet", "testnet"]
        let serverContainsSignet = signetKeywords.contains { keyword in
            serverAddress.lowercased().contains(keyword)
        }
        let esploraContainsSignet = signetKeywords.contains { keyword in
            esploraAddress?.lowercased().contains(keyword) ?? false
        }
        return serverContainsSignet || esploraContainsSignet
    }

    public var isMainnet: Bool {
        network.lowercased() == "bitcoin"
    }

    public var isTestnet: Bool {
        network.lowercased() == "testnet"
    }

    public var isRegtest: Bool {
        network.lowercased() == "regtest"
    }

    // Configuration summary for display
    public var configurationSummary: String {
        var summary = [String]()

        summary.append(String(localized: "format_network", defaultValue: "Network: \(network)", bundle: .module))
        summary.append(String(localized: "data_server", defaultValue: "Server: \(serverAddress)", bundle: .module))

        if hasEsploraEndpoint {
            summary.append("Esplora: \(esploraAddress!)")
        }
        if hasBitcoindConnection {
            summary.append("Bitcoin Core: \(bitcoindAddress!)")
        }

        summary.append("Fee Rate: \(fallbackFeeRateSatPerVB) sat/vB")
        summary.append("Refresh Threshold: \(vtxoRefreshThresholdBlocks) blocks")

        if let exitMargin = vtxoExitMargin {
            summary.append("Exit Margin: \(exitMargin) blocks")
        }
        if let htlcDelta = htlcRecvClaimDelta {
            summary.append("HTLC Claim Delta: \(htlcDelta) blocks")
        }
        if let confirmations = roundTxRequiredConfirmations {
            summary.append("Required Confirmations: \(confirmations)")
        }

        return summary.joined(separator: "\n")
    }
}
