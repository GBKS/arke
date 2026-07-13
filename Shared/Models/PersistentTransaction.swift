//
//  PersistentTransaction.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/23/25.
//

import Foundation
import SwiftData
import ArkeUI

@Model
final class PersistentTransaction {
    // Remove @Attribute(.unique) for CloudKit compatibility
    var txid: String = ""  // Primary stable identifier - default for CloudKit
    var movementId: Int?  // Server movement ID for grouping (optional for migration compatibility)
    var recipientIndex: Int?  // For tracking multiple recipients in same movement
    var type: String = "received"  // "sent" or "received" - default for CloudKit
    var amount: Int = 0  // Amount in satoshis - default for CloudKit
    var date: Date = Date()  // Default for CloudKit
    var status: String = "pending"  // "confirmed", "pending", etc. - default for CloudKit
    var address: String?  // Recipient address for sends, nil for receives
    var notes: String?  // User-added notes for this transaction (max 1000 characters)
    var fees: Int?  // Transaction fees in satoshis (proportionally allocated for multi-recipient sends)
    
    // ✅ Enhanced metadata fields (Phase 4)
    var subsystemCategory: String?  // Movement category (e.g., "lightning_send", "offchain_transfer")
    var subsystemName: String?  // Subsystem name from server (e.g., "bark.arkoor", "bark.offboard")
    var subsystemKind: String?  // Subsystem kind from server (e.g., "send", "receive", "send_onchain")
    var paymentMethodType: String?  // Payment method type (e.g., "invoice", "bitcoin", "ark")
    var paymentHash: String?  // Lightning payment hash identifier
    var paymentPreimage: String?  // Lightning payment preimage (proof of payment)
    var onchainFeeSat: Int?  // Bitcoin network fees (separate from offchain fees)
    var fundingTxid: String?  // Round funding transaction ID
    
    // VTXO ID tracking (stored as JSON array strings for CloudKit compatibility)
    var inputVtxoIdsJson: String?  // VTXOs consumed in this transaction (JSON array)
    var outputVtxoIdsJson: String?  // VTXOs created by this transaction (JSON array)
    var exitedVtxoIdsJson: String?  // VTXOs forced into unilateral exit (JSON array)
    
    // Unified transaction system fields (Phase 1: Onchain Integration)
    var sourceType: String = "ark"  // "ark" or "onchain" - discriminator for transaction source
    var confirmationHeight: UInt32?  // Block height where onchain transaction was confirmed
    var confirmationCount: UInt32?  // Number of confirmations for onchain transactions
    var onchainReceived: UInt64?  // Exact received amount for onchain transactions
    var onchainSent: UInt64?  // Exact sent amount for onchain transactions
    
    // Tag assignments relationship - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.transaction)
    var tagAssignments: [TransactionTagAssignment]? = []
    
    // Contact assignments relationship - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \TransactionContactAssignment.transaction)
    var contactAssignments: [TransactionContactAssignment]? = []
    
    // Address relationship - MUST be optional for CloudKit (Phase 3)
    /// The address that received this transaction (if applicable)
    @Relationship(deleteRule: .nullify)
    var receivingAddress: PersistentAddress?
    
    // Transaction linking fields (for movement-onchain linking)
    /// References the parent movement txid for onchain transactions (e.g., "movement_123")
    var parentTxid: String?
    
    /// Array of linked onchain txids for movements (e.g., ["onchain_abc...", "onchain_def..."])
    var childTxids: [String]?
    
    init(txid: String, movementId: Int?, recipientIndex: Int? = nil, type: TransactionTypeEnum, 
         amount: Int, date: Date, status: TransactionStatusEnum, address: String?, notes: String? = nil, fees: Int? = nil,
         subsystemCategory: String? = nil, subsystemName: String? = nil, subsystemKind: String? = nil,
         paymentMethodType: String? = nil, paymentHash: String? = nil, paymentPreimage: String? = nil,
         onchainFeeSat: Int? = nil, fundingTxid: String? = nil,
         inputVtxoIds: [String]? = nil, outputVtxoIds: [String]? = nil, exitedVtxoIds: [String]? = nil) {
        self.txid = txid
        self.movementId = movementId
        self.recipientIndex = recipientIndex
        self.type = Self.stringValue(for: type)
        self.amount = amount
        self.date = date
        self.status = Self.stringValue(for: status)
        self.address = address
        self.notes = notes
        self.fees = fees
        self.subsystemCategory = subsystemCategory
        self.subsystemName = subsystemName
        self.subsystemKind = subsystemKind
        self.paymentMethodType = paymentMethodType
        self.paymentHash = paymentHash
        self.paymentPreimage = paymentPreimage
        self.onchainFeeSat = onchainFeeSat
        self.fundingTxid = fundingTxid
        self.inputVtxoIdsJson = Self.encodeVtxoIds(inputVtxoIds)
        self.outputVtxoIdsJson = Self.encodeVtxoIds(outputVtxoIds)
        self.exitedVtxoIdsJson = Self.encodeVtxoIds(exitedVtxoIds)
    }
    
    // MARK: - Computed Properties
    
    /// SwiftUI identifier using txid instead of persistentModelID
    var id: String { txid }
    
    /// Decoded input VTXO IDs
    var inputVtxoIds: [String] {
        Self.decodeVtxoIds(from: inputVtxoIdsJson) ?? []
    }
    
    /// Decoded output VTXO IDs
    var outputVtxoIds: [String] {
        Self.decodeVtxoIds(from: outputVtxoIdsJson) ?? []
    }
    
    /// Decoded exited VTXO IDs
    var exitedVtxoIds: [String] {
        Self.decodeVtxoIds(from: exitedVtxoIdsJson) ?? []
    }
    
    /// Get the transaction type as enum
    var transactionType: TransactionTypeEnum {
        return Self.transactionType(from: type)
    }
    
    /// Get the transaction status as enum
    var transactionStatus: TransactionStatusEnum {
        return Self.transactionStatus(from: status)
    }
    
    // MARK: - Rich Metadata Computed Properties
    
    /// Get the movement category as enum
    var category: MovementCategory? {
        guard let subsystemCategory = subsystemCategory else { return nil }
        return MovementCategory(rawValue: subsystemCategory)
    }
    
    /// Get the payment method as enum (with type detection fallback)
    var paymentMethod: PaymentMethod? {
        guard let address = address else { return nil }
        // Use stored type if available, otherwise detect from address
        if let _ = paymentMethodType {
            return PaymentMethod.detect(from: address)
        }
        return PaymentMethod.detect(from: address)
    }
    
    /// Total fees (offchain + onchain)
    var totalFees: Int? {
        let offchain = fees ?? 0
        let onchain = onchainFeeSat ?? 0
        let total = offchain + onchain
        return total > 0 ? total : nil
    }
    
    /// Whether this transaction involved Lightning Network
    var isLightning: Bool {
        category?.isLightning ?? false
    }
    
    /// Whether this transaction involved onchain Bitcoin
    var isOnchain: Bool {
        category?.isOnchain ?? false
    }
    
    /// Whether this is an Ark offchain transfer
    var isOffchain: Bool {
        category?.isOffchain ?? false
    }
    
    /// Whether this is a maintenance operation
    var isMaintenance: Bool {
        category?.isMaintenance ?? false
    }
    
    /// Short payment method display name
    var paymentMethodDisplayName: String? {
        paymentMethod?.shortDisplayType
    }
    
    /// Category display name
    var categoryDisplayName: String? {
        category?.shortDisplayName
    }
    
    // MARK: - Tag Convenience Methods
    
    /// Get all tags associated with this transaction
    var associatedTags: [PersistentTag] {
        (tagAssignments ?? []).compactMap { $0.tag }
    }
    
    /// Get count of tags on this transaction
    var tagCount: Int {
        tagAssignments?.count ?? 0
    }
    
    /// Check if transaction has a specific tag
    func hasTag(_ tag: PersistentTag) -> Bool {
        (tagAssignments ?? []).contains { $0.tag?.id == tag.id }
    }
    
    /// Check if transaction has any tags
    var hasTags: Bool {
        !(tagAssignments ?? []).isEmpty
    }
    
    // MARK: - Contact Convenience Methods
    
    /// Get all contacts associated with this transaction
    var associatedContacts: [PersistentContact] {
        (contactAssignments ?? []).compactMap { $0.contact }
    }
    
    /// Get count of contacts on this transaction
    var contactCount: Int {
        contactAssignments?.count ?? 0
    }
    
    /// Check if transaction has a specific contact
    func hasContact(_ contact: PersistentContact) -> Bool {
        (contactAssignments ?? []).contains { $0.contact?.id == contact.id }
    }
    
    /// Check if transaction has any contacts
    var hasContacts: Bool {
        !(contactAssignments ?? []).isEmpty
    }
    
    // MARK: - Notes Convenience Methods
    
    /// Check if transaction has notes
    var hasNotes: Bool {
        guard let notes = notes else { return false }
        return !notes.isEmpty
    }
    
    /// Get a preview of the notes (first 100 characters)
    var notesPreview: String? {
        guard let notes = notes, !notes.isEmpty else { return nil }
        if notes.count <= 100 {
            return notes
        }
        let endIndex = notes.index(notes.startIndex, offsetBy: 100)
        return String(notes[..<endIndex]) + String(localized: "symbol_ellipsis")
    }
    
    // MARK: - Internal Transfer Detection
    
    /// Check if this transaction is an internal transfer (to our own address)
    /// Includes:
    /// - Boarding/offboarding/refresh/exit operations (internal by nature)
    /// - Onchain sends to our own Bitcoin addresses (detected via receivingAddress link)
    var isInternalTransfer: Bool {
        // Check if it's an inherently internal category
        if let category = category {
            switch category {
            case .boarding, .offboarding, .refresh, .exit:
                return true
            case .onchainSend:
                // For onchain sends, check if sent to our own address
                return receivingAddress != nil
            default:
                break
            }
        }
        
        // Legacy fallback: for sent transactions with receiving address linked
        if type == "sent" && receivingAddress != nil {
            return true
        }
        
        return false
    }
    
    /// Get effective type (considering internal transfers)
    /// Returns "internal_transfer" if this is a send to our own address,
    /// otherwise returns the normal type
    var effectiveType: String {
        if isInternalTransfer {
            return "internal_transfer"
        }
        return type
    }
    
    /// Display name for effective type
    var effectiveTypeDisplayName: String {
        switch effectiveType {
        case "internal_transfer":
            return "Internal Transfer"
        case "sent":
            return "Sent"
        case "received":
            return "Received"
        case "transfer":
            return "Transfer"
        case "pending":
            return "Pending"
        default:
            return type.capitalized
        }
    }
    
    /// Icon for effective type (SF Symbol name)
    var effectiveTypeIcon: String {
        switch effectiveType {
        case "internal_transfer":
            return "arrow.left.arrow.right"
        case "sent":
            return "arrow.up"
        case "received":
            return "arrow.down"
        default:
            return "arrow.left.arrow.right.circle"
        }
    }
    
    // MARK: - Helper methods for enum conversion
    
    private static func stringValue(for type: TransactionTypeEnum) -> String {
        switch type {
        case .sent: return "sent"
        case .received: return "received"
        case .transfer: return "transfer"
        case .pending: return "pending"
        }
    }
    
    private static func stringValue(for status: TransactionStatusEnum) -> String {
        switch status {
        case .confirmed: return "confirmed"
        case .pending: return "pending"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }
    
    private static func transactionType(from string: String) -> TransactionTypeEnum {
        switch string {
        case "sent": return .sent
        case "received": return .received
        case "transfer": return .transfer
        case "pending": return .pending
        default: return .sent // fallback
        }
    }
    
    private static func transactionStatus(from string: String) -> TransactionStatusEnum {
        switch string {
        case "confirmed": return .confirmed
        case "pending": return .pending
        case "failed": return .failed
        case "cancelled": return .cancelled
        default: return .confirmed // fallback
        }
    }
    
    // MARK: - VTXO ID Encoding/Decoding Helpers
    
    /// Encode array of VTXO IDs to JSON string for storage
    static func encodeVtxoIds(_ ids: [String]?) -> String? {
        guard let ids = ids, !ids.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
    
    /// Decode VTXO IDs from JSON string
    private static func decodeVtxoIds(from json: String?) -> [String]? {
        guard let json = json,
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return ids
    }
}

// MARK: - Transaction Linking Helpers

extension PersistentTransaction {
    /// Fetch linked onchain transactions for this movement
    /// Returns empty array if no linked transactions exist
    func fetchLinkedOnchainTransactions(context: ModelContext) -> [PersistentTransaction] {
        guard let childTxids = childTxids, !childTxids.isEmpty else {
            return []
        }
        
        var linkedTransactions: [PersistentTransaction] = []
        for txid in childTxids {
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == txid }
            )
            if let transaction = try? context.fetch(descriptor).first {
                linkedTransactions.append(transaction)
            }
        }
        return linkedTransactions
    }
    
    /// Check if any linked onchain transaction is confirmed
    func hasConfirmedOnchain(context: ModelContext) -> Bool {
        let linkedTransactions = fetchLinkedOnchainTransactions(context: context)
        return linkedTransactions.contains { $0.confirmationHeight != nil }
    }
    
    /// Get confirmation details from the first confirmed linked onchain transaction
    /// Returns tuple of (block height, timestamp) or nil if no confirmed transactions
    func onchainConfirmation(context: ModelContext) -> (height: UInt32, timestamp: Date)? {
        let linkedTransactions = fetchLinkedOnchainTransactions(context: context)
        for transaction in linkedTransactions {
            if let height = transaction.confirmationHeight {
                return (height, transaction.date)
            }
        }
        return nil
    }
}


