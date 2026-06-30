//
//  ContactModel.swift
//  ArkéUI
//
//  Created by Assistant on 11/04/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark). App-side bridging (persistence conversion and the
//  NetworkConfig-based `addressesForNetwork(_:)` helper) lives in
//  ContactModel+Persistence.swift.
//

import SwiftUI

public struct ContactModel: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let cachedName: String
    public let notes: String?
    public let avatarData: Data?
    public let createdAt: Date
    public let updatedAt: Date
    public let contactType: ContactType

    // Native contact integration
    public let nativeContactID: String?           // CNContact.identifier for linked native contacts
    public let lastSyncedFromNative: Date?         // When we last imported/refreshed from native contact

    // Transaction statistics (optional for backward compatibility)
    public let transactionCount: Int?
    public let sentAmount: Int?
    public let receivedAmount: Int?

    // Addresses associated with this contact
    public let addresses: [ContactAddressModel]

    public init(id: UUID = UUID(), cachedName: String, notes: String? = nil, avatarData: Data? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), contactType: ContactType = .standard, nativeContactID: String? = nil, lastSyncedFromNative: Date? = nil, transactionCount: Int? = nil, sentAmount: Int? = nil, receivedAmount: Int? = nil, addresses: [ContactAddressModel] = []) {
        self.id = id
        self.cachedName = cachedName
        self.notes = notes
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contactType = contactType
        self.nativeContactID = nativeContactID
        self.lastSyncedFromNative = lastSyncedFromNative
        self.transactionCount = transactionCount
        self.sentAmount = sentAmount
        self.receivedAmount = receivedAmount
        self.addresses = addresses
    }

    // Display name (just the cached name for now)
    public var displayName: String {
        cachedName.isEmpty ? "Unknown Contact" : cachedName
    }

    // Check if this contact is linked to a native contact
    public var isLinkedToNativeContact: Bool {
        nativeContactID != nil
    }

    // Computed properties for formatted display of transaction statistics
    public var formattedTransactionCount: String? {
        guard let count = transactionCount else { return nil }
        return count == 1 ? "1 transaction" : "\(count) transactions"
    }

    public var formattedSentAmount: String? {
        guard let amount = sentAmount, amount > 0 else { return nil }
        return BitcoinFormatter.shared.formatAccountingAmount(amount, transactionType: .sent)
    }

    public var formattedReceivedAmount: String? {
        guard let amount = receivedAmount, amount > 0 else { return nil }
        return BitcoinFormatter.shared.formatAccountingAmount(amount, transactionType: .received)
    }

    // MARK: - Address-related computed properties

    /// Primary address if one exists
    public var primaryAddress: ContactAddressModel? {
        addresses.first { $0.isPrimary }
    }

    /// Bitcoin addresses
    public var bitcoinAddresses: [ContactAddressModel] {
        addresses.filter { $0.format == .bitcoin }
    }

    /// Lightning addresses
    public var lightningAddresses: [ContactAddressModel] {
        addresses.filter { $0.format == .lightning }
    }

    /// Silent payment addresses
    public var silentPaymentAddresses: [ContactAddressModel] {
        addresses.filter { $0.format == .silentPayments }
    }

    /// Ark addresses
    public var arkAddresses: [ContactAddressModel] {
        addresses.filter { $0.format == .ark }
    }

    /// BIP-21 payment URIs
    public var bip21Addresses: [ContactAddressModel] {
        addresses.filter { $0.format == .bip21 }
    }

    /// BIP-353 addresses
    public var bip353Addresses: [ContactAddressModel] {
        addresses.filter { $0.format == .bip353 }
    }

    /// Count of addresses
    public var addressCount: Int {
        addresses.count
    }

    /// Get addresses by format
    public func addresses(for format: AddressFormat) -> [ContactAddressModel] {
        addresses.filter { $0.format == format }
    }

    /// Check if contact has any addresses
    public var hasAddresses: Bool {
        !addresses.isEmpty
    }

    /// Get a summary of address types for display
    public var addressTypesSummary: String {
        let formats = Set(addresses.map { $0.format })
        if formats.isEmpty {
            return "No addresses"
        } else if formats.count == 1 {
            return formats.first?.displayName ?? "Unknown"
        } else {
            return "\(formats.count) address types"
        }
    }

    // Create a new contact model with updated timestamp
    public func withUpdatedTimestamp() -> ContactModel {
        return ContactModel(
            id: self.id,
            cachedName: self.cachedName,
            notes: self.notes,
            avatarData: self.avatarData,
            createdAt: self.createdAt,
            updatedAt: Date(),
            contactType: self.contactType,
            nativeContactID: self.nativeContactID,
            lastSyncedFromNative: self.lastSyncedFromNative,
            transactionCount: self.transactionCount,
            sentAmount: self.sentAmount,
            receivedAmount: self.receivedAmount,
            addresses: self.addresses
        )
    }
}

// MARK: - Sample Data

public extension ContactModel {
    /// Stable sample values for previews and tests. No database or Bark required.
    static let sampleAlice: ContactModel = {
        let id = UUID()
        return ContactModel(
            id: id,
            cachedName: "Alice Nakamoto",
            notes: "Met at the Bitcoin meetup.",
            contactType: .standard,
            transactionCount: 7,
            sentAmount: 125_000,
            receivedAmount: 480_000,
            addresses: [
                ContactAddressModel.sampleArk(contactId: id),
                ContactAddressModel.sampleBitcoin(contactId: id),
                ContactAddressModel.sampleLightning(contactId: id)
            ]
        )
    }()

    static let sampleBob: ContactModel = {
        let id = UUID()
        return ContactModel(
            id: id,
            cachedName: "Bob",
            contactType: .standard,
            transactionCount: 1,
            sentAmount: 0,
            receivedAmount: 21_000,
            addresses: [ContactAddressModel.sampleLightning(contactId: id)]
        )
    }()

    static let sampleFaucet = ContactModel(
        cachedName: "Faucetto Signetto",
        contactType: .faucet
    )

    static let samples: [ContactModel] = [sampleAlice, sampleBob, sampleFaucet]
}

// MARK: - Preview

#Preview("ContactModel sample data") {
    List(ContactModel.samples) { contact in
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.displayName)
                .font(.headline)
            Text(contact.addressTypesSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let received = contact.formattedReceivedAmount {
                Text(received)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
