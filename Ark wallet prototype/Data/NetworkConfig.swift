import Foundation
import Combine

// MARK: - Bitcoin Network Types

enum BitcoinNetwork: String, CaseIterable {
    case mainnet = "mainnet"
    case testnet = "testnet"
    case signet = "signet"
    case regtest = "regtest"
    
    var displayName: String {
        switch self {
        case .mainnet:
            return "Bitcoin Mainnet"
        case .testnet:
            return "Bitcoin Testnet"
        case .signet:
            return "Bitcoin Signet"
        case .regtest:
            return "Bitcoin Regtest"
        }
    }
    
    /// Initialize from NetworkConfig networkType string
    init?(networkType: String) {
        switch networkType.lowercased() {
        case "mainnet":
            self = .mainnet
        case "testnet":
            self = .testnet
        case "signet":
            self = .signet
        case "regtest":
            self = .regtest
        default:
            return nil
        }
    }
    
    /// Check if this network matches a NetworkConfig
    func matches(_ networkConfig: NetworkConfig) -> Bool {
        return self.rawValue == networkConfig.networkType.lowercased()
    }
}

// MARK: - Network Configuration Models

struct NetworkConfig: Codable, Equatable {
    let id: String
    let name: String
    let esploraURL: String
    let aspURL: String
    let isMainnet: Bool
    let networkType: String // "mainnet", "signet", "testnet", "custom"
    
    var esploraBaseURL: String {
        // Ensure URL has https:// prefix and no trailing slash
        let url = esploraURL.hasPrefix("http") ? esploraURL : "https://\(esploraURL)"
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }
    
    var aspBaseURL: String {
        // Ensure URL has https:// prefix and no trailing slash
        let url = aspURL.hasPrefix("http") ? aspURL : "https://\(aspURL)"
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

// MARK: - Predefined Network Configurations

extension NetworkConfig {
    static let mainnet = NetworkConfig(
        id: "mainnet",
        name: "Bitcoin Mainnet",
        esploraURL: "blockstream.info/api",
        aspURL: "ark.mainnet.arkdev.info", // Replace with actual mainnet ASP when available
        isMainnet: true,
        networkType: "mainnet"
    )
    
    static let signet = NetworkConfig(
        id: "signet",
        name: "Bitcoin Signet",
        esploraURL: "esplora.signet.2nd.dev",
        aspURL: "ark.signet.2nd.dev",
        isMainnet: false,
        networkType: "signet"
    )
    
    static let testnet = NetworkConfig(
        id: "testnet",
        name: "Bitcoin Testnet",
        esploraURL: "blockstream.info/testnet/api",
        aspURL: "ark.testnet.arkdev.info", // Replace with actual testnet ASP when available
        isMainnet: false,
        networkType: "testnet"
    )
    
    static let defaultNetworks: [NetworkConfig] = [signet, testnet, mainnet]
    
    static func custom(name: String, esploraURL: String, aspURL: String, isMainnet: Bool) -> NetworkConfig {
        NetworkConfig(
            id: "custom_\(UUID().uuidString)",
            name: name,
            esploraURL: esploraURL,
            aspURL: aspURL,
            isMainnet: isMainnet,
            networkType: "custom"
        )
    }
}

// MARK: - Address Validation Integration

extension NetworkConfig {
    /// Get the corresponding BitcoinNetwork for address validation
    var bitcoinNetwork: BitcoinNetwork? {
        return BitcoinNetwork(networkType: networkType)
    }
    
    /// Validate an address against this network configuration
    func isValidAddress(_ address: String) -> Bool {
        return AddressValidator.isValidAddress(address, for: self)
    }
    
    /// Parse an address ensuring it matches this network
    func parseAddress(_ address: String) -> ParsedAddress? {
        return AddressValidator.parseAddress(address, expectedNetwork: self)
    }
}
