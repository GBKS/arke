//
//  PersistedTransaction.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/23/25.
//

import Foundation
import SwiftData

@Model
class PersistedTransaction {
    var id: String
    var type: String  // "sent" or "received"
    var amount: Int
    var date: Date
    var status: String  // "confirmed", "pending", etc.
    var address: String?
    
    init(id: String, type: TransactionTypeEnum, amount: Int, date: Date, status: TransactionStatusEnum, address: String?) {
        self.id = id
        self.type = Self.stringValue(for: type)
        self.amount = amount
        self.date = date
        self.status = Self.stringValue(for: status)
        self.address = address
    }
    
    /// Convert to UI model for compatibility with existing code
    var transactionModel: TransactionModel {
        return TransactionModel(
            type: Self.transactionType(from: type),
            amount: amount,
            date: date,
            status: Self.transactionStatus(from: status),
            txid: id,
            address: address
        )
    }
    
    /// Create from existing TransactionModel
    static func from(_ transaction: TransactionModel) -> PersistedTransaction {
        return PersistedTransaction(
            id: transaction.txid ?? UUID().uuidString,
            type: transaction.type,
            amount: transaction.amount,
            date: transaction.date,
            status: transaction.status,
            address: transaction.address
        )
    }
    
    // MARK: - Helper methods for enum conversion
    
    private static func stringValue(for type: TransactionTypeEnum) -> String {
        switch type {
        case .sent: return "sent"
        case .received: return "received"
        case .pending: return "pending"
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
        case "pending": return .pending
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
