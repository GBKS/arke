//
//  ReceiveQRContentHelper.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import Foundation

struct ReceiveQRContentHelper {
    static func getCurrentQRContent(
        selectedBalance: ReceiveView.BalanceType,
        amount: String,
        note: String,
        arkAddress: String,
        onchainAddress: String
    ) -> (content: String, title: String)? {
        let amountValue = amount.isEmpty ? nil : amount
        let noteValue = note.isEmpty ? nil : note
        
        switch selectedBalance {
        case .payments:
            guard !arkAddress.isEmpty else { return nil }
            return (
                content: BIP21URIHelper.createBIP21URI(
                    arkAddress: arkAddress,
                    amount: amountValue,
                    label: nil,
                    message: noteValue ?? nil
                ),
                title: "Receive to Payments"
            )
            
        case .savings:
            guard !onchainAddress.isEmpty else { return nil }
            return (
                content: BIP21URIHelper.createBIP21URI(
                    onchainAddress: onchainAddress,
                    amount: amountValue,
                    label: nil,
                    message: noteValue ?? nil
                ),
                title: "Receive to Savings"
            )
            
        case .paymentsAndSavings:
            let combinedURI = BIP21URIHelper.createBIP21URI(
                arkAddress: arkAddress,
                onchainAddress: onchainAddress
            )
            return (
                content: combinedURI,
                title: "Receive to Payments or Savings"
            )
            
        case .lightning:
            return nil // Lightning not supported yet
        }
    }
    
    static func getShareContent(
        selectedBalance: ReceiveView.BalanceType,
        amount: String,
        note: String,
        arkAddress: String,
        onchainAddress: String
    ) -> String? {
        switch selectedBalance {
        case .payments:
            guard !arkAddress.isEmpty else { return nil }
            return BIP21URIHelper.createBIP21URI(
                arkAddress: arkAddress,
                amount: amount.isEmpty ? nil : amount,
                label: "Ark Payments Address",
                message: note.isEmpty ? "For instant, private payments" : note
            )
            
        case .savings:
            guard !onchainAddress.isEmpty else { return nil }
            return BIP21URIHelper.createBIP21URI(
                onchainAddress: onchainAddress,
                amount: amount.isEmpty ? nil : amount,
                label: "Bitcoin Savings Address",
                message: note.isEmpty ? "For funding your savings" : note
            )
            
        case .paymentsAndSavings:
            return BIP21URIHelper.createBIP21URI(
                arkAddress: arkAddress,
                onchainAddress: onchainAddress
            )
            
        case .lightning:
            return nil
        }
    }
}
