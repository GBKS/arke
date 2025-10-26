//
//  TransactionModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct TransactionModel: Identifiable, Hashable, Codable {
    let id: UUID
    let type: TransactionTypeEnum
    let amount: Int // in sats
    let date: Date
    let status: TransactionStatusEnum
    let txid: String?
    let address: String?
    
    init(type: TransactionTypeEnum, amount: Int, date: Date, status: TransactionStatusEnum, txid: String? = nil, address: String? = nil) {
        self.id = UUID()
        self.type = type
        self.amount = amount
        self.date = date
        self.status = status
        self.txid = txid
        self.address = address
    }
    
    var formattedAmount: String {
        return BitcoinFormatter.formatTransactionAmount(amount, transactionType: type)
    }
    
    var formattedAmountAccounting: String {
        return BitcoinFormatter.formatAccountingAmount(amount, transactionType: type)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
