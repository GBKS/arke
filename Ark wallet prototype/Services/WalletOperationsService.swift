//
//  WalletOperationsService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation

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
    func sendOnchain(to address: String, amount: Int) async throws -> String {
        return try await taskManager.execute(key: "sendOnchain-\(address)-\(amount)") {
            let result = try await self.wallet.sendOnchain(to: address, amount: amount)
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
    func exitVTXO(vtxoId: String) async throws -> String {
        return try await taskManager.execute(key: "exitVTXO-\(vtxoId)") {
            let result = try await self.wallet.exitVTXO(vtxo_id: vtxoId)
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
    
    /// Refresh VTXOs by calling the wallet's refresh command
    func refreshVTXOs() async throws -> String {
        return try await taskManager.execute(key: "refreshVTXOs") {
            let result = try await self.wallet.refreshVTXOs()
            print("✅ VTXOs refreshed successfully: \(result)")
            await self.onTransactionCompleted?()
            return result
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
               taskManager.isRunning(key: "refreshVTXOs")
    }
}
