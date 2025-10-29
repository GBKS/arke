//
//  UTXOModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import Foundation

struct UTXOModel: Codable, Identifiable, Hashable, Sendable {
    let outpoint: String
    let amountSat: Int
    let confirmationHeight: Int?
    
    enum CodingKeys: String, CodingKey {
        case outpoint
        case amountSat = "amount_sat"
        case confirmationHeight = "confirmation_height"
    }
    
    // Identifiable conformance using outpoint as the unique identifier
    var id: String {
        outpoint
    }
    
    // Computed properties for convenience
    var amount: Int {
        amountSat
    }
    
    // Computed properties for convenience
    var amountBTC: Double {
        Double(amountSat) / 100_000_000
    }
    
    // Parse transaction hash and output index from outpoint
    var transactionHash: String {
        String(outpoint.split(separator: ":").first ?? "")
    }
    
    var outputIndex: Int {
        Int(outpoint.split(separator: ":").last ?? "0") ?? 0
    }
    
    // Formatted amount for display
    var formattedAmount: String {
        return BitcoinFormatter.formatAmount(amountSat)
    }
    
    // Short outpoint for display (first 8 chars of hash + index)
    var shortOutpoint: String {
        let hash = transactionHash
        let shortHash = hash.count > 8 ? String(hash.prefix(8)) : hash
        return "\(shortHash):\(outputIndex)"
    }
}

// Array extension for working with multiple UTXOs
extension Array where Element == UTXOModel {
    var totalSat: Int {
        reduce(0) { $0 + $1.amountSat }
    }
    
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
}
