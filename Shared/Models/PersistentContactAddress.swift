//
//  PersistentContactAddress.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/05/25.
//

import Foundation
import ArkeUI
import SwiftData

@Model
final class PersistentContactAddress {
    var id: UUID = UUID()  // CloudKit: removed .unique, added default
    var address: String = ""  // CloudKit: added default
    var normalizedAddress: String = ""  // CloudKit: added default
    var formatRawValue: String = AddressFormat.bitcoin.rawValue  // CloudKit: added default
    var label: String?
    var isPrimary: Bool = false  // CloudKit: added default
    var networkRawValue: String?
    var createdAt: Date = Date()  // CloudKit: added default
    var updatedAt: Date = Date()  // CloudKit: added default
    
    // Relationship back to contact
    @Relationship(inverse: \PersistentContact.addresses) 
    var contact: PersistentContact?
    
    // MARK: - Initializers
    
    init(id: UUID = UUID(), address: String, normalizedAddress: String, format: AddressFormat, label: String? = nil, isPrimary: Bool = false, network: BitcoinNetwork? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.address = address
        self.normalizedAddress = normalizedAddress
        self.formatRawValue = format.rawValue
        self.label = label
        self.isPrimary = isPrimary
        self.networkRawValue = network?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties for Enum Conversion
    
    var format: AddressFormat {
        get { AddressFormat(rawValue: formatRawValue) ?? .bitcoin }
        set { formatRawValue = newValue.rawValue }
    }
    
    var network: BitcoinNetwork? {
        get { 
            guard let rawValue = networkRawValue else { return nil }
            return BitcoinNetwork(rawValue: rawValue)
        }
        set { networkRawValue = newValue?.rawValue }
    }
    
    // MARK: - Display Properties
    
    /// Display name for the address (label if available, otherwise format name)
    var displayName: String {
        if let label = label, !label.isEmpty {
            return label
        }
        return format.displayName
    }
    
    /// Shortened address for display
    var shortAddress: String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }
    
    // MARK: - Methods
    
    /// Helper method to update the updatedAt timestamp
    func touch() {
        updatedAt = Date()
    }
    
    /// Check if this address supports Bitcoin networks
    var supportsBitcoinNetworks: Bool {
        format.supportsBitcoinNetworks
    }
    
    /// Check if this address is compatible with a specific network configuration
    func isCompatibleWith(_ networkConfig: NetworkConfig) -> Bool {
        guard let network = network else {
            // Non-Bitcoin addresses (Lightning, BIP-353) are generally network-agnostic
            return !format.supportsBitcoinNetworks
        }
        return network.matches(networkConfig)
    }
}

// MARK: - CustomStringConvertible
extension PersistentContactAddress: CustomStringConvertible {
    var description: String {
        return "\(displayName): \(shortAddress)"
    }
}