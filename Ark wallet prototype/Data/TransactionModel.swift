//
//  TransactionModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/23/25.
//

import Foundation
import SwiftData

@Model
final class TransactionModel: @unchecked Sendable {
    @Attribute(.unique) var txid: String  // Primary stable identifier
    var movementId: Int?  // Server movement ID for grouping (optional for migration compatibility)
    var recipientIndex: Int?  // For tracking multiple recipients in same movement
    var type: String  // "sent" or "received"
    var amount: Int  // Amount in satoshis
    var date: Date
    var status: String  // "confirmed", "pending", etc.
    var address: String?  // Recipient address for sends, nil for receives
    
    // Future: Tags relationship (ready for when we implement tagging)
    // @Relationship(deleteRule: .cascade) var tags: [PersistentTag] = []
    
    init(txid: String, movementId: Int?, recipientIndex: Int? = nil, type: TransactionTypeEnum, 
         amount: Int, date: Date, status: TransactionStatusEnum, address: String?) {
        self.txid = txid
        self.movementId = movementId
        self.recipientIndex = recipientIndex
        self.type = Self.stringValue(for: type)
        self.amount = amount
        self.date = date
        self.status = Self.stringValue(for: status)
        self.address = address
    }
    
    // MARK: - Computed Properties
    
    /// SwiftUI identifier using txid instead of persistentModelID
    var id: String { txid }
    
    /// Get the transaction type as enum
    var transactionType: TransactionTypeEnum {
        return Self.transactionType(from: type)
    }
    
    /// Get the transaction status as enum
    var transactionStatus: TransactionStatusEnum {
        return Self.transactionStatus(from: status)
    }
    
    /// Formatted amount for display
    var formattedAmount: String {
        return BitcoinFormatter.formatTransactionAmount(amount, transactionType: transactionType)
    }
    
    /// Formatted amount for accounting display
    var formattedAmountAccounting: String {
        return BitcoinFormatter.formatAccountingAmount(amount, transactionType: transactionType)
    }
    
    /// Formatted date for display
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Legacy Compatibility
    
    /// Convert to UI model for backward compatibility (to be deprecated)
    /*
    @available(*, deprecated, message: "Use TransactionModel directly instead")
    var transactionModel: TransactionModel {
        return TransactionModel(
            type: transactionType,
            amount: amount,
            date: date,
            status: transactionStatus,
            txid: txid,
            address: address
        )
    }
    */
    
    // MARK: - Helper methods for enum conversion
    
    private static func stringValue(for type: TransactionTypeEnum) -> String {
        switch type {
        case .sent: return "sent"
        case .received: return "received"
        case .pending: return "pending" // This seems like a design issue - pending should be status, not type
        }
    }
    
    private static func stringValue(for status: TransactionStatusEnum) -> String {
        switch status {
        case .confirmed: return "confirmed"
        case .pending: return "pending"
        case .failed: return "failed"
        }
    }
    
    private static func transactionType(from string: String) -> TransactionTypeEnum {
        switch string {
        case "sent": return .sent
        case "received": return .received
        case "pending": return .pending // This seems like a design issue - pending should be status, not type
        default: return .sent // fallback
        }
    }
    
    private static func transactionStatus(from string: String) -> TransactionStatusEnum {
        switch string {
        case "confirmed": return .confirmed
        case "pending": return .pending
        case "failed": return .failed
        default: return .confirmed // fallback
        }
    }
}


