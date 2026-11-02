import Foundation
import ArkeUI

// MARK: - Bitcoin Network Types
// `BitcoinNetwork` is a pure value type and now lives in the ArkéUI package.
// Its `NetworkConfig`-based helper stays here, since `NetworkConfig` is app-side.

extension BitcoinNetwork {
    /// Check if this network matches a NetworkConfig
    func matches(_ networkConfig: NetworkConfig) -> Bool {
        return self.rawValue == networkConfig.networkType.lowercased()
    }
}

// MARK: - Ark Server Identity

/// Which Ark server a wallet talks to, kept apart from which chain it is on.
/// The chain is `NetworkConfig.networkType`; this is the operator. Features
/// that depend on the operator (the signet faucet, push relay allowlisting)
/// key on this, features that depend on the chain (fee caps, exit fee rate,
/// address validation) key on `networkType` (Features/Ark_Server_Selection.md).
nonisolated enum ArkServerKind: String, Codable, Equatable, Sendable {
    case secondMainnet
    case secondSignet
    case custom
}

// MARK: - Network Configuration Models

nonisolated struct NetworkConfig: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let esploraURL: String
    let arkServerURL: String
    let arkServerAccessToken: String?
    /// Chain only: `"mainnet"` or `"signet"` (the `BitcoinNetwork` raw values
    /// bark accepts). Never a server name; the server is `serverKind`.
    let networkType: String
    let serverKind: ArkServerKind

    var isMainnet: Bool {
        networkType.lowercased() == BitcoinNetwork.mainnet.rawValue
    }

    var esploraBaseURL: String {
        Self.normalizedBaseURL(esploraURL)
    }

    var arkServerBaseURL: String {
        Self.normalizedBaseURL(arkServerURL)
    }

    /// Ensure the URL has a lower-case `https://` (or `http://`) scheme and no
    /// trailing slash. Schemes are matched case-insensitively so a typed
    /// `HTTPS://` does not get a second scheme prepended.
    static func normalizedBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        var url: String
        if lower.hasPrefix("https://") {
            url = "https://" + trimmed.dropFirst("https://".count)
        } else if lower.hasPrefix("http://") {
            url = "http://" + trimmed.dropFirst("http://".count)
        } else {
            url = "https://" + trimmed
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }
}

// MARK: - Predefined Network Configurations

extension NetworkConfig {
    /// Second's mainnet server. The id is persisted on every installed device,
    /// so it never changes.
    static let mainnet = NetworkConfig(
        id: "mainnet",
        name: "Bitcoin Mainnet",
        esploraURL: "mempool.second.tech/api",
        arkServerURL: "ark.second.tech",
        arkServerAccessToken: nil,
        networkType: BitcoinNetwork.mainnet.rawValue,
        serverKind: .secondMainnet
    )

    /// Second's signet server. Same id stability rule as `mainnet`.
    static let signet = NetworkConfig(
        id: "signet",
        name: "Bitcoin Signet",
        esploraURL: "esplora.signet.2nd.dev",
        arkServerURL: "ark.signet.2nd.dev",
        arkServerAccessToken: nil,
        networkType: BitcoinNetwork.signet.rawValue,
        serverKind: .secondSignet
    )

    /// Terms of use of Second's mainnet server, as the server itself advertises
    /// in `ArkInfo.tos_link` (verified 2026-10-29). Hard-coded because the Swift
    /// bindings do not expose that field yet; Second's signet server advertises
    /// no terms.
    static let secondMainnetTermsURL: URL = {
        guard let url = URL(string: "https://second.tech/terms") else {
            preconditionFailure("constant URL")
        }
        return url
    }()

    /// The built-in servers, in the order the cover-screen sheet lists them.
    /// (The former `testnet` preset had no server and was dropped 2026-10-29.)
    static let presets: [NetworkConfig] = [mainnet, signet]

    static func preset(byId id: String) -> NetworkConfig? {
        presets.first { $0.id == id }
    }

    /// The Esplora the custom-server form prefills for a detected chain:
    /// Second's for that chain, so the chain-data trust stays where it is today.
    /// Returned in the stored form (`https://`, no trailing slash) so the field
    /// shows the same text before and after saving.
    static func defaultEsploraURL(for network: BitcoinNetwork) -> String {
        switch network {
        case .mainnet: return mainnet.esploraBaseURL
        case .signet, .testnet, .regtest: return signet.esploraBaseURL
        }
    }
}

// MARK: - Custom Servers

extension NetworkConfig {
    /// A user-entered Ark server on a known chain.
    ///
    /// The id is deterministic (`custom:<chain>:<host[:port]>`) so two devices
    /// that enter the same server agree on it, and reconciliation's id
    /// comparison keeps meaning "same server". Returns nil when the URL has no
    /// host.
    static func custom(
        arkServerURL: String,
        esploraURL: String,
        network: BitcoinNetwork,
        name: String? = nil
    ) -> NetworkConfig? {
        guard let host = serverHost(arkServerURL),
              let canonical = canonicalServerURL(arkServerURL) else { return nil }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NetworkConfig(
            id: customId(network: network, host: host),
            name: trimmedName.isEmpty ? host : trimmedName,
            esploraURL: esploraURL,
            arkServerURL: canonical,
            arkServerAccessToken: nil,
            networkType: network.rawValue,
            serverKind: .custom
        )
    }

    /// The one form a custom server address is probed and stored in: scheme +
    /// lower-cased host[:port], no path. An Ark server address has no path,
    /// and one canonical form keeps the probe, the sheet, the cover label and
    /// the id in agreement whatever was typed. Nil when there is no host.
    static func canonicalServerURL(_ raw: String) -> String? {
        guard let host = serverHost(raw) else { return nil }
        let scheme = normalizedBaseURL(raw).hasPrefix("http://") ? "http://" : "https://"
        return scheme + host
    }

    static let customIdPrefix = "custom:"

    /// The host part of a custom id (`custom:<chain>:<host>`), for messages.
    static func hostFromCustomId(_ id: String) -> String? {
        guard id.hasPrefix(customIdPrefix) else { return nil }
        let parts = id.dropFirst(customIdPrefix.count).split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    static func customId(network: BitcoinNetwork, host: String) -> String {
        "\(customIdPrefix)\(network.rawValue):\(host)"
    }

    /// Lower-cased host, with the port when one is given, of a server URL
    /// written with or without a scheme.
    static func serverHost(_ raw: String) -> String? {
        guard let components = URLComponents(string: normalizedBaseURL(raw)),
              let host = components.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }
}

// MARK: - Address Validation Integration

extension NetworkConfig {
    /// Get the corresponding BitcoinNetwork for address validation
    var bitcoinNetwork: BitcoinNetwork? {
        return BitcoinNetwork(networkType: networkType)
    }

    /// Validate a payment request against this network configuration
    func isValidPaymentRequest(_ input: String) -> Bool {
        return AddressValidator.isValidPaymentRequest(input, for: self)
    }

    /// Parse a payment request ensuring it matches this network
    func parsePaymentRequest(_ input: String) -> PaymentRequest? {
        return AddressValidator.parsePaymentRequest(input, expectedNetwork: self)
    }
}
