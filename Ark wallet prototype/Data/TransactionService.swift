//
//  TransactionService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import SwiftData

// MARK: - JSON Parsing Models for Movements

struct MovementData: Codable {
    let id: Int
    let fees: Int
    let spends: [TransactionOutput]
    let receives: [TransactionOutput]
    let recipients: [RecipientData]
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, fees, spends, receives, recipients
        case createdAt = "created_at"
    }
}

struct RecipientData: Codable {
    let recipient: String
    let amountSat: Int
    
    enum CodingKeys: String, CodingKey {
        case recipient
        case amountSat = "amount_sat"
    }
}

struct TransactionOutput: Codable {
    let id: String
    let amountSat: Int
    let policyType: String?
    let userPubkey: String?
    let serverPubkey: String?
    let expiryHeight: Int?
    let exitDelta: Int?
    let chainAnchor: String?
    let exitDepth: Int?
    let arkoorDepth: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case amountSat = "amount_sat"
        case policyType = "policy_type"
        case userPubkey = "user_pubkey"
        case serverPubkey = "server_pubkey"
        case expiryHeight = "expiry_height"
        case exitDelta = "exit_delta"
        case chainAnchor = "chain_anchor"
        case exitDepth = "exit_depth"
        case arkoorDepth = "arkoor_depth"
    }
}

// MARK: - Transaction Service

@MainActor
@Observable
class TransactionService {
    var error: String?
    var isRefreshing: Bool = false
    var hasLoadedTransactions: Bool = false
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private var modelContext: ModelContext?
    
    // MARK: - Computed Properties
    
    /// Get all transactions from SwiftData
    var transactions: [TransactionModel] {
        guard let modelContext = modelContext else {
            return []
        }
        
        do {
            let descriptor = FetchDescriptor<TransactionModel>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let TransactionModels = try modelContext.fetch(descriptor)
            return TransactionModels
        } catch {
            print("❌ Failed to fetch transactions: \(error)")
            return []
        }
    }
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    /// Set the model context for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// Refresh transactions with deduplication using upsert strategy
    func refreshTransactions() async {
        await taskManager.execute(key: "transactions") {
            await self.performRefreshTransactions()
        }
    }
    
    private func performRefreshTransactions() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let output = try await wallet.getMovements()
            print("📋 Transactions output: \(output)")
            await upsertTransactionsFromServerData(output)
            hasLoadedTransactions = true
        } catch {
            print("❌ Failed to get transactions: \(error)")
            self.error = "Failed to get transactions: \(error)"
        }
    }
    
    /// Get raw transactions data from wallet
    func getTransactions() async throws -> String {
        return try await wallet.getMovements()
    }
    
    // MARK: - Upsert Strategy (Insert or Update)
    
    private func upsertTransactionsFromServerData(_ output: String) async {
        guard let modelContext = modelContext else {
            print("🚨 No model context available for upserting transactions")
            return
        }
        
        guard let jsonData = output.data(using: .utf8) else {
            print("❌ Failed to convert output to data")
            return
        }
        
        do {
            let movements = try JSONDecoder().decode([MovementData].self, from: jsonData)
            
            // Get existing transactions to check for updates/new ones
            let existingDescriptor = FetchDescriptor<TransactionModel>()
            let existingTransactions = try modelContext.fetch(existingDescriptor)
            let existingTransactionDict = Dictionary(uniqueKeysWithValues: existingTransactions.map { ($0.txid, $0) })
            
            var upsertedCount = 0
            var updatedCount = 0
            
            for movement in movements {
                let movementTransactions = await parseMovementToTransactions(movement)
                
                for transactionData in movementTransactions {
                    if let existingTransaction = existingTransactionDict[transactionData.txid] {
                        // Update existing transaction if data has changed
                        var hasChanges = false
                        
                        if existingTransaction.amount != transactionData.amount {
                            existingTransaction.amount = transactionData.amount
                            hasChanges = true
                        }
                        
                        if existingTransaction.transactionStatus != transactionData.status {
                            existingTransaction.status = Self.stringValue(for: transactionData.status)
                            hasChanges = true
                        }
                        
                        if existingTransaction.address != transactionData.address {
                            existingTransaction.address = transactionData.address
                            hasChanges = true
                        }
                        
                        if hasChanges {
                            updatedCount += 1
                        }
                    } else {
                        // Insert new transaction
                        let newTransaction = TransactionModel(
                            txid: transactionData.txid,
                            movementId: transactionData.movementId,
                            recipientIndex: transactionData.recipientIndex,
                            type: transactionData.type,
                            amount: transactionData.amount,
                            date: transactionData.date,
                            status: transactionData.status,
                            address: transactionData.address
                        )
                        modelContext.insert(newTransaction)
                        upsertedCount += 1
                    }
                }
            }
            
            // Save changes
            try modelContext.save()
            
            print("💾 Successfully saved \(upsertedCount) new, \(updatedCount) updated transactions")
            
        } catch {
            print("❌ Failed to upsert transactions: \(error)")
            self.error = "Failed to process transactions: \(error)"
        }
    }
    
    // MARK: - Transaction Parsing
    
    private struct TransactionData {
        let txid: String
        let movementId: Int
        let recipientIndex: Int?
        let type: TransactionTypeEnum
        let amount: Int
        let date: Date
        let status: TransactionStatusEnum
        let address: String?
    }
    
    private func parseMovementToTransactions(_ movement: MovementData) async -> [TransactionData] {
        var transactions: [TransactionData] = []
        let parsedDate = parseDate(movement.createdAt)
        
        // Analyze the movement to determine transaction types
        let totalSpent = movement.spends.reduce(0) { $0 + $1.amountSat }
        let totalReceived = movement.receives.reduce(0) { $0 + $1.amountSat }
        let totalSentToRecipients = movement.recipients.reduce(0) { $0 + $1.amountSat }
        
        if !movement.recipients.isEmpty {
            // This is a send transaction (user sent to others)
            // Create separate transactions for each recipient to preserve detail
            for (index, recipient) in movement.recipients.enumerated() {
                let transaction = TransactionData(
                    txid: "movement_\(movement.id)_recipient_\(index)",
                    movementId: movement.id,
                    recipientIndex: index,
                    type: .sent,
                    amount: recipient.amountSat,
                    date: parsedDate,
                    status: .confirmed,
                    address: recipient.recipient
                )
                transactions.append(transaction)
            }
        } else if totalReceived > 0 && totalSpent == 0 {
            // This is a receive transaction (user received from others)
            let transaction = TransactionData(
                txid: "movement_\(movement.id)",
                movementId: movement.id,
                recipientIndex: nil,
                type: .received,
                amount: totalReceived,
                date: parsedDate,
                status: .confirmed,
                address: nil
            )
            transactions.append(transaction)
        } else if totalSpent > 0 && totalReceived > 0 && movement.recipients.isEmpty {
            // This is an internal transaction (VTXO consolidation/splitting)
            // Skip internal transactions as they don't represent economic transfers
            print("🔄 Skipping internal transaction for movement \(movement.id)")
        } else {
            // Fallback for unexpected cases - log and skip
            print("⚠️ Unexpected movement pattern: spends=\(totalSpent), receives=\(totalReceived), recipients=\(totalSentToRecipients)")
        }
        
        return transactions
    }
    
    private func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Fallback to current date if parsing fails
        print("⚠️ Failed to parse date: \(dateString)")
        return Date()
    }
    
    // MARK: - Helper Methods
    
    /// Convert TransactionStatusEnum to String representation
    private static func stringValue(for status: TransactionStatusEnum) -> String {
        switch status {
        case .confirmed: return "confirmed"
        case .pending: return "pending"
        case .failed: return "failed"
        }
    }
    
    /// Convert TransactionTypeEnum to String representation
    private static func stringValue(for type: TransactionTypeEnum) -> String {
        switch type {
        case .sent: return "sent"
        case .received: return "received"
        case .pending: return "pending"
        }
    }
    
    // MARK: - Utility Methods
    
    /// Clear all persisted transactions from SwiftData
    func clearTransactionModels() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for clearing transactions")
            return
        }
        
        do {
            // Fetch all persisted transactions
            let descriptor = FetchDescriptor<TransactionModel>()
            let TransactionModels = try modelContext.fetch(descriptor)
            
            // Delete all transactions
            for transaction in TransactionModels {
                modelContext.delete(transaction)
            }
            
            // Save changes
            try modelContext.save()
            
            // Reset loaded state
            hasLoadedTransactions = false
            
            print("🗑️ Cleared \(TransactionModels.count) persisted transactions")
            
        } catch {
            print("❌ Failed to clear persisted transactions: \(error)")
        }
    }
    
    // MARK: - State Management
    
    /// Clear error state
    func clearError() {
        error = nil
    }
}
