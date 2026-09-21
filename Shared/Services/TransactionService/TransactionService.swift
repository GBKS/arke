//
//  TransactionService.swift
//  Arke
//
//  Core transaction service handling movement data from the wallet API.
//  Orchestrates transaction refresh, processing, and persistence.
//

import Foundation
import SwiftData
import ArkeUI
import OSLog

// MARK: - Supporting Models

// MARK: Address Object Model

/// Address object as returned by the API (JSON-encoded within the address arrays)
struct AddressObject: Codable {
    let type: String   // "ark", "bitcoin", "lightning", etc.
    let value: String  // The actual address/invoice/identifier
    
    /// Convert to PaymentMethod enum
    var paymentMethod: PaymentMethod {
        // Use the explicit type from the server instead of heuristic detection
        switch type.lowercased() {
        case "ark":
            return .ark(address: value)
        case "bitcoin":
            return .bitcoin(address: value)
        case "lightning":
            // Could be invoice, offer, or lightning address - use detection for subcategory
            if value.hasPrefix("lnbc") || value.hasPrefix("lntb") || value.hasPrefix("lnbcrt") {
                return .invoice(value: value)
            } else if value.hasPrefix("lno1") {
                return .offer(value: value)
            } else if value.contains("@") {
                return .lightningAddress(value: value)
            } else {
                return .unknown(value: value)
            }
        default:
            // Unknown type - fall back to heuristic detection
            return PaymentMethod.detect(from: value)
        }
    }
}

// MARK: Collection Async Utilities

extension Collection {
    /// Async version of flatMap for collections
    /// - Parameter transform: An async closure that transforms each element into an array
    /// - Returns: A flattened array of all transformed elements
    func asyncFlatMap<T>(_ transform: (Element) async throws -> [T]) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            let transformed = try await transform(element)
            result.append(contentsOf: transformed)
        }
        return result
    }
}

// MARK: - Transaction Service

@MainActor
@Observable
class TransactionService {
    /// Logger for transaction service operations
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "TransactionService")
    
    var error: String?
    var isRefreshing: Bool = false
    var hasLoadedTransactions: Bool = false
    
    private let taskManager: TaskDeduplicationManager
    
    // Internal use by extensions only.
    var modelContext: ModelContext?
    var addressService: AddressService?
    var linkingService: TransactionLinkingService?
    let wallet: BarkWalletProtocol
    
    // MARK: - Properties
    
    /// Get all transactions from SwiftData as UI models
    var transactions: [TransactionModel] {
        guard let modelContext = modelContext else {
            return []
        }
        
        do {
            let descriptor = FetchDescriptor<PersistentTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let persistentTransactions = try modelContext.fetch(descriptor)
            return persistentTransactions.map { TransactionModel(from: $0) }
        } catch {
            Self.logger.error("Failed to fetch transactions: \(error.localizedDescription)")
            return []
        }
    }
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    // MARK: - Configuration
    
    /// Set the model context for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// Set the address service for address-transaction linking
    func setAddressService(_ service: AddressService?) {
        self.addressService = service
    }
    
    /// Set the linking service for movement-onchain linking
    func setLinkingService(_ service: TransactionLinkingService?) {
        self.linkingService = service
    }
    
    // MARK: - Transaction Operations
    
    /// Refresh transactions with deduplication using upsert strategy.
    ///
    /// Deduplicated: if a refresh is already in flight this **joins** it
    /// rather than starting a new one, so on return the newest data is only
    /// as fresh as whenever that in-flight fetch called `getMovements()`.
    /// Fine for "show me transactions"; not safe after writing wallet state —
    /// use `refreshTransactionsAfterWrite()` for that.
    func refreshTransactions() async {
        await taskManager.execute(key: "transactions") {
            await self.performRefreshTransactions()
        }
    }

    /// Refresh transactions with a guarantee that the fetch observes writes
    /// made before this call ("read your own writes").
    ///
    /// Awaits any in-flight refresh first — so we neither stampede nor cancel
    /// someone else's work — and then performs a fresh fetch, because that
    /// earlier fetch may have read bark before our write landed. Callers that
    /// just changed wallet state (refresh scheduled, exit progressed, round
    /// completed) must use this: joining a stale fetch left
    /// `hasActiveRefresh` and `vtxoIdsBeingRefreshed()` blind to a refresh
    /// the app had just scheduled (`Features/Refresh_Deduplication.md` §3.2).
    func refreshTransactionsAfterWrite() async {
        await taskManager.executeFresh(key: "transactions") {
            await self.performRefreshTransactions()
        }
    }


    private func performRefreshTransactions() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let output = try await wallet.getMovements()
            Self.logger.debug("Transactions output: \(output)")
            await upsertTransactionsFromServerData(output)
            hasLoadedTransactions = true
        } catch {
            Self.logger.error("Failed to get transactions: \(error.localizedDescription)")
            self.error = "Failed to get transactions: \(error)"
        }
    }
    
    /// Process a single movement from notification stream
    /// Converts single movement JSON to array format and processes through existing upsert pipeline
    func processSingleMovement(json: String) async {
        guard modelContext != nil else {
            Self.logger.error("No model context available for processing movement")
            return
        }
        
        // Wrap single movement in array format expected by parser
        let wrappedJson = "[\(json)]"
        
        Self.logger.info("Processing single movement from notification")
        
        // Reuse existing upsert pipeline
        await upsertTransactionsFromServerData(wrappedJson)
        
        Self.logger.info("Processed single movement from notification")
    }
    
    // MARK: - State Management
    
    /// Clear error state
    func clearError() {
        error = nil
    }
}

// MARK: - Transaction Service Errors

enum TransactionServiceError: LocalizedError {
    case noModelContext
    case transactionNotFound(txid: String)
    case notesTooLong(count: Int, limit: Int)
    
    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "No model context available for database operations"
        case .transactionNotFound(let txid):
            return "Transaction not found: \(txid)"
        case .notesTooLong(let count, let limit):
            return "Notes too long: \(count) characters (limit: \(limit))"
        }
    }
}

// MARK: - Transaction Data Model

extension TransactionService {
    /// Intermediate transaction data used during parsing and upserting
    struct TransactionData {
        let txid: String
        let movementId: Int
        let recipientIndex: Int?
        let type: TransactionTypeEnum
        let amount: Int
        let date: Date
        let status: TransactionStatusEnum
        let address: String?
        let fees: Int?  // Proportionally allocated fees for this transaction
        
        // Enhanced metadata
        let category: MovementCategory
        let subsystemName: String  // Raw subsystem name from server (e.g., "bark.offboard")
        let subsystemKind: String  // Raw subsystem kind from server (e.g., "send_onchain")
        let paymentMethod: PaymentMethod?
        let paymentHash: String?
        let paymentPreimage: String?
        let onchainFeeSat: Int?
        let fundingTxid: String?
        let inputVtxoIds: [String]
        let outputVtxoIds: [String]
        let exitedVtxoIds: [String]
        let lightningOffer: String?  // Lightning offer (BOLT12) for contact matching (Bark v0.10.0+)
        
        /// Whether this transaction should be shown in history by default
        var shouldShowInHistory: Bool {
            category.showInHistoryByDefault
        }
    }
}

