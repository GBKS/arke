//
//  ContactAddressModel.swift
//  ArkéUI
//
//  Created by Assistant on 11/05/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark). App-side bridging (PaymentDestination/persistence
//  conversion and the NetworkConfig-based `isCompatibleWith(_:)` helper) lives
//  in ContactAddressModel+Persistence.swift.
//

import Foundation

public struct ContactAddressModel: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let address: String
    public let normalizedAddress: String
    public let format: AddressFormat
    public let label: String?
    public let isPrimary: Bool
    public let contactId: UUID
    public let createdAt: Date
    public let updatedAt: Date

    // Network info (derived from address validation)
    public let network: BitcoinNetwork?

    // MARK: - Initializers

    public init(id: UUID = UUID(), address: String, normalizedAddress: String, format: AddressFormat, label: String? = nil, isPrimary: Bool = false, contactId: UUID, network: BitcoinNetwork? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.address = address
        self.normalizedAddress = normalizedAddress
        self.format = format
        self.label = label
        self.isPrimary = isPrimary
        self.contactId = contactId
        self.network = network
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// Display name for the address (label if available, otherwise format name)
    public var displayName: String {
        if let label = label, !label.isEmpty {
            return label
        }
        return format.displayName
    }

    /// Full display name including network info
    public var fullDisplayName: String {
        if let network = network {
            return "\(displayName) (\(network.displayName))"
        }
        return displayName
    }

    /// Check if this address supports Bitcoin networks
    public var supportsBitcoinNetworks: Bool {
        format.supportsBitcoinNetworks
    }

    /// Shortened address for display (first 8 + String(localized: "symbol_ellipsis") + last 8 characters)
    public var shortAddress: String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }

    // MARK: - Methods

    /// Create a new address model with updated timestamp
    public func withUpdatedTimestamp() -> ContactAddressModel {
        return ContactAddressModel(
            id: self.id,
            address: self.address,
            normalizedAddress: self.normalizedAddress,
            format: self.format,
            label: self.label,
            isPrimary: self.isPrimary,
            contactId: self.contactId,
            network: self.network,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// Create a new address model with updated primary status
    public func withPrimaryStatus(_ isPrimary: Bool) -> ContactAddressModel {
        return ContactAddressModel(
            id: self.id,
            address: self.address,
            normalizedAddress: self.normalizedAddress,
            format: self.format,
            label: self.label,
            isPrimary: isPrimary,
            contactId: self.contactId,
            network: self.network,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}

// MARK: - CustomStringConvertible
extension ContactAddressModel: CustomStringConvertible {
    public var description: String {
        return "\(displayName): \(shortAddress)"
    }
}

// MARK: - Sample Data

public extension ContactAddressModel {
    /// Stable sample values for previews and tests. No database or Bark required.
    static func sampleArk(contactId: UUID = UUID()) -> ContactAddressModel {
        ContactAddressModel(
            address: "ark1qw3kf0n2x8j5h7m9p4q6r8s0t2v4w6x8y0z2a4b6c8d0e2f4g6h8j0k2m4n6p8q",
            normalizedAddress: "ark1qw3kf0n2x8j5h7m9p4q6r8s0t2v4w6x8y0z2a4b6c8d0e2f4g6h8j0k2m4n6p8q",
            format: .ark,
            label: "Spending",
            isPrimary: true,
            contactId: contactId,
            network: .signet
        )
    }

    static func sampleBitcoin(contactId: UUID = UUID()) -> ContactAddressModel {
        ContactAddressModel(
            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            normalizedAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            format: .bitcoin,
            label: "Savings",
            contactId: contactId,
            network: .mainnet
        )
    }

    static func sampleLightning(contactId: UUID = UUID()) -> ContactAddressModel {
        ContactAddressModel(
            address: "satoshi@example.com",
            normalizedAddress: "satoshi@example.com",
            format: .lightning,
            contactId: contactId
        )
    }
}
