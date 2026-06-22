//
//  WalletOperationsService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import Bark

@MainActor
@Observable
class WalletOperationsService {
    var error: String?
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    
    // Callback for post-transaction balance refresh
    var onTransactionCompleted: (() async -> Void)?
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    // MARK: - Transaction Operations
    
    /// Send Ark payment to an address
    func send(to address: String, amount: Int) async throws -> String {
        return try await taskManager.execute(key: "send-\(address)-\(amount)") {
            let result = try await self.wallet.send(to: address, amount: amount)
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    /// Send onchain Bitcoin transaction
    func sendOnchain(to address: String, amount: Int, feeRateSatPerVb: UInt64? = nil) async throws -> String {
        return try await taskManager.execute(key: "sendOnchain-\(address)-\(amount)") {
            let result = try await self.wallet.sendOnchain(to: address, amount: amount, feeRateSatPerVb: feeRateSatPerVb)
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    /// Send from VTXOs to onchain Bitcoin transaction
    func sendToOnchain(to address: String, amount: Int) async throws -> String {
        return try await taskManager.execute(key: "sendToOnchain-\(address)-\(amount)") {
            let result = try await self.wallet.sendToOnchain(to: address, amount: amount)
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    /// Board funds to Ark (move onchain funds to Ark)
    func board(amount: Int) async throws {
        try await taskManager.execute(key: "board-\(amount)") {
            try await self.wallet.board(amount: amount)
            await self.onTransactionCompleted?()
        }
    }
    
    /// Board all available onchain funds to Ark
    func boardAll() async throws -> String {
        return try await taskManager.execute(key: "boardAll") {
            let result = try await self.wallet.boardAll()
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    // MARK: - Exit Operations
    
    /// Start the exit process for pending VTXOs - checks exit progress and waits
    func startExit() async throws -> String {
        return try await taskManager.execute(key: "startExit") {
            let result = try await self.wallet.startExit()
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    /// Exit a specific VTXO by its ID
    func exitVTXO(vtxoId: String, to address: String) async throws -> String {
        return try await taskManager.execute(key: "exitVTXO-\(vtxoId)") {
            let result = try await self.wallet.exitVTXO(vtxo_id: vtxoId, to: address)
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    // MARK: - Data Retrieval Operations
    
    /// Get all VTXOs (Virtual Transaction Outputs)
    func getVTXOs() async throws -> [VTXOModel] {
        return try await taskManager.execute(key: "getVTXOs") {
            return try await self.wallet.getVTXOs()
        }
    }
    
    /// Get all UTXOs (Unspent Transaction Outputs)
    func getUTXOs() async throws -> [UTXOModel] {
        return try await taskManager.execute(key: "getUTXOs") {
            return try await self.wallet.getUTXOs()
        }
    }
    
    /// Get wallet configuration
    func getConfig() async throws -> ArkConfigModel {
        return try await taskManager.execute(key: "getConfig") {
            return try await self.wallet.getConfig()
        }
    }
    
    /// Get Ark network information
    func getArkInfo() async throws -> ArkInfoModel {
        return try await taskManager.execute(key: "getArkInfo") {
            return try await self.wallet.getArkInfo()
        }
    }
    
    /// Get the wallet's mnemonic phrase
    func getMnemonic() async throws -> String {
        return try await taskManager.execute(key: "getMnemonic") {
            return try await self.wallet.getMnemonic()
        }
    }
    
    // MARK: - Refresh Operations
    
    /// Refresh VTXOs using delegated refresh (non-blocking)
    /// Schedules the refresh without requiring the app to stay online until round starts
    func refreshVtxosDelegated(vtxo_ids: [String]) async throws -> String {
        return try await taskManager.execute(key: "refreshVTXOs") {
            let roundState = try await self.wallet.refreshVtxosDelegated(vtxoIds: vtxo_ids)
            
            if let roundState = roundState {
                print("✅ VTXOs refresh scheduled successfully, Round ID: \(roundState.id)")
                await self.onTransactionCompleted?()
                return "Refresh scheduled for round \(roundState.id)"
            } else {
                print("ℹ️ No refresh scheduled (VTXOs may not need refresh yet)")
                return "No refresh needed"
            }
        }
    }
    
    /// Refresh a single VTXO using delegated refresh (non-blocking)
    /// Schedules the refresh without requiring the app to stay online until round starts
    func refreshVtxoDelegated(vtxo_id: String) async throws -> String {
        return try await taskManager.execute(key: "refreshVTXO-\(vtxo_id)") {
            let roundState = try await self.wallet.refreshVtxosDelegated(vtxoIds: [vtxo_id])
            
            if let roundState = roundState {
                print("✅ VTXO refresh scheduled successfully, Round ID: \(roundState.id)")
                await self.onTransactionCompleted?()
                return "Refresh scheduled for round \(roundState.id)"
            } else {
                print("ℹ️ No refresh scheduled (VTXO may not need refresh yet)")
                return "No refresh needed"
            }
        }
    }
    
    // MARK: - Lightning Operations
    
    /// Generate a Lightning invoice for the specified amount
    func getLightningInvoice(amountSats: UInt64, description: String?) async throws -> String {
        return try await taskManager.execute(key: "getLightningInvoice-\(amountSats)") {
            let result = try await self.wallet.getLightningInvoice(amountSats: amountSats, description: description)
            print("✅ Lightning invoice generated for \(amountSats) sats")
            return result
        }
    }
    
    /// Pay a Lightning invoice with optional amount (for invoices that may already include an amount)
    func payLightningInvoice(invoice: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        return try await taskManager.execute(key: "payLightningInvoice-\(invoice.prefix(20))") {
            let result = try await self.wallet.payLightningInvoice(invoice: invoice, amountSats: amountSats.map { UInt64($0) }, wait: true)
            print("✅ Lightning invoice payment completed")
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    /// Get the status of a Lightning invoice
    func getLightningInvoiceStatus(invoice: String) async throws -> String {
        return try await taskManager.execute(key: "getLightningInvoiceStatus-\(invoice.prefix(20))") {
            let result = try await self.wallet.getLightningInvoiceStatus(invoice: invoice)
            print("✅ Lightning invoice status retrieved")
            return result
        }
    }
    
    /// List all Lightning invoices
    func listLightningInvoices() async throws -> String {
        return try await taskManager.execute(key: "listLightningInvoices") {
            let result = try await self.wallet.listLightningInvoices()
            print("✅ Lightning invoices listed")
            return result
        }
    }
    
    /// Claim a Lightning invoice
    func claimLightningInvoice(invoice: String) async throws -> String {
        return try await taskManager.execute(key: "claimLightningInvoice-\(invoice.prefix(20))") {
            let result = try await self.wallet.claimLightningInvoice(invoice: invoice)
            print("✅ Lightning invoice claimed")
            await self.onTransactionCompleted?()
            return result
        }
    }
    
    // MARK: - Custom Command Execution
    
    /// Execute a custom bark CLI command
    /// - Parameter commandString: The command to execute (e.g., "balance", "vtxos --limit 5")
    /// - Returns: Raw command output
    /// - Note: For development and debugging purposes
    func executeCustomCommand(_ commandString: String) async throws -> String {
        // Use timestamp to ensure commands aren't deduplicated
        let key = "customCommand-\(Date().timeIntervalSince1970)"
        return try await taskManager.execute(key: key) {
            return try await self.wallet.executeCustomCommand(commandString)
        }
    }
    
    // MARK: - Utility Methods
    
    /// Set the callback for post-transaction operations
    func setTransactionCompletedCallback(_ callback: @escaping () async -> Void) {
        self.onTransactionCompleted = callback
    }
    
    /// Clear any error state
    func clearError() {
        error = nil
    }
    
    /// Check if a specific operation is currently running
    func isOperationRunning(_ operationKey: String) -> Bool {
        return taskManager.isRunning(key: operationKey)
    }
    
    /// Check if any transaction-related operations are currently running
    var isAnyTransactionRunning: Bool {
        return taskManager.isRunning(key: "boardAll") ||
               taskManager.isRunning(key: "startExit") ||
               taskManager.isRunning(key: "refreshVTXOs") ||
               taskManager.runningTaskKeys.contains { $0.hasPrefix("payLightningInvoice") } ||
               taskManager.runningTaskKeys.contains { $0.hasPrefix("claimLightningInvoice") }
    }
    
    /// Check if any Lightning operations are currently running
    var isAnyLightningOperationRunning: Bool {
        return taskManager.runningTaskKeys.contains { key in
            key.hasPrefix("payLightningInvoice") ||
            key.hasPrefix("claimLightningInvoice") ||
            key.hasPrefix("getLightningInvoice") ||
            key.hasPrefix("getLightningInvoiceStatus") ||
            key.hasPrefix("listLightningInvoices")
        }
    }
}
