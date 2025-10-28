import Foundation
import Combine

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
