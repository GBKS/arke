//
//  WalletManager.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation
import SwiftUI

// MARK: - JSON Parsing Models for Movements

private struct MovementData: Codable {
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

private struct RecipientData: Codable {
    let recipient: String
    let amountSat: Int
    
    enum CodingKeys: String, CodingKey {
        case recipient
        case amountSat = "amount_sat"
    }
}

private struct TransactionOutput: Codable {
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

@MainActor
@Observable
class WalletManager {
    var isInitialized: Bool = false
    var arkBalance: ArkBalanceModel?
    var onchainBalance: OnchainBalanceModel?
    var totalBalance: TotalBalanceModel?
    var transactions: [TransactionModel] = []
    var arkAddress: String = ""
    var onchainAddress: String = ""
    var error: String?
    var isRefreshing: Bool = false
    var hasLoadedOnce: Bool = false
    
    private var wallet: BarkWalletProtocol?
    private let asp = "ark.signet.2nd.dev"
    
    // Request deduplication - track in-flight operations
    private var refreshTask: Task<Void, Never>?
    private var initializeTask: Task<Void, Never>?
    private var arkBalanceTask: Task<ArkBalanceModel, Error>?
    private var onchainBalanceTask: Task<OnchainBalanceModel, Error>?
    private var addressTask: Task<Void, Never>?
    private var transactionsTask: Task<Void, Never>?
    private var blockHeightTask: Task<Int, Error>?
    
    // Block height caching
    private var cachedBlockHeight: Int?
    private var blockHeightCacheTime: Date?
    private let blockHeightCacheTimeout: TimeInterval = 60 // Cache for 1 minute
    
    // Ark info caching for round interval
    private var cachedArkInfo: ArkInfoModel?
    private var arkInfoCacheTime: Date?
    private let arkInfoCacheTimeout: TimeInterval = 300 // Cache for 5 minutes
    
    // MARK: - Computed Properties for UI
    
    /// Formatted total spendable balance across all wallets
    var formattedSpendableBalance: String {
        guard let totalBalance = totalBalance else { return "0 sats" }
        return "\(totalBalance.totalSpendableSat.formatted()) sats"
    }
    
    /// Formatted total balance across all wallets
    var formattedTotalBalance: String {
        guard let totalBalance = totalBalance else { return "0 sats" }
        return "\(totalBalance.grandTotalSat.formatted()) sats"
    }
    
    /// Formatted Ark spendable balance
    var formattedArkSpendableBalance: String {
        guard let arkBalance = arkBalance else { return "0 sats" }
        return "\(arkBalance.spendableSat.formatted()) sats"
    }
    
    /// Formatted onchain spendable balance
    var formattedOnchainSpendableBalance: String {
        guard let onchainBalance = onchainBalance else { return "0 sats" }
        return "\(onchainBalance.trustedSpendableSat.formatted()) sats"
    }
    
    /// True if there are any pending balances
    var hasPendingBalance: Bool {
        totalBalance?.hasPendingBalance ?? false
    }
    
    /// True if user has any spendable funds
    var hasSpendableBalance: Bool {
        totalBalance?.hasSpendableBalance ?? false
    }
    
    /// True if this is the initial load (no data loaded yet)
    var isInitialLoading: Bool {
        isRefreshing && !hasLoadedOnce
    }
    
    /// True if data has been loaded before and is currently refreshing
    var isRefreshingWithData: Bool {
        isRefreshing && hasLoadedOnce
    }
    
    /// Cached Ark info for UI components
    var arkInfo: ArkInfoModel? {
        return cachedArkInfo
    }
    
    /// Estimated current block height based on cached data and round interval
    var estimatedBlockHeight: Int? {
        guard let cachedHeight = cachedBlockHeight,
              let cacheTime = blockHeightCacheTime,
              let arkInfo = cachedArkInfo,
              let roundIntervalSeconds = arkInfo.roundIntervalSeconds else {
            return cachedBlockHeight // Return cached value if we can't estimate
        }
        
        let secondsElapsed = Date().timeIntervalSince(cacheTime)
        let roundsElapsed = Int(secondsElapsed) / roundIntervalSeconds
        
        return cachedHeight + roundsElapsed
    }
    
    init(useMock: Bool = false) {
        if useMock {
            wallet = MockBarkWallet()
        } else {
            wallet = BarkWallet()
        }
    }
    
    func initialize() async {
        // Deduplicate initialization requests
        if let existingTask = initializeTask {
            await existingTask.value
            return
        }
        
        let task = Task {
            await performInitialization()
        }
        initializeTask = task
        await task.value
        initializeTask = nil
    }
    
    private func performInitialization() async {
        guard let wallet = wallet else {
            error = "Wallet not available"
            return
        }
        
        // Check if wallet actually exists by looking for the mnemonic file
        let mnemonicFile = wallet.walletDir.appendingPathComponent("mnemonic")
        let walletExists = FileManager.default.fileExists(atPath: mnemonicFile.path)
        
        if walletExists {
            print("✅ Wallet mnemonic found - wallet exists")
            isInitialized = true
        } else {
            print("⚠️ No mnemonic found - need to create wallet")
            
            // If directory exists but no wallet, delete it first
            if FileManager.default.fileExists(atPath: wallet.walletDir.path) {
                print("🗑️ Cleaning up empty directory")
                try? FileManager.default.removeItem(at: wallet.walletDir)
            }
            
            // Now create the wallet
            do {
                let wallet = try await wallet.createWallet(network: "signet", asp: asp)
                print("✅ Wallet created successfully", wallet)
                isInitialized = true
            } catch {
                let errorMsg = "\(error)"
                print("❌ Failed to create wallet: \(errorMsg)")
                self.error = "Failed to create wallet: \(errorMsg)"
                return
            }
        }
        
        // Load wallet data using centralized refresh
        await refresh()
    }
    
    /// Centralized refresh method - coordinates all data fetching
    func refresh() async {
        // Deduplicate refresh requests
        if let existingTask = refreshTask {
            await existingTask.value
            return
        }
        
        let task = Task {
            await performRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
    
    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        guard let wallet = wallet else { 
            error = "Wallet not initialized"
            return 
        }
        
        do {
            // First, refresh the wallet state
            //_ = try await wallet.refreshVTXOs()
            
            // Cache ArkInfo for block height estimation
            await cacheArkInfoIfNeeded()
            
            // Then fetch balances in parallel (with deduplication)
            async let arkBalanceResult = getArkBalanceWithDeduplication()
            async let onchainBalanceResult = getOnchainBalanceWithDeduplication()
            
            // Start address and transaction loading in parallel
            let addressTask = Task { await loadAddressesWithDeduplication() }
            let transactionTask = Task { await refreshTransactionsWithDeduplication() }
            
            // Wait for both balances to complete
            let (arkBal, onchainBal) = try await (arkBalanceResult, onchainBalanceResult)
            
            // Update UI state
            self.arkBalance = arkBal
            self.onchainBalance = onchainBal
            updateTotalBalance()
            
            // Wait for other operations to complete
            await addressTask.value
            await transactionTask.value
            
            error = nil
            hasLoadedOnce = true
            print("✅ All wallet data refreshed successfully")
            
        } catch {
            self.error = "Failed to refresh wallet: \(error)"
            print("❌ Failed to refresh wallet: \(error)")
        }
    }
    
    private func updateTotalBalance() {
        guard let arkBalance = arkBalance, let onchainBalance = onchainBalance else {
            print("⚠️ Cannot calculate total balance - missing ark or onchain balance")
            return
        }
        
        totalBalance = TotalBalanceModel(arkBalance: arkBalance, onchainBalance: onchainBalance)
        print("📊 Total balance: \(totalBalance?.grandTotalSat ?? 0) sats (\(totalBalance?.totalSpendableSat ?? 0) spendable)")
    }
    
    // MARK: - Deduplicated Balance Methods
    
    private func getArkBalanceWithDeduplication() async throws -> ArkBalanceModel {
        if let existingTask = arkBalanceTask {
            return try await existingTask.value
        }
        
        let task = Task {
            try await wallet!.getArkBalance()
        }
        arkBalanceTask = task
        
        do {
            let result = try await task.value
            arkBalanceTask = nil
            print("📊 Ark balance: \(result.spendableSat) sats spendable, \(result.totalPendingSat) sats pending")
            return result
        } catch {
            arkBalanceTask = nil
            throw error
        }
    }
    
    private func getOnchainBalanceWithDeduplication() async throws -> OnchainBalanceModel {
        if let existingTask = onchainBalanceTask {
            return try await existingTask.value
        }
        
        let task = Task {
            try await wallet!.getOnchainBalance()
        }
        onchainBalanceTask = task
        
        do {
            let result = try await task.value
            onchainBalanceTask = nil
            print("📊 Onchain balance: \(result.totalSat) sats total, \(result.trustedSpendableSat) sats spendable")
            return result
        } catch {
            onchainBalanceTask = nil
            throw error
        }
    }
    
    private func loadAddressesWithDeduplication() async {
        if let existingTask = addressTask {
            await existingTask.value
            return
        }
        
        let task = Task {
            await performLoadAddresses()
        }
        addressTask = task
        await task.value
        addressTask = nil
    }
    
    private func performLoadAddresses() async {
        guard let wallet = wallet else { return }
        
        do {
            arkAddress = try await wallet.getArkAddress()
            print("✅ Ark address: \(arkAddress)")
        } catch {
            print("❌ Failed to get Ark address: \(error)")
            self.error = "Failed to get Ark address: \(error)"
        }
        
        do {
            onchainAddress = try await wallet.getOnchainAddress()
            print("✅ Onchain address: \(onchainAddress)")
        } catch {
            print("❌ Failed to get onchain address: \(error)")
        }
    }
    
    private func refreshTransactionsWithDeduplication() async {
        if let existingTask = transactionsTask {
            await existingTask.value
            return
        }
        
        let task = Task {
            await performRefreshTransactions()
        }
        transactionsTask = task
        await task.value
        transactionsTask = nil
    }
    
    private func performRefreshTransactions() async {
        guard let wallet = wallet else { return }
        
        do {
            let output = try await wallet.getMovements()
            print("📋 Transactions output: \(output)")
            transactions = parseTransactions(output)
        } catch {
            print("❌ Failed to get transactions: \(error)")
            self.error = "Failed to get transactions: \(error)"
        }
    }
    
    func send(to address: String, amount: Int) async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.send(to: address, amount: amount)
        // After sending, refresh to get updated balances
        await refresh()
        
        return result
    }
    
    func getLatestBlockHeight() async throws -> Int {
        return try await getBlockHeightWithDeduplication()
    }
    
    private func cacheArkInfoIfNeeded() async {
        // Check if we need to refresh ArkInfo cache
        if let _ = cachedArkInfo,
           let cacheTime = arkInfoCacheTime,
           Date().timeIntervalSince(cacheTime) < arkInfoCacheTimeout {
            print("📦 Using cached ArkInfo")
            return
        }
        
        do {
            let arkInfo = try await getArkInfo()
            cachedArkInfo = arkInfo
            arkInfoCacheTime = Date()
            print("✅ ArkInfo cached - round interval: \(arkInfo.roundInterval)")
        } catch {
            print("⚠️ Failed to cache ArkInfo: \(error)")
            // Don't update error state since this is just for caching
        }
    }
    
    private func getBlockHeightWithDeduplication() async throws -> Int {
        // Check cache first
        if let cached = cachedBlockHeight,
           let cacheTime = blockHeightCacheTime,
           Date().timeIntervalSince(cacheTime) < blockHeightCacheTimeout {
            print("📦 Using cached block height: \(cached)")
            return cached
        }
        
        // Check for existing task
        if let existingTask = blockHeightTask {
            return try await existingTask.value
        }
        
        let task = Task {
            guard let wallet = wallet else {
                throw BarkError.commandFailed("Wallet not initialized")
            }
            return try await wallet.getLatestBlockHeight()
        }
        blockHeightTask = task
        
        do {
            let result = try await task.value
            blockHeightTask = nil
            
            // Update cache
            cachedBlockHeight = result
            blockHeightCacheTime = Date()
            print("🔗 Fetched latest block height: \(result)")
            
            return result
        } catch {
            blockHeightTask = nil
            throw error
        }
    }
    
    func sendOnchain(to address: String, amount: Int) async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.sendOnchain(to: address, amount: amount)
        // After sending onchain, refresh to get updated balances
        await refresh()
        
        return result
    }
    
    func board(amount: Int) async throws {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        try await wallet.board(amount: amount)
        // After boarding, refresh to get updated balances
        await refresh()
    }
    
    func boardAll() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.boardAll()
        // After boarding all, refresh to get updated balances
        await refresh()
        return result
    }
    
    func getVTXOs() async throws -> [VTXOModel] {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getVTXOs()
    }
    
    func getUTXOs() async throws -> [UTXOModel] {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getUTXOs()
    }
    
    func getConfig() async throws -> ArkConfigModel {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getConfig()
    }
    
    func getArkInfo() async throws -> ArkInfoModel {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getArkInfo()
    }
    
    /// Start the exit process for pending VTXOs - checks exit progress and waits
    func startExit() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.startExit()
        // After starting exit, refresh to get updated balances and transactions
        await refresh()
        return result
    }
    
    /// Exit a specific VTXO by its ID
    func exitVTXO(vtxoId: String) async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.exitVTXO(vtxo_id: vtxoId)
        // After exiting VTXO, refresh to get updated balances and transactions
        await refresh()
        return result
    }

    func refreshTransactions() async {
        await refreshTransactionsWithDeduplication()
    }
    
    func getTransactions() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getMovements()
    }
    
    /// Refresh VTXOs by calling the wallet's refresh command
    func refreshVTXOs() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let result = try await wallet.refreshVTXOs()
        print("✅ VTXOs refreshed successfully:  \(result)")
        
        return result
    }
    
    // MARK: - Direct Balance Access Methods (with deduplication)
    
    /// Get the current Ark balance model - now uses deduplication
    func getArkBalance() async throws -> ArkBalanceModel {
        return try await getArkBalanceWithDeduplication()
    }
    
    /// Get the current onchain balance model - now uses deduplication
    func getCurrentOnchainBalance() async throws -> OnchainBalanceModel {
        return try await getOnchainBalanceWithDeduplication()
    }
    
    // MARK: - Convenience Methods for Individual Refreshes
    
    /// Refresh just Ark balance (will use centralized refresh if full refresh is better)
    func refreshArkBalance() async {
        do {
            arkBalance = try await getArkBalanceWithDeduplication()
            updateTotalBalance()
            error = nil
        } catch {
            self.error = "Failed to get Ark balance: \(error)"
            print("❌ Failed to get Ark balance: \(error)")
        }
    }
    
    /// Refresh just onchain balance (will use centralized refresh if full refresh is better)
    func refreshOnchainBalance() async {
        do {
            onchainBalance = try await getOnchainBalanceWithDeduplication()
            updateTotalBalance()
            error = nil
        } catch {
            self.error = "Failed to get onchain balance: \(error)"
            print("❌ Failed to get onchain balance: \(error)")
        }
    }
    
    /// Load wallet addresses
    func loadAddresses() async {
        await loadAddressesWithDeduplication()
    }
    
    /// Get estimated block height, fetching cached data if needed
    func getEstimatedBlockHeight() async -> Int? {
        // Ensure we have both cached block height and ark info
        if cachedBlockHeight == nil {
            do {
                _ = try await getLatestBlockHeight()
            } catch {
                print("⚠️ Failed to fetch block height for estimation: \(error)")
            }
        }
        
        if cachedArkInfo == nil {
            await cacheArkInfoIfNeeded()
        }
        
        return estimatedBlockHeight
    }
    
    /// Get the wallet's mnemonic phrase
    func getMnemonic() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        return try await wallet.getMnemonic()
    }
    
    private func parseTransactions(_ output: String) -> [TransactionModel] {
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
                        type: .received,
                        amount: receive.amountSat,
                        date: parseDate(movement.createdAt),
                        status: .confirmed, // Assuming confirmed if it appears in movements
                        txid: receive.id,
                        address: nil // Receiving address not provided in this format
                    )
                    transactions.append(transaction)
                }
                
                // Parse spends (outgoing transactions)
                for spend in movement.spends {
                    // Try to find corresponding recipient address
                    let recipientAddress = movement.recipients.first?.recipient
                    
                    let transaction = TransactionModel(
                        type: .sent,
                        amount: spend.amountSat,
                        date: parseDate(movement.createdAt),
                        status: .confirmed, // Assuming confirmed if it appears in movements
                        txid: spend.id,
                        address: recipientAddress
                    )
                    transactions.append(transaction)
                }
            }
            
            // Sort transactions by date (most recent first)
            transactions.sort { $0.date > $1.date }
            
            print("✅ Parsed \(transactions.count) transactions")
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
}

// Helper extension for regex
extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(self.startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        
        if match.numberOfRanges > 1 {
            let matchRange = match.range(at: 1)
            if let range = Range(matchRange, in: self) {
                return String(self[range])
            }
        }
        return nil
    }
}
