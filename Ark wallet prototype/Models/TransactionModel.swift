//
//  TransactionModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct TransactionModel: Identifiable, Hashable, Codable {
    let id = UUID()
    let type: TransactionTypeEnum
    let amount: Int // in sats
    let date: Date
    let status: TransactionStatusEnum
    let txid: String?
    let address: String?
    
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
