//
//  PaymentDestination.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import Foundation
import ArkeUI

/// Represents a single payment destination with format-specific information
struct PaymentDestination: Identifiable, Hashable, Codable {
    let id: UUID
    let format: AddressFormat
    let network: BitcoinNetwork?
    let address: String
    
    // Format-specific data
    let scanPublicKey: Data? // For silent payments
    let spendPublicKey: Data? // For silent payments
    
    // MARK: - Computed Properties
    
    /// Display name with network information if available
    var displayName: String {
        if let network = network {
            return "\(format.displayName) (\(network.displayName))"
        } else {
            return format.displayName
        }
    }
    
    /// Check if this is a Bitcoin-based address format
    var isBitcoin: Bool {
        return format.supportsBitcoinNetworks
    }
    
    /// Shortened address for display (first 8 + L10n.symbolEllipsis + last 8 characters)
    var shortAddress: String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }
    
    // MARK: - Initializers
    
    init(
        format: AddressFormat,
        network: BitcoinNetwork?,
        address: String,
        scanPublicKey: Data? = nil,
        spendPublicKey: Data? = nil
    ) {
        self.id = UUID()
        self.format = format
        self.network = network
        self.address = address
        self.scanPublicKey = scanPublicKey
        self.spendPublicKey = spendPublicKey
    }
    
    // MARK: - Methods
    
    /// Check if this destination is compatible with a specific network configuration
    func isCompatible(with networkConfig: NetworkConfig) -> Bool {
        guard let network = network else {
            // Non-Bitcoin addresses (Lightning, BIP-353) are generally network-agnostic
            return !format.supportsBitcoinNetworks
        }
        
        // Special case: testnet and signet addresses are indistinguishable by format
        // (both use tb1 for bech32, both use similar address formats)
        // So we treat them as compatible with each other
        let testNetworks: Set<String> = ["testnet", "signet", "regtest"]
        let destinationNetworkType = network.rawValue.lowercased()
        let configNetworkType = networkConfig.networkType.lowercased()
        
        if testNetworks.contains(destinationNetworkType) && testNetworks.contains(configNetworkType) {
            // Allow any test network address to work with any test network config
            return true
        }
        
        return network.matches(networkConfig)
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(format)
        hasher.combine(network)
        hasher.combine(address)
    }
    
    static func == (lhs: PaymentDestination, rhs: PaymentDestination) -> Bool {
        return lhs.format == rhs.format &&
               lhs.network == rhs.network &&
               lhs.address == rhs.address
    }
}

// MARK: - CustomStringConvertible
extension PaymentDestination: CustomStringConvertible {
    var description: String {
        return "\(displayName): \(shortAddress)"
    }
}
