//
//  WalletManager.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Export Data Structure
struct WalletExportData: Codable {
    let addresses: AddressData
    let balances: BalanceData
    let transactions: [TransactionModel]
    let vtxos: [VTXOModel]
    let utxos: [UTXOModel]
    let configuration: ArkConfigModel
    let arkInfo: ArkInfoModel
    let blockHeight: Int
    let exportTimestamp: Date
    
    struct AddressData: Codable {
        let arkAddress: String
        let onchainAddress: String
    }
    
    struct BalanceData: Codable {
        let arkBalance: ArkBalanceModel?
        let onchainBalance: OnchainBalanceModel?
        let totalBalance: TotalBalanceModel?
    }
}

@MainActor
@Observable
class WalletManager {
    // MARK: - Coordinator State
    var isInitialized: Bool = false
    var error: String?
    var isRefreshing: Bool = false
    var hasLoadedOnce: Bool = false
    
    // MARK: - Services
    private var wallet: BarkWalletProtocol?
    private let asp = "ark.signet.2nd.dev"
    private let taskManager = TaskDeduplicationManager()
    private let cacheManager = WalletCacheManager()
    private var modelContext: ModelContext?
    
    private var transactionService: TransactionService?
    private var balanceService: BalanceService?
    private var addressService: AddressService?
    private var walletOperationsService: WalletOperationsService?
    
    // MARK: - Computed Properties - Data Access
    var transactions: [TransactionModel] {
        transactionService?.transactions ?? []
    }
    
    var arkAddress: String {
        addressService?.arkAddress ?? ""
    }
    
    var onchainAddress: String {
        addressService?.onchainAddress ?? ""
    }
    
    var arkBalance: ArkBalanceModel? {
        balanceService?.arkBalance
    }
    
    var onchainBalance: OnchainBalanceModel? {
        balanceService?.onchainBalance
    }
    
    var totalBalance: TotalBalanceModel? {
        balanceService?.totalBalance
    }
    
    // MARK: - Computed Properties - Formatted Values
    var formattedSpendableBalance: String {
        let spendableAmount = totalBalance?.totalSpendableSat ?? 0
        return BitcoinFormatter.formatAmount(spendableAmount)
    }
    
    var formattedTotalBalance: String {
        let totalAmount = totalBalance?.grandTotalSat ?? 0
        return BitcoinFormatter.formatAmount(totalAmount)
    }
    
    var formattedArkSpendableBalance: String {
        let arkSpendable = arkBalance?.spendableSat ?? 0
        return BitcoinFormatter.formatAmount(arkSpendable)
    }
    
    var formattedOnchainSpendableBalance: String {
        let onchainSpendable = onchainBalance?.trustedSpendableSat ?? 0
        return BitcoinFormatter.formatAmount(onchainSpendable)
    }
    
    // MARK: - Computed Properties - State Checks
    var hasPendingBalance: Bool {
        balanceService?.hasPendingBalance ?? false
    }
    
    var hasSpendableBalance: Bool {
        balanceService?.hasSpendableBalance ?? false
    }
    
    var isInitialLoading: Bool {
        isRefreshing && !hasLoadedOnce && !(transactionService?.hasLoadedTransactions ?? false)
    }
    
    var isRefreshingWithData: Bool {
        isRefreshing && hasLoadedOnce
    }
    
    var arkInfo: ArkInfoModel? {
        balanceService?.arkInfo
    }
    
    var estimatedBlockHeight: Int? {
        balanceService?.estimatedBlockHeight
    }
    
    // MARK: - Initialization
    init(useMock: Bool = false) {
        setupWallet(useMock: useMock)
        initializeServices()
    }
    
    private func setupWallet(useMock: Bool) {
        wallet = useMock ? MockBarkWallet() : BarkWallet()
    }
    
    private func initializeServices() {
        guard let wallet = wallet else { return }
        
        // Initialize all services with shared task manager and cache manager
        transactionService = TransactionService(wallet: wallet, taskManager: taskManager)
        balanceService = BalanceService(wallet: wallet, taskManager: taskManager, cacheManager: cacheManager)
        addressService = AddressService(wallet: wallet, taskManager: taskManager)
        walletOperationsService = WalletOperationsService(wallet: wallet, taskManager: taskManager)
        
        // Configure post-transaction callback
        walletOperationsService?.setTransactionCompletedCallback { [weak self] in
            await self?.balanceService?.refreshAfterTransaction()
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        transactionService?.setModelContext(context)
    }
    
    // MARK: - Coordination Methods
    func initialize() async {
        await taskManager.execute(key: "initialize") {
            await self.performInitialization()
        }
    }
    
    private func performInitialization() async {
        guard let wallet = wallet else {
            error = "Wallet not available"
            return
        }
        
        // Check wallet existence
        let mnemonicFile = wallet.walletDir.appendingPathComponent("mnemonic")
        let walletExists = FileManager.default.fileExists(atPath: mnemonicFile.path)
        
        if walletExists {
            print("✅ Wallet mnemonic found - wallet exists")
            isInitialized = true
        } else {
            print("⚠️ No mnemonic found - need to create wallet")
            await createNewWallet()
        }
        
        // Load all wallet data
        if isInitialized {
            await refresh()
        }
    }
    
    private func createNewWallet() async {
        guard let wallet = wallet else { return }
        
        // Clean up empty directory if it exists
        if FileManager.default.fileExists(atPath: wallet.walletDir.path) {
            print("🗑️ Cleaning up empty directory")
            try? FileManager.default.removeItem(at: wallet.walletDir)
        }
        
        do {
            let newWallet = try await wallet.createWallet(network: "signet", asp: asp)
            print("✅ Wallet created successfully", newWallet)
            isInitialized = true
        } catch {
            let errorMsg = "\(error)"
            print("❌ Failed to create wallet: \(errorMsg)")
            self.error = "Failed to create wallet: \(errorMsg)"
        }
    }
    
    /// Centralized refresh - orchestrates all services
    func refresh() async {
        await taskManager.execute(key: "refresh") {
            await self.performRefresh()
        }
    }
    
    private func performRefresh() async {
        isRefreshing = true
        defer { 
            isRefreshing = false
            hasLoadedOnce = true
        }
        
        guard wallet != nil else { 
            error = "Wallet not initialized"
            return 
        }
        
        // Coordinate service refreshes in parallel where possible
        await withTaskGroup(of: Void.self) { group in
            // Balance service handles its own coordination
            group.addTask { await self.balanceService?.refreshAllBalances() }
            
            // Address loading
            group.addTask { await self.addressService?.loadAddresses() }
            
            // Transaction refresh
            group.addTask { await self.transactionService?.refreshTransactions() }
        }
        
        // Check for errors from services
        if let addressError = addressService?.error {
            self.error = addressError
            return
        }
        
        if let transactionError = transactionService?.error {
            self.error = transactionError
            return
        }
        
        if let balanceError = balanceService?.error {
            self.error = balanceError
            return
        }
        
        error = nil
        print("✅ All wallet data refreshed successfully")
    }
    
    // MARK: - Wallet Operations (delegates to WalletOperationsService)
    
    func send(to address: String, amount: Int) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.send(to: address, amount: amount)
    }
    
    func sendOnchain(to address: String, amount: Int) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.sendOnchain(to: address, amount: amount)
    }
    
    func board(amount: Int) async throws {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        try await walletOperationsService.board(amount: amount)
    }
    
    func boardAll() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.boardAll()
    }
    
    /// Start the exit process for pending VTXOs - checks exit progress and waits
    func startExit() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.startExit()
    }
    
    /// Exit a specific VTXO by its ID
    func exitVTXO(vtxoId: String) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.exitVTXO(vtxoId: vtxoId)
    }
    
    func getVTXOs() async throws -> [VTXOModel] {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getVTXOs()
    }
    
    func getUTXOs() async throws -> [UTXOModel] {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getUTXOs()
    }
    
    func getConfig() async throws -> ArkConfigModel {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getConfig()
    }
    
    func getArkInfo() async throws -> ArkInfoModel {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getArkInfo()
    }
    
    /// Refresh VTXOs by calling the wallet's refresh command
    func refreshVTXOs() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.refreshVTXOs()
    }
    
    /// Get the wallet's mnemonic phrase
    func getMnemonic() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkError.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getMnemonic()
    }
    
    func getLatestBlockHeight() async throws -> Int {
        return try await getBlockHeightWithDeduplication()
    }
    
    private func getBlockHeightWithDeduplication() async throws -> Int {
        // Check cache first
        if let cached = cacheManager.blockHeight.value {
            print("📦 Using cached block height: \(cached)")
            return cached
        }
        
        return try await taskManager.execute(key: "blockHeight") {
            guard let wallet = self.wallet else {
                throw BarkError.commandFailed("Wallet not initialized")
            }
            let result = try await wallet.getLatestBlockHeight()
            
            // Update cache
            self.cacheManager.blockHeight.setValue(result)
            print("🔗 Fetched latest block height: \(result)")
            
            return result
        }
    }


    func getTransactions() async throws -> String {
        return try await transactionService?.getTransactions() ?? ""
    }
    
    /// Get the current Ark balance model - delegates to balance service
    func getArkBalance() async throws -> ArkBalanceModel {
        guard let balanceService = balanceService else {
            throw BarkError.commandFailed("Balance service not initialized")
        }
        return try await balanceService.getArkBalance()
    }
    
    /// Get the current onchain balance model - delegates to balance service
    func getCurrentOnchainBalance() async throws -> OnchainBalanceModel {
        guard let balanceService = balanceService else {
            throw BarkError.commandFailed("Balance service not initialized")
        }
        return try await balanceService.getCurrentOnchainBalance()
    }
    
    // MARK: - Convenience Methods for Individual Refreshes (delegates to BalanceService)
    
    /// Refresh just Ark balance - delegates to balance service
    func refreshArkBalance() async {
        await balanceService?.refreshArkBalance()
        // Update local error state if balance service encountered an error
        if let balanceError = balanceService?.error {
            self.error = balanceError
        }
    }
    
    /// Refresh just onchain balance - delegates to balance service
    func refreshOnchainBalance() async {
        await balanceService?.refreshOnchainBalance()
        // Update local error state if balance service encountered an error
        if let balanceError = balanceService?.error {
            self.error = balanceError
        }
    }
    
    /// Load wallet addresses
    func loadAddresses() async {
        await addressService?.loadAddresses()
        // Update local error state if address service encountered an error
        if let addressError = addressService?.error {
            self.error = addressError
        }
    }
    
    /// Get estimated block height, fetching cached data if needed
    func getEstimatedBlockHeight() async -> Int? {
        // Ensure we have both cached block height and ark info
        if cacheManager.blockHeight.value == nil {
            do {
                _ = try await getLatestBlockHeight()
            } catch {
                print("⚠️ Failed to fetch block height for estimation: \(error)")
            }
        }
        
        // Cache ArkInfo if needed using balance service
        if cacheManager.arkInfo.value == nil {
            await balanceService?.cacheArkInfoIfNeeded()
        }
        
        return cacheManager.getEstimatedBlockHeight()
    }
    
    // MARK: - Data Export
    
    /// Export all wallet data as JSON
    func exportWalletData() async throws -> Data {
        return try await taskManager.execute(key: "exportData") {
            try await self.performDataExport()
        }
    }
    
    private func performDataExport() async throws -> Data {
        // Gather async data first
        let vtxos = try await getVTXOs()
        let utxos = try await getUTXOs()
        let configuration = try await getConfig()
        
        // Get arkInfo with fallback
        let currentArkInfo: ArkInfoModel
        if let cached = arkInfo {
            currentArkInfo = cached
        } else {
            currentArkInfo = try await getArkInfo()
        }
        
        // Get block height with fallback
        let currentBlockHeight: Int
        if let cached = estimatedBlockHeight {
            currentBlockHeight = cached
        } else {
            currentBlockHeight = try await getLatestBlockHeight()
        }
        
        // Create export data
        let exportData = WalletExportData(
            addresses: WalletExportData.AddressData(
                arkAddress: arkAddress,
                onchainAddress: onchainAddress
            ),
            balances: WalletExportData.BalanceData(
                arkBalance: arkBalance,
                onchainBalance: onchainBalance,
                totalBalance: totalBalance
            ),
            transactions: transactions,
            vtxos: vtxos,
            utxos: utxos,
            configuration: configuration,
            arkInfo: currentArkInfo,
            blockHeight: currentBlockHeight,
            exportTimestamp: Date()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(exportData)
    }

}


