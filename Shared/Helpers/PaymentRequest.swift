//
//  PaymentRequest.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import Foundation
import ArkeUI

/// Represents a payment request which may contain one or more payment destinations
struct PaymentRequest: Identifiable, Hashable, Codable {
    let id = UUID()
    let destinations: [PaymentDestination]
    let amount: Int? // Amount in satoshis if specified
    let label: String?
    let message: String?
    let originalString: String
    
    enum CodingKeys: String, CodingKey {
        case destinations
        case amount
        case label
        case message
        case originalString
    }
    
    // MARK: - Initializers
    
    init(
        destinations: [PaymentDestination],
        amount: Int? = nil,
        label: String? = nil,
        message: String? = nil,
        originalString: String
    ) {
        self.destinations = destinations
        self.amount = amount
        self.label = label
        self.message = message
        self.originalString = originalString
    }
    
    /// Convenience initializer for single destination
    init(
        destination: PaymentDestination,
        amount: Int? = nil,
        label: String? = nil,
        message: String? = nil
    ) {
        self.destinations = [destination]
        self.amount = amount
        self.label = label
        self.message = message
        self.originalString = destination.address
    }
    
    // MARK: - Computed Properties
    
    /// The primary destination (first one, typically the main payment method)
    var primaryDestination: PaymentDestination? {
        destinations.first
    }
    
    /// Alternative destinations (all except the first)
    var alternativeDestinations: [PaymentDestination] {
        Array(destinations.dropFirst())
    }
    
    /// Check if this request has multiple payment options
    var hasAlternatives: Bool {
        destinations.count > 1
    }
    
    /// The primary address (convenience accessor)
    var primaryAddress: String? {
        primaryDestination?.address
    }
    
    /// The primary format (convenience accessor)
    var primaryFormat: AddressFormat? {
        primaryDestination?.format
    }
    
    /// The primary network (convenience accessor)
    var primaryNetwork: BitcoinNetwork? {
        primaryDestination?.network
    }
    
    // MARK: - Query Methods
    
    /// Get destinations for a specific format
    func destinations(for format: AddressFormat) -> [PaymentDestination] {
        destinations.filter { $0.format == format }
    }
    
    /// Get destinations compatible with a network configuration
    func destinations(for networkConfig: NetworkConfig) -> [PaymentDestination] {
        destinations.filter { $0.isCompatible(with: networkConfig) }
    }
    
    /// Check if this request supports a specific payment format
    func supports(_ format: AddressFormat) -> Bool {
        destinations.contains { $0.format == format }
    }
    
    /// Check if this request has any destinations compatible with a network
    func isCompatible(with networkConfig: NetworkConfig) -> Bool {
        !destinations(for: networkConfig).isEmpty
    }
    
    /// Get the first destination matching a specific format
    func firstDestination(for format: AddressFormat) -> PaymentDestination? {
        destinations.first { $0.format == format }
    }
    
    // MARK: - Filtering
    
    /// Create a new payment request with only destinations matching the network config
    func filtered(for networkConfig: NetworkConfig) -> PaymentRequest? {
        let matchingDestinations = destinations(for: networkConfig)
        guard !matchingDestinations.isEmpty else { return nil }
        
        return PaymentRequest(
            destinations: matchingDestinations,
            amount: amount,
            label: label,
            message: message,
            originalString: originalString
        )
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(destinations)
        hasher.combine(originalString)
    }
    
    static func == (lhs: PaymentRequest, rhs: PaymentRequest) -> Bool {
        return lhs.destinations == rhs.destinations &&
               lhs.amount == rhs.amount &&
               lhs.label == rhs.label &&
               lhs.message == rhs.message &&
               lhs.originalString == rhs.originalString
    }
}

// MARK: - CustomStringConvertible
extension PaymentRequest: CustomStringConvertible {
    var description: String {
        var desc = "PaymentRequest(\(destinations.count) destination(s))"
        if let amount = amount {
            desc += ", \(amount) sats"
        }
        if hasAlternatives {
            desc += ", with alternatives"
        }
        return desc
    }
}
