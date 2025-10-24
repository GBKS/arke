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
    var transactions: [TransactionModel] = []
    var error: String?
    var hasLoadedTransactions: Bool = false
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private var modelContext: ModelContext?
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    /// Set the model context for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        // Load persisted transactions immediately
        Task {
            await loadPersistedTransactions()
        }
    }
    
    /// Refresh transactions with deduplication
    func refreshTransactions() async {
        await taskManager.execute(key: "transactions") {
            await self.performRefreshTransactions()
        }
    }
    
    private func performRefreshTransactions() async {
        do {
            let output = try await wallet.getMovements()
            print("📋 Transactions output: \(output)")
            transactions = await parseTransactions(output)
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
    
    // MARK: - JSON Parsing
    
    private func parseTransactions(_ output: String) async -> [TransactionModel] {
        print("🔍 Parsing transactions from: \(output)")
        
        guard let jsonData = output.data(using: .utf8) else {
            print("❌ Failed to convert output to data")
            return []
        }
        
        do {
            let movements = try JSONDecoder().decode([MovementData].self, from: jsonData)
            var transactions: [TransactionModel] = []
            
            for movement in movements {
                // Parse receives (incoming transactions)
                for receive in movement.receives {
                    let transaction = TransactionModel(
                        type: TransactionTypeEnum.received,
                        amount: receive.amountSat,
                        date: parseDate(movement.createdAt),
                        status: TransactionStatusEnum.confirmed, // Assuming confirmed if it appears in movements
                        txid: receive.id,
                        address: nil as String? // Receiving address not provided in this format
                    )
                    transactions.append(transaction)
                }
                
                // Parse spends (outgoing transactions)
                for spend in movement.spends {
                    // Try to find corresponding recipient address
                    let recipientAddress = movement.recipients.first?.recipient
                    
                    let transaction = TransactionModel(
                        type: TransactionTypeEnum.sent,
                        amount: spend.amountSat,
                        date: parseDate(movement.createdAt),
                        status: TransactionStatusEnum.confirmed, // Assuming confirmed if it appears in movements
                        txid: spend.id,
                        address: recipientAddress
                    )
                    transactions.append(transaction)
                }
            }
            
            // Sort transactions by date (most recent first)
            transactions.sort { $0.date > $1.date }
            
            print("✅ Parsed \(transactions.count) transactions")
            
            // Save to SwiftData and update UI
            await saveTransactionsToSwiftData(transactions)
            
            return transactions
            
        } catch {
            print("❌ Failed to parse transactions JSON: \(error)")
            return []
        }
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
    
    // MARK: - SwiftData Persistence
    
    /// Load persisted transactions from SwiftData immediately for instant UI
    private func loadPersistedTransactions() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading transactions")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<PersistedTransaction>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let persistedTransactions = try modelContext.fetch(descriptor)
            
            // Convert to UI models
            self.transactions = persistedTransactions.map { $0.transactionModel }
            hasLoadedTransactions = true
            
            print("📱 Loaded \(transactions.count) persisted transactions")
        } catch {
            print("❌ Failed to load persisted transactions: \(error)")
        }
    }
    
    /// Save transactions to SwiftData, avoiding duplicates
    private func saveTransactionsToSwiftData(_ newTransactions: [TransactionModel]) async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for saving transactions")
            return
        }
        
        do {
            // Get existing transaction IDs to avoid duplicates
            let existingDescriptor = FetchDescriptor<PersistedTransaction>()
            let existingTransactions = try modelContext.fetch(existingDescriptor)
            let existingIds = Set(existingTransactions.map { $0.id })
            
            // Filter out transactions that already exist
            let transactionsToSave = newTransactions.filter { transaction in
                guard let txid = transaction.txid else { return true } // Include transactions with no txid
                return !existingIds.contains(txid)
            }
            
            // Create and insert new persisted transactions
            for transaction in transactionsToSave {
                let persistedTransaction = PersistedTransaction.from(transaction)
                modelContext.insert(persistedTransaction)
            }
            
            // Save changes
            try modelContext.save()
            
            print("💾 Saved \(transactionsToSave.count) new transactions to SwiftData")
            
        } catch {
            print("❌ Failed to save transactions to SwiftData: \(error)")
        }
    }
    
    // MARK: - State Management
    
    /// Clear error state
    func clearError() {
        error = nil
    }
}
