//
//  ContactAddressModel+Persistence.swift
//  Ark wallet prototype
//
//  The `ContactAddressModel` value type itself now lives in the ArkéUI package
//  as a pure, previewable presentation model. This file holds the app-side
//  bridging: conversion to/from the SwiftData `PersistentContactAddress` store,
//  construction from a `PaymentDestination`, and the `NetworkConfig`-based
//  compatibility helper. Kept here so the model stays free of SwiftData and
//  remains previewable in isolation.
//

import Foundation
import ArkeUI

extension ContactAddressModel {
    /// Initialize from payment destination
    init(from destination: PaymentDestination, contactId: UUID, label: String? = nil, isPrimary: Bool = false) {
        self.init(
            address: destination.address,
            normalizedAddress: destination.address.lowercased(),
            format: destination.format,
            label: label,
            isPrimary: isPrimary,
            contactId: contactId,
            network: destination.network
        )
    }

    /// Initialize from persistent address
    init(from persistentAddress: PersistentContactAddress) {
        self.init(
            id: persistentAddress.id,
            address: persistentAddress.address,
            normalizedAddress: persistentAddress.normalizedAddress,
            format: persistentAddress.format,
            label: persistentAddress.label,
            isPrimary: persistentAddress.isPrimary,
            contactId: persistentAddress.contact?.id ?? UUID(),
            network: persistentAddress.network,
            createdAt: persistentAddress.createdAt,
            updatedAt: persistentAddress.updatedAt
        )
    }

    /// Convert to persistent model
    func toPersistentAddress() -> PersistentContactAddress {
        let persistent = PersistentContactAddress(
            id: self.id,
            address: self.address,
            normalizedAddress: self.normalizedAddress,
            format: self.format,
            label: self.label,
            isPrimary: self.isPrimary,
            network: self.network,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
        return persistent
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
