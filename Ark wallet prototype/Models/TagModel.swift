//
//  TagModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/29/25.
//

import SwiftUI
import SwiftData

// MARK: - Persistent Tag Model

@Model
final class PersistentTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var emoji: String
    var createdDate: Date
    var isActive: Bool
    
    // Relationship to tag assignments (not direct to transactions for better control)
    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.tag)
    var tagAssignments: [TransactionTagAssignment] = []
    
    init(id: UUID = UUID(), name: String, colorHex: String, emoji: String, createdDate: Date = Date(), isActive: Bool = true) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.emoji = emoji
        self.createdDate = createdDate
        self.isActive = isActive
    }
    
    // Computed property for SwiftUI Color
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    // Display name with emoji
    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
    
    // Get all transactions that have this tag
    var associatedTransactions: [TransactionModel] {
        tagAssignments.compactMap { $0.transaction }
    }
    
    // Count of associated transactions
    var transactionCount: Int {
        tagAssignments.count
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
}

// MARK: - Transaction Tag Assignment (Junction Table)

@Model
final class TransactionTagAssignment {
    var assignedDate: Date
    
    // Relationships to both tag and transaction
    @Relationship var tag: PersistentTag?
    @Relationship var transaction: TransactionModel?
    
    init(tag: PersistentTag, transaction: TransactionModel, assignedDate: Date = Date()) {
        self.tag = tag
        self.transaction = transaction
        self.assignedDate = assignedDate
    }
    
    // Computed property for easier identification
    var id: String {
        guard let tagId = tag?.id.uuidString,
              let txid = transaction?.txid else {
            return UUID().uuidString
        }
        return "\(tagId)_\(txid)"
    }
}

// MARK: - UI Model (for backward compatibility and UI convenience)

struct TagModel: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let emoji: String
    let createdDate: Date
    let isActive: Bool
    
    init(id: UUID = UUID(), name: String, colorHex: String, emoji: String, createdDate: Date = Date(), isActive: Bool = true) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.emoji = emoji
        self.createdDate = createdDate
        self.isActive = isActive
    }
    
    // Initialize from persistent tag
    init(from persistentTag: PersistentTag) {
        self.id = persistentTag.id
        self.name = persistentTag.name
        self.colorHex = persistentTag.colorHex
        self.emoji = persistentTag.emoji
        self.createdDate = persistentTag.createdDate
        self.isActive = persistentTag.isActive
    }
    
    // Computed property for SwiftUI Color
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    // Display name with emoji
    var displayName: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
    
    // For creating common tags
    static func createDefaultTags() -> [TagModel] {
        return [
            TagModel(name: "Coffee", colorHex: "#8B4513", emoji: "☕"),
            TagModel(name: "Food", colorHex: "#FF6B35", emoji: "🍕"),
            TagModel(name: "Transport", colorHex: "#4A90E2", emoji: "🚗"),
            TagModel(name: "Shopping", colorHex: "#7B68EE", emoji: "🛒"),
            TagModel(name: "Bills", colorHex: "#FF4444", emoji: "📄"),
            TagModel(name: "Income", colorHex: "#32CD32", emoji: "💰"),
            TagModel(name: "Investment", colorHex: "#FFD700", emoji: "📈"),
            TagModel(name: "Gift", colorHex: "#FF69B4", emoji: "🎁")
        ]
    }
    
    // Convert to persistent model
    func toPersistentTag() -> PersistentTag {
        return PersistentTag(
            id: self.id,
            name: self.name,
            colorHex: self.colorHex,
            emoji: self.emoji,
            createdDate: self.createdDate,
            isActive: self.isActive
        )
    }
}
