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
    let transactions: [ExportTransactionData]
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
        let arkBalance: ArkBalanceResponse?
        let onchainBalance: OnchainBalanceModel?
        // Note: TotalBalanceModel is computed from the above, not stored
    }
    
    struct ExportTransactionData: Codable {
        let txid: String
        let movementId: Int?
        let recipientIndex: Int?
        let type: String
        let amount: Int
        let date: Date
        let status: String
        let address: String?
        
        init(from TransactionModel: TransactionModel) {
            self.txid = TransactionModel.txid
            self.movementId = TransactionModel.movementId
            self.recipientIndex = TransactionModel.recipientIndex
            self.type = TransactionModel.type
            self.amount = TransactionModel.amount
            self.date = TransactionModel.date
            self.status = TransactionModel.status
            self.address = TransactionModel.address
        }
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
    private let taskManager = TaskDeduplicationManager()
    private let cacheManager = WalletCacheManager()
    private var modelContext: ModelContext?
    
    private var transactionService: TransactionService?
    private var balanceService: BalanceService?
    private var addressService: AddressService?
    private var walletOperationsService: WalletOperationsService?
    private var tagService: TagService?
    
    // MARK: - Computed Properties - Network Info
    var currentNetworkName: String {
        wallet?.currentNetworkName ?? "Unknown"
    }
    
    var isMainnet: Bool {
        wallet?.isMainnet ?? false
    }
    
    var networkConfig: NetworkConfig? {
        wallet?.networkConfig
    }
    
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
    
    // MARK: - Tag Properties
    var tags: [TagModel] {
        tagService?.tags ?? []
    }
    
    var activeTags: [TagModel] {
        tagService?.activeTags ?? []
    }
    
    var hasTagsAvailable: Bool {
        tagService?.hasTags ?? false
    }
    
    var tagServiceError: String? {
        tagService?.error
    }
    
    /// Access to TagService for SwiftUI environment injection
    var tagServiceForEnvironment: TagService? {
        tagService
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
    
    var transactionServiceInstance: TransactionService? {
        transactionService
    }
    
    // MARK: - Initialization
    init(useMock: Bool = false, networkConfig: NetworkConfig? = nil) {
        let config = networkConfig ?? NetworkConfig.signet
        setupWallet(useMock: useMock, networkConfig: config)
        initializeServices()
    }
    
    /// Convenience initializer for different networks
    static func forNetwork(_ networkConfig: NetworkConfig, useMock: Bool = false) -> WalletManager {
        return WalletManager(useMock: useMock, networkConfig: networkConfig)
    }
    
    private func setupWallet(useMock: Bool, networkConfig: NetworkConfig) {
        if useMock {
            wallet = MockBarkWallet()
        } else {
            wallet = BarkWallet(networkConfig: networkConfig)
            if wallet == nil {
                print("❌ Failed to initialize BarkWallet with network config: \(networkConfig.name)")
            }
        }
    }
    
    private func initializeServices() {
        guard let wallet = wallet else { return }
        
        // Initialize all services with shared task manager and cache manager
        transactionService = TransactionService(wallet: wallet, taskManager: taskManager)
        balanceService = BalanceService(wallet: wallet, taskManager: taskManager, cacheManager: cacheManager)
        addressService = AddressService(wallet: wallet, taskManager: taskManager)
        walletOperationsService = WalletOperationsService(wallet: wallet, taskManager: taskManager)
        tagService = TagService(taskManager: taskManager)
        
        // Configure post-transaction callback
        walletOperationsService?.setTransactionCompletedCallback { [weak self] in
            await self?.balanceService?.refreshAfterTransaction()
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        transactionService?.setModelContext(context)
        balanceService?.setModelContext(context)
        tagService?.setModelContext(context)
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
            print("✅ Wallet mnemonic found - wallet exists on \(currentNetworkName)")
            isInitialized = true
            // Load all wallet data for existing wallet
            await refresh()
            // Create default tags if needed (after data is loaded)
            await createDefaultTagsIfNeeded()
        } else {
            print("⚠️ No mnemonic found - wallet needs to be created or imported on \(currentNetworkName)")
            isInitialized = false
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
            group.addTask { 
                await self.balanceService?.refreshAllBalances() 
            }
            
            // Address loading
            group.addTask { 
                await self.addressService?.loadAddresses() 
            }
            
            // Transaction refresh
            group.addTask { 
                await self.transactionService?.refreshTransactions() 
            }
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
        print("✅ All wallet data refreshed successfully on \(currentNetworkName)")
    }
    
    // MARK: - Tag Operations (delegates to TagService)
    
    /// Create a new tag
    func createTag(_ tagModel: TagModel) async throws -> TagModel {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        return try await tagService.createTag(tagModel)
    }
    
    /// Update an existing tag
    func updateTag(_ tagModel: TagModel) async throws {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        try await tagService.updateTag(tagModel)
    }
    
    /// Delete a tag (soft delete)
    func deleteTag(_ tagId: UUID) async throws {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        try await tagService.deleteTag(tagId)
    }
    
    /// Assign a tag to a transaction
    func assignTag(_ tagId: UUID, to transactionTxid: String) async throws {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        try await tagService.assignTag(tagId, to: transactionTxid)
    }
    
    /// Remove a tag assignment from a transaction
    func unassignTag(_ tagId: UUID, from transactionTxid: String) async throws {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        try await tagService.unassignTag(tagId, from: transactionTxid)
    }
    
    /// Get all transactions with a specific tag
    func getTransactionsWithTag(_ tagId: UUID) async throws -> [TransactionModel] {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        return try await tagService.getTransactionsWithTag(tagId)
    }
    
    /// Create default tags if needed
    func createDefaultTagsIfNeeded() async {
        await tagService?.createDefaultTagsIfNeeded()
    }
    
    /// Get tag usage statistics
    func getTagStatistics() async throws -> [TagStatistic] {
        guard let tagService = tagService else {
            throw BarkError.commandFailed("Tag service not initialized")
        }
        return try await tagService.getTagStatistics()
    }
    
    /// Clear tag service errors
    func clearTagError() {
        tagService?.clearError()
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
    
    /// Import an existing wallet using a mnemonic phrase
    func importWallet(mnemonic: String) async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMnemonic.isEmpty else {
            throw BarkError.commandFailed("Mnemonic phrase cannot be empty")
        }
        
        let result = try await wallet.importWallet(network: wallet.networkConfig.networkType, asp: wallet.networkConfig.aspURL, mnemonic: trimmedMnemonic)
        isInitialized = true
        return result
    }
    
    /// Create a new wallet
    func createWallet() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        // Execute creation through task manager for deduplication
        return try await taskManager.execute(key: "createWallet") {
            let result = try await wallet.createWallet(network: wallet.networkConfig.networkType, asp: wallet.networkConfig.aspURL)
            self.isInitialized = true
            print("✅ New wallet created successfully on \(self.currentNetworkName)")
            return result
        }
    }
    
    /// Delete the current wallet and reset manager state
    func deleteWallet() async throws -> String {
        guard let wallet = wallet else {
            throw BarkError.commandFailed("Wallet not initialized")
        }
        
        // Execute deletion through task manager for deduplication
        return try await taskManager.execute(key: "deleteWallet") {
            let result = try await wallet.deleteWallet()
            
            // Reset all manager state after successful deletion
            await self.resetManagerState()
            
            print("✅ Wallet deleted and manager state reset")
            return result
        }
    }
    
    /// Reset all manager and service state after wallet deletion
    private func resetManagerState() async {
        // Reset coordinator state
        isInitialized = false
        error = nil
        isRefreshing = false
        hasLoadedOnce = false
        
        // Reset balance service state
        balanceService?.arkBalance = nil
        balanceService?.onchainBalance = nil
        balanceService?.totalBalance = nil
        balanceService?.error = nil
        
        // Reset transaction service state (clear transactions)
        await transactionService?.clearTransactionModels()
        transactionService?.error = nil
        transactionService?.hasLoadedTransactions = false
        
        // Reset address service state
        addressService?.arkAddress = ""
        addressService?.onchainAddress = ""
        addressService?.error = nil
        
        // Clear persisted balance data
        balanceService?.resetBalances()
        
        print("🔄 All manager and service state reset")
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
    
    /// Get the current Ark balance response - delegates to balance service
    func getArkBalance() async throws -> ArkBalanceResponse {
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
                arkBalance: arkBalance.map { model in
                    ArkBalanceResponse(
                        spendableSat: model.spendableSat,
                        pendingLightningSendSat: model.pendingLightningSendSat,
                        pendingInRoundSat: model.pendingInRoundSat,
                        pendingExitSat: model.pendingExitSat,
                        pendingBoardSat: model.pendingBoardSat
                    )
                },
                onchainBalance: onchainBalance
            ),
            transactions: transactions.map { WalletExportData.ExportTransactionData(from: $0) },
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


