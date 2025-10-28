import Foundation

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

// MARK: - Network Settings Manager

@MainActor
class NetworkSettingsManager: ObservableObject {
    @Published var currentNetwork: NetworkConfig
    @Published var customNetworks: [NetworkConfig] = []
    
    private let userDefaults = UserDefaults.standard
    private let currentNetworkKey = "currentNetwork"
    private let customNetworksKey = "customNetworks"
    
    init() {
        // Load current network from UserDefaults, default to signet
        if let data = userDefaults.data(forKey: currentNetworkKey),
           let network = try? JSONDecoder().decode(NetworkConfig.self, from: data) {
            self.currentNetwork = network
        } else {
            self.currentNetwork = NetworkConfig.signet
        }
        
        // Load custom networks
        if let data = userDefaults.data(forKey: customNetworksKey),
           let networks = try? JSONDecoder().decode([NetworkConfig].self, from: data) {
            self.customNetworks = networks
        }
    }
    
    var allNetworks: [NetworkConfig] {
        NetworkConfig.defaultNetworks + customNetworks
    }
    
    func setCurrentNetwork(_ network: NetworkConfig) {
        currentNetwork = network
        saveCurrentNetwork()
    }
    
    func addCustomNetwork(_ network: NetworkConfig) {
        customNetworks.append(network)
        saveCustomNetworks()
    }
    
    func removeCustomNetwork(_ network: NetworkConfig) {
        customNetworks.removeAll { $0.id == network.id }
        saveCustomNetworks()
        
        // If we removed the current network, switch to signet
        if currentNetwork.id == network.id {
            setCurrentNetwork(.signet)
        }
    }
    
    private func saveCurrentNetwork() {
        if let data = try? JSONEncoder().encode(currentNetwork) {
            userDefaults.set(data, forKey: currentNetworkKey)
        }
    }
    
    private func saveCustomNetworks() {
        if let data = try? JSONEncoder().encode(customNetworks) {
            userDefaults.set(data, forKey: customNetworksKey)
        }
    }
    
    // Helper methods for UI
    func networkDisplayName(_ network: NetworkConfig) -> String {
        if network.isMainnet {
            return "🔴 \(network.name)" // Red indicator for mainnet
        } else {
            return "🔵 \(network.name)" // Blue indicator for testnet/signet
        }
    }
    
    func isCurrentNetwork(_ network: NetworkConfig) -> Bool {
        currentNetwork.id == network.id
    }
}