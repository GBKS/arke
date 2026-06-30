//
//  MovementData.swift
//  Arke
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import ArkeUI

struct MovementData: Codable {
    let id: Int
    let status: String                          // "Pending", "Finished", "Failed", "Cancelled"
    let subsystemKind: String                   // "send" | "receive" | other subsystem-specific
    let subsystemName: String                   // e.g., "bark.arkoor", "bark.lightning"
    let intendedBalanceSat: Int64
    let effectiveBalanceSat: Int64              // Negative for sends, positive for receives
    let offchainFeeSat: Int64                   // Renamed from "fees"
    let sentToAddresses: [AddressObject]        // Address objects with type and value
    let receivedOnAddresses: [AddressObject]    // Address objects with type and value
    let inputVtxoIds: [String]                  // Replaces old "spends" (just IDs now)
    let outputVtxoIds: [String]                 // Replaces old "receives" (just IDs now)
    let exitedVtxoIds: [String]                 // VTXOs forced into unilateral exit (empty array if none)
    let metadataJson: String                    // JSON string, not parsed object
    let createdAt: String                       // ISO 8601 format
    let updatedAt: String
    let completedAt: String?                    // Nil if not yet completed
    
    // New Lightning fields (Bark v0.10.0+)
    let paymentHash: String?                    // Payment hash for Lightning payments
    let lightningInvoice: String?               // Full Lightning invoice (BOLT11)
    let lightningOffer: String?                 // Lightning offer (BOLT12)
    
    enum CodingKeys: String, CodingKey {
        case id, status
        case subsystemKind = "subsystem_kind"
        case subsystemName = "subsystem_name"
        case intendedBalanceSat = "intended_balance_sats"
        case effectiveBalanceSat = "effective_balance_sats"
        case offchainFeeSat = "offchain_fee_sats"
        case sentToAddresses = "sent_to_addresses"
        case receivedOnAddresses = "received_on_addresses"
        case inputVtxoIds = "input_vtxo_ids"
        case outputVtxoIds = "output_vtxo_ids"
        case exitedVtxoIds = "exited_vtxo_ids"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case paymentHash = "payment_hash"
        case lightningInvoice = "lightning_invoice"
        case lightningOffer = "lightning_offer"
    }
    
    // MARK: - Custom Decoding
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode simple properties
        id = try container.decode(Int.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        subsystemKind = try container.decode(String.self, forKey: .subsystemKind)
        subsystemName = try container.decode(String.self, forKey: .subsystemName)
        intendedBalanceSat = try container.decode(Int64.self, forKey: .intendedBalanceSat)
        effectiveBalanceSat = try container.decode(Int64.self, forKey: .effectiveBalanceSat)
        offchainFeeSat = try container.decode(Int64.self, forKey: .offchainFeeSat)
        inputVtxoIds = try container.decode([String].self, forKey: .inputVtxoIds)
        outputVtxoIds = try container.decode([String].self, forKey: .outputVtxoIds)
        exitedVtxoIds = try container.decode([String].self, forKey: .exitedVtxoIds)
        metadataJson = try container.decode(String.self, forKey: .metadataJson)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        
        // Decode new Lightning fields (optional, available in Bark v0.10.0+)
        paymentHash = try container.decodeIfPresent(String.self, forKey: .paymentHash)
        lightningInvoice = try container.decodeIfPresent(String.self, forKey: .lightningInvoice)
        lightningOffer = try container.decodeIfPresent(String.self, forKey: .lightningOffer)
        
        // Decode address arrays (JSON-encoded strings -> AddressObject)
        let sentStrings = try container.decode([String].self, forKey: .sentToAddresses)
        sentToAddresses = Self.decodeAddressObjects(from: sentStrings)
        
        let receivedStrings = try container.decode([String].self, forKey: .receivedOnAddresses)
        receivedOnAddresses = Self.decodeAddressObjects(from: receivedStrings)
    }
    
    /// Decode JSON-encoded address strings into AddressObject array
    private static func decodeAddressObjects(from jsonStrings: [String]) -> [AddressObject] {
        return jsonStrings.compactMap { jsonString in
            guard let data = jsonString.data(using: .utf8) else {
                print("⚠️ Failed to convert address string to data: \(jsonString)")
                return nil
            }
            
            do {
                let addressObject = try JSONDecoder().decode(AddressObject.self, from: data)
                return addressObject
            } catch {
                print("⚠️ Failed to decode address object from '\(jsonString)': \(error)")
                return nil
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Movement category based on subsystem
    var category: MovementCategory {
        MovementCategory.from(subsystemName: subsystemName, subsystemKind: subsystemKind)
    }
    
    /// Parsed metadata (lazily computed)
    var metadata: MovementMetadata? {
        MovementMetadataParser.parse(json: metadataJson, subsystemName: subsystemName)
    }
    
    /// Destination objects from sent addresses (now with explicit type information from server)
    var destinations: [MovementDestination] {
        sentToAddresses.map { addressObject in
            MovementDestination(
                paymentMethod: addressObject.paymentMethod,
                address: addressObject.value
            )
        }
    }
    
    /// Source objects from received addresses (now with explicit type information from server)
    var sources: [MovementDestination] {
        receivedOnAddresses.map { addressObject in
            MovementDestination(
                paymentMethod: addressObject.paymentMethod,
                address: addressObject.value
            )
        }
    }
    
    /// Total onchain fees (if available in metadata)
    var onchainFeeSat: Int? {
        (metadata as? BoardMetadata)?.onchainFeeSat
    }
    
    /// Payment preimage (if Lightning payment - proof of payment)
    /// Note: paymentHash is now a direct field from Bark v0.10.0+, no longer needs to be computed
    var paymentPreimage: String? {
        (metadata as? LightningMetadata)?.paymentPreimage
    }
    
    /// Round funding transaction ID (if round operation)
    var fundingTxid: String? {
        (metadata as? RoundMetadata)?.fundingTxid
    }
    
    /// Whether this movement should be shown in history by default
    var showInHistoryByDefault: Bool {
        category.showInHistoryByDefault
    }
}
