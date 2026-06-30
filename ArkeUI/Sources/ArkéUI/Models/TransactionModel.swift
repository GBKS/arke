//
//  TransactionModel.swift
//  ArkéUI
//
//  Created by Christoph on 10/23/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark/WalletManager). App-side concerns live in extensions:
//    - `TransactionModel+Persistence.swift`  — PersistentTransaction bridging +
//      the `*IncludingLinked` fee/amount variants (SwiftData fetches).
//    - `TransactionModel+WalletManager.swift` — `liveConfirmations`,
//      `currentExitStatus`, `isExitClaimed`, and the static `walletManager` hook.
//

import SwiftUI

public struct TransactionModel: Identifiable, Hashable, Codable, Sendable {
    public let txid: String  // Primary stable identifier
    public let movementId: Int?  // Server movement ID for grouping
    public let recipientIndex: Int?  // For tracking multiple recipients in same movement
    public let type: TransactionTypeEnum
    public let amount: Int  // Amount in satoshis
    public let date: Date
    public let status: TransactionStatusEnum
    public let address: String?  // Recipient address for sends, nil for receives
    public let notes: String?  // User-added notes for this transaction (max 1000 characters)
    public let fees: Int?  // Offchain transaction fees in satoshis (proportionally allocated for multi-recipient sends)
    public let onchainFeeSat: Int?  // Bitcoin network fees (for onchain operations like boarding)

    // Enhanced metadata fields (Phase 4)
    public let subsystemCategory: String?  // Movement category (e.g., "lightning_send", "offchain_transfer")
    public let subsystemName: String?  // Subsystem name from server (e.g., "bark.arkoor", "bark.offboard")
    public let subsystemKind: String?  // Subsystem kind from server (e.g., "send", "receive", "send_onchain")
    public let paymentMethodType: String?  // Payment method type (e.g., "invoice", "bitcoin", "ark")
    public let paymentHash: String?  // Lightning payment hash identifier
    public let paymentPreimage: String?  // Lightning payment preimage (proof of payment)
    public let fundingTxid: String?  // Round funding transaction ID

    // VTXO ID tracking
    public let inputVtxoIds: [String]  // VTXOs consumed in this transaction
    public let outputVtxoIds: [String]  // VTXOs created by this transaction
    public let exitedVtxoIds: [String]  // VTXOs forced into unilateral exit

    // Onchain transaction fields
    public let confirmationHeight: UInt32?  // Block height where tx was confirmed (onchain only)
    public let confirmationCount: UInt32?  // Number of confirmations (onchain only) - deprecated, use liveConfirmations

    // Transaction linking fields (movement-onchain linking)
    public let parentTxid: String?  // Parent movement txid for linked onchain transactions
    public let childTxids: [String]?  // Linked onchain txids for movement transactions

    // Associated tags and contacts (full objects for UI convenience)
    public let associatedTags: [TagModel]
    public let associatedContacts: [ContactModel]

    // Movement category for enhanced display
    public let category: MovementCategory?

    public init(txid: String, movementId: Int?, recipientIndex: Int? = nil, type: TransactionTypeEnum,
                amount: Int, date: Date, status: TransactionStatusEnum, address: String?, notes: String? = nil,
                associatedTags: [TagModel] = [], associatedContacts: [ContactModel] = [], fees: Int? = nil,
                onchainFeeSat: Int? = nil, subsystemCategory: String? = nil, subsystemName: String? = nil,
                subsystemKind: String? = nil, paymentMethodType: String? = nil,
                paymentHash: String? = nil, paymentPreimage: String? = nil, fundingTxid: String? = nil,
                inputVtxoIds: [String] = [], outputVtxoIds: [String] = [],
                exitedVtxoIds: [String] = [], confirmationHeight: UInt32? = nil, confirmationCount: UInt32? = nil,
                category: MovementCategory? = nil, parentTxid: String? = nil, childTxids: [String]? = nil) {
        self.txid = txid
        self.movementId = movementId
        self.recipientIndex = recipientIndex
        self.type = type
        self.amount = amount
        self.date = date
        self.status = status
        self.address = address
        self.notes = notes
        self.associatedTags = associatedTags
        self.associatedContacts = associatedContacts
        self.fees = fees
        self.onchainFeeSat = onchainFeeSat
        self.subsystemCategory = subsystemCategory
        self.subsystemName = subsystemName
        self.subsystemKind = subsystemKind
        self.paymentMethodType = paymentMethodType
        self.paymentHash = paymentHash
        self.paymentPreimage = paymentPreimage
        self.fundingTxid = fundingTxid
        self.inputVtxoIds = inputVtxoIds
        self.outputVtxoIds = outputVtxoIds
        self.exitedVtxoIds = exitedVtxoIds
        self.confirmationHeight = confirmationHeight
        self.confirmationCount = confirmationCount
        self.category = category
        self.parentTxid = parentTxid
        self.childTxids = childTxids
    }

    // MARK: - Identifiable

    public var id: String { txid }

    // MARK: - UI Formatting Properties

    /// Formatted amount for display (e.g., "+0.00123456 BTC" or "-0.00050000 BTC")
    public var formattedAmount: String {
        return BitcoinFormatter.shared.formatTransactionAmount(amount, transactionType: type, isInternalTransfer: isInternalTransfer)
    }

    /// Net amount including fees (what actually left/arrived in the wallet)
    public var netAmount: Int {
        // For sent and transfer transactions, add fees to get total amount that left the wallet
        if type == .sent || type == .transfer {
            return amount + totalFees  // amount is stored as positive, so we add fees to show total that left
        }
        // For received transactions, amount is what arrived (fees not relevant to user)
        return amount
    }

    /// Formatted net amount for display (includes fees in the calculation)
    /// For internal transfers, shows only the fees paid (as negative amount)
    public var formattedNetAmount: String {
        // For internal transfers, only show the fees (as negative)
        if isInternalTransfer {
            let feesToShow = totalFees
            guard feesToShow > 0 else {
                return BitcoinFormatter.shared.formatAmount(0)
            }
            return BitcoinFormatter.shared.formatTransactionAmount(feesToShow, transactionType: .sent, isInternalTransfer: false)
        }

        return BitcoinFormatter.shared.formatTransactionAmount(netAmount, transactionType: type, isInternalTransfer: isInternalTransfer)
    }

    /// Formatted amount for display in transaction detail views
    /// For internal transfers (onboard, offboard, unilateral exit, send_onchain to own address),
    /// shows the amount that was transferred without the +/- sign
    /// For other transactions, shows the net amount with +/- sign
    public var formattedDisplayAmount: String {
        // For internal transfers, show the transferred amount without sign
        if isInternalTransfer {
            return BitcoinFormatter.shared.formatAmount(abs(amount))
        }

        // For other transactions, show net amount with sign
        return BitcoinFormatter.shared.formatTransactionAmount(amount, transactionType: type, isInternalTransfer: isInternalTransfer)
    }

    /// Formatted amount for accounting display
    public var formattedAmountAccounting: String {
        return BitcoinFormatter.shared.formatAccountingAmount(amount, transactionType: type, isInternalTransfer: isInternalTransfer)
    }

    /// Formatted date for display (relative time)
    public var formattedDate: String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Show "just now" for timestamps within ±5 seconds
        if abs(interval) <= 5 {
            return "just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Absolute formatted date
    public var formattedDateAbsolute: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formatted fee for display (e.g., "250 sats" or "0.00000250 BTC")
    /// Shows offchain fees only (for backwards compatibility)
    public var formattedFee: String? {
        guard let fees = fees, fees > 0 else {
            return nil
        }
        return BitcoinFormatter.shared.formatAmount(fees)
    }

    /// Formatted onchain fee for display
    public var formattedOnchainFee: String? {
        guard let onchainFee = onchainFeeSat, onchainFee > 0 else {
            return nil
        }
        return BitcoinFormatter.shared.formatAmount(onchainFee)
    }

    /// Total fees (offchain + onchain)
    /// For exit transactions, this only returns fees stored directly on the transaction.
    /// Use totalFeesIncludingLinked(modelContext:) to include fees from linked onchain transactions.
    public var totalFees: Int {
        let offchain = fees ?? 0
        let onchain = onchainFeeSat ?? 0
        return offchain + onchain
    }

    /// Formatted total fees for display
    public var formattedTotalFees: String? {
        let total = totalFees
        guard total > 0 else {
            return nil
        }
        return BitcoinFormatter.shared.formatAmount(total)
    }

    /// Formatted total fees as negative amount (like a send transaction)
    public var formattedTotalFeesNegative: String? {
        let total = totalFees
        guard total > 0 else {
            return nil
        }
        return BitcoinFormatter.shared.formatTransactionAmount(total, transactionType: .sent, isInternalTransfer: false)
    }

    /// Check if transaction has fees
    public var hasFees: Bool {
        totalFees > 0
    }

    /// Check if transaction has both onchain and offchain fees
    public var hasBothFeeTypes: Bool {
        let hasOffchain = (fees ?? 0) > 0
        let hasOnchain = (onchainFeeSat ?? 0) > 0
        return hasOffchain && hasOnchain
    }

    /// Convenience accessor for transaction type (already a typed property)
    public var transactionType: TransactionTypeEnum {
        return type
    }

    /// Convenience accessor for transaction status (already a typed property)
    public var transactionStatus: TransactionStatusEnum {
        return status
    }

    /// Check if this transaction is an internal transfer (between user's own balances)
    /// Internal transfers include:
    /// - Boarding, offboarding, refresh, exit operations (internal by nature)
    /// - Onchain sends to own addresses (requires client-side detection)
    /// - Onchain self-transfers detected by BDK (both sent and received non-zero)
    public var isInternalTransfer: Bool {
        guard let category = category else { return false }

        switch category {
        case .boarding, .offboarding, .refresh, .exit:
            return true
        case .onchainTransaction:
            // For pure onchain transactions from BDK, check if it's a self-transfer
            // This is indicated by subsystemKind being "self_transfer"
            return subsystemKind == "self_transfer"
        case .onchainSend:
            return subsystemName == "bark.offboard"
            // For onchain sends, this will be determined by whether a receivingAddress
            // is linked in PersistentTransaction. This property will be true when
            // the TransactionService detects the destination is owned by the user.
            // Note: This check is placeholder - actual detection happens in PersistentTransaction
            //return false
        default:
            return false
        }
    }

    // MARK: - Tag and Contact Helpers

    /// Check if transaction has any tags
    public var hasTags: Bool {
        !associatedTags.isEmpty
    }

    /// Count of tags
    public var tagCount: Int {
        associatedTags.count
    }

    /// Check if transaction has a specific tag
    public func hasTag(_ tag: TagModel) -> Bool {
        associatedTags.contains { $0.id == tag.id }
    }

    /// Check if transaction has a specific tag ID
    public func hasTag(id: UUID) -> Bool {
        associatedTags.contains { $0.id == id }
    }

    /// Check if transaction has any contacts
    public var hasContacts: Bool {
        !associatedContacts.isEmpty
    }

    /// Count of contacts
    public var contactCount: Int {
        associatedContacts.count
    }

    /// Check if transaction has a specific contact
    public func hasContact(_ contact: ContactModel) -> Bool {
        associatedContacts.contains { $0.id == contact.id }
    }

    /// Check if transaction has a specific contact ID
    public func hasContact(id: UUID) -> Bool {
        associatedContacts.contains { $0.id == id }
    }

    // MARK: - Notes Helpers

    /// Check if transaction has notes
    public var hasNotes: Bool {
        guard let notes = notes else { return false }
        return !notes.isEmpty
    }

    /// Get a preview of the notes (first 100 characters)
    public var notesPreview: String? {
        guard let notes = notes, !notes.isEmpty else { return nil }
        if notes.count <= 100 {
            return notes
        }
        let endIndex = notes.index(notes.startIndex, offsetBy: 100)
        return String(notes[..<endIndex]) + String(localized: "symbol_ellipsis")
    }

    // MARK: - Linking Helpers

    /// Check if this transaction has linked onchain transactions
    public var hasLinkedOnchainTransactions: Bool {
        guard let childTxids = childTxids else { return false }
        return !childTxids.isEmpty
    }

    /// Check if this transaction is linked to a parent movement
    public var hasParentMovement: Bool {
        parentTxid != nil
    }

    // MARK: - Exit Status Helpers

    /// Check if this transaction has an associated unilateral exit
    public var hasUnilateralExit: Bool {
        // For exit transactions, the API doesn't populate exitedVtxoIds.
        // Instead, the VTXOs being exited are in inputVtxoIds.
        return subsystemName == "bark.exit" && !inputVtxoIds.isEmpty
    }
}

// MARK: - Sample Data

public extension TransactionModel {
    /// Stable sample values for previews and tests. No database, Bark, or
    /// WalletManager required.
    static let sampleReceive = TransactionModel(
        txid: "sample-receive-0001",
        movementId: 1,
        type: .received,
        amount: 250_000,
        date: Date(timeIntervalSinceNow: -3_600),
        status: .confirmed,
        address: nil,
        notes: "Invoice payment",
        associatedTags: [TagModel.sampleFood],
        associatedContacts: [ContactModel.sampleAlice],
        category: .lightningReceive
    )

    static let sampleSend = TransactionModel(
        txid: "sample-send-0002",
        movementId: 2,
        type: .sent,
        amount: 75_000,
        date: Date(timeIntervalSinceNow: -86_400),
        status: .confirmed,
        address: "ark1qw3kf0n2x8j5h7m9p4q6r8s0t2v4w6x8y0z2a4b6c8d0e2f4g6h8j0k2m4n6p8q",
        associatedTags: [TagModel.sampleSavings],
        associatedContacts: [ContactModel.sampleBob],
        fees: 250,
        category: .offchainTransfer
    )

    static let samplePending = TransactionModel(
        txid: "sample-pending-0003",
        movementId: nil,
        type: .sent,
        amount: 10_000,
        date: Date(),
        status: .pending,
        address: nil,
        category: .lightningSend
    )

    static let samples: [TransactionModel] = [sampleReceive, sampleSend, samplePending]
}

// MARK: - Preview

#Preview("TransactionModel sample data") {
    List(TransactionModel.samples) { tx in
        HStack {
            Image(systemName: tx.type.iconName)
                .foregroundStyle(tx.type.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.category?.displayName ?? tx.type.displayName)
                    .font(.headline)
                Text(tx.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(tx.formattedAmount)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
    }
}
