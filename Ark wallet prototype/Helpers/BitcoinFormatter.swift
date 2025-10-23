//
//  BitcoinFormatter.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/22/25.
//

import Foundation

struct BitcoinFormatter {
    
    /// Formats a Bitcoin amount in satoshis for general display
    /// - Parameter amountSats: The amount in satoshis
    /// - Returns: Formatted string with Bitcoin symbol
    static func formatAmount(_ amountSats: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₿"
        formatter.maximumFractionDigits = 0 // Since we're dealing with sats (integers)
        
        let absoluteAmount = abs(amountSats)
        return formatter.string(from: NSNumber(value: absoluteAmount)) ?? "0 ₿"
    }
    
    /// Formats a Bitcoin amount with transaction type context (adds +/- prefixes)
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - transactionType: The type of transaction to determine sign prefix
    /// - Returns: Formatted string with appropriate sign prefix
    static func formatTransactionAmount(_ amountSats: Int, transactionType: TransactionTypeEnum) -> String {
        let baseFormatted = formatAmount(amountSats)
        
        // Add sign prefix for received transactions
        if transactionType == .received {
            return "+\(baseFormatted)"
        }
        
        return baseFormatted
    }
    
    /// Formats a Bitcoin amount in accounting style with consistent symbol placement
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - transactionType: The type of transaction to determine sign
    /// - Returns: Formatted string in accounting style with symbol on the right
    static func formatAccountingAmount(_ amountSats: Int, transactionType: TransactionTypeEnum) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₿"
        formatter.maximumFractionDigits = 0
        
        // For accounting style, use consistent symbol placement on the right
        let absoluteAmount = abs(amountSats)
        let baseFormatted = formatter.string(from: NSNumber(value: absoluteAmount)) ?? "0"
        
        // Remove the currency symbol from the formatted string and add it at the end
        let numberOnly = baseFormatted.replacingOccurrences(of: "₿", with: "").trimmingCharacters(in: .whitespaces)
        
        switch transactionType {
        case .received:
            return "+\(numberOnly) ₿"
        default: // sent or other types
            return "-\(numberOnly) ₿"
        }
    }
}