//
//  PersistentTag.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/4/25.
//

import SwiftUI
import SwiftData
import ArkeUI

@Model
final class PersistentTag {
    // Remove @Attribute(.unique) for CloudKit compatibility
    var id: UUID = UUID()  // Default for CloudKit
    var name: String = ""  // Default for CloudKit
    var colorHex: String = "#007AFF"  // Default blue color for CloudKit
    var emoji: String = "🏷️"  // Default emoji for CloudKit
    var createdDate: Date = Date()  // Default for CloudKit
    var isSystemTag: Bool = false  // Default for CloudKit
    
    // Relationship to tag assignments - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.tag)
    var tagAssignments: [TransactionTagAssignment]? = []
    
    // Relationship to pending tag assignments - MUST be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \PendingTagAssignment.tag)
    var pendingTagAssignments: [PendingTagAssignment]? = []
    
    init(id: UUID = UUID(), name: String, colorHex: String, emoji: String, createdDate: Date = Date(), isSystemTag: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.emoji = emoji
        self.createdDate = createdDate
        self.isSystemTag = isSystemTag
    }
    
    // Computed property for SwiftUI Color
    var color: Color {
        Color(hex: colorHex) ?? .Arke.blue
    }
    
    // Display name with emoji
    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
    
    // Get all transactions that have this tag
    var associatedTransactions: [PersistentTransaction] {
        (tagAssignments ?? []).compactMap { $0.transaction }
    }
    
    // Count of associated transactions
    var transactionCount: Int {
        tagAssignments?.count ?? 0
    }
    
    // Total amount (net: received - sent)
    var totalTransactionAmount: Int {
        let sent = sentAmount
        let received = receivedAmount
        return received - sent
    }
    
    // Sum of sent transaction amounts
    var sentAmount: Int {
        associatedTransactions
            .filter { $0.type == "sent" }
            .reduce(0) { $0 + $1.amount }
    }
    
    // Sum of received transaction amounts
    var receivedAmount: Int {
        associatedTransactions
            .filter { $0.type == "received" }
            .reduce(0) { $0 + $1.amount }
    }
    
    // Sum of offchain fees (from fees field)
    var offchainFees: Int {
        associatedTransactions
            .reduce(0) { $0 + ($1.fees ?? 0) }
    }
    
    // Sum of onchain fees (from onchainFeeSat field)
    var onchainFees: Int {
        associatedTransactions
            .reduce(0) { $0 + ($1.onchainFeeSat ?? 0) }
    }
    
    // Total fees (offchain + onchain)
    var totalFees: Int {
        offchainFees + onchainFees
    }
}
