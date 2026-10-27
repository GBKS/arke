//
//  AddressService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import SwiftData

/// Service responsible for managing wallet addresses (Ark and onchain)
/// Now includes address history tracking, gap limit enforcement, and internal transfer detection
@MainActor
@Observable
class AddressService {
    
    // MARK: - Properties
    
    /// Current Ark address (cached for quick access)
    var arkAddress: String = ""
    
    /// Current onchain address (cached for quick access)
    var onchainAddress: String = ""
    
    /// Error message if address operations fail
    var error: String?
    
    // MARK: - Private Properties
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private let modelContext: ModelContext
    
    // MARK: - Constants
    
    /// Maximum number of unused onchain addresses (BIP44 gap limit)
    private static let maxUnusedOnchainAddresses = 20
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager, modelContext: ModelContext) {
        self.wallet = wallet
        self.taskManager = taskManager
        self.modelContext = modelContext

        // Publish the saved history right away. The service is created in
        // `setModelContext`, before the wallet opens; `loadAddresses()` only
        // runs at Step 3 of the launch refresh, behind the onchain sync, so
        // the receive screen showed a spinner for the whole sync although
        // the rows were already local (2026-10-27). This is a database read
        // only — the bark reveal that contract rule 7 orders before the
        // onchain history read still happens in Step 3, which overwrites
        // these values if the sync marked the onchain address used.
        updateCachedAddresses()
    }
    
    // MARK: - Public Methods
    
    /// Load both Ark and onchain addresses with task deduplication
    /// Now uses address history instead of always generating new addresses
    func loadAddresses() async {
        #if DEBUG
        print("📍 [ADDRESS TRACE] AddressService.loadAddresses() CALLED")
        print("   📞 Call stack:")
        Thread.callStackSymbols.prefix(6).enumerated().forEach { index, symbol in
            print("      \(index): \(symbol)")
        }
        #endif
        
        await taskManager.execute(key: "addresses") {
            await self.performLoadAddresses()
        }
    }
    
    /// Refresh addresses by reloading them
    func refreshAddresses() async {
        await loadAddresses()
    }
    
    /// Clear any cached addresses (useful for wallet reset scenarios)
    func clearAddresses() {
        arkAddress = ""
        onchainAddress = ""
        error = nil
    }
    
    // MARK: - Address Retrieval (New API)
    
    /// Get the current address to show for receiving funds
    /// Returns existing unused address or generates new one (respecting gap limit)
    func getCurrentReceiveAddress(type: AddressType) async throws -> PersistentAddress {
        switch type {
        case .ark:
            // For Ark: Return most recent address (can be reused)
            if let existing = getMostRecentArkAddress() {
                return existing
            }
            // No Ark address exists, generate first one
            return try await generateNewAddress(type: .ark, strategy: .auto)
            
        case .onchain:
            // For onchain: Return most recent unused address
            if let existing = getUnusedOnchainAddress() {
                return existing
            }
            // No unused address, need to generate new one (check gap limit)
            let unusedCount = getUnusedAddressCountSync(type: .onchain)
            if unusedCount >= Self.maxUnusedOnchainAddresses {
                throw AddressError.gapLimitExceeded(unusedCount: unusedCount)
            }
            return try await generateNewAddress(type: .onchain, strategy: .auto)
        }
    }
    
    /// Generate a new address (user explicitly requested)
    func generateNewAddress(type: AddressType, strategy: AddressGenerationStrategy = .userRequested) async throws -> PersistentAddress {
        // For onchain, check gap limit before generating
        if type == .onchain && strategy == .userRequested {
            let unusedCount = getUnusedAddressCountSync(type: .onchain)
            if unusedCount >= Self.maxUnusedOnchainAddresses {
                throw AddressError.gapLimitExceeded(unusedCount: unusedCount)
            }
        }
        
        // Generate new address from wallet
        let addressString: String
        let derivationIndex: Int?
        
        switch type {
        case .ark:
            addressString = try await wallet.getArkAddress()
            derivationIndex = nil  // Ark doesn't use BIP44 derivation
            print("✅ Generated new Ark address: \(addressString)")
            
        case .onchain:
            addressString = try await wallet.getOnchainAddress()
            // Calculate derivation index based on existing addresses
            derivationIndex = getNextDerivationIndex()
            print("✅ Generated new onchain address: \(addressString) (index: \(derivationIndex ?? -1))")
        }
        
        // Check for duplicates
        if isAddressInDatabase(addressString) {
            throw AddressError.duplicateAddress(addressString)
        }
        
        // Create and save to database
        let persistentAddress = PersistentAddress(
            address: addressString,
            addressType: type,
            generatedAt: Date(),
            derivationIndex: derivationIndex,
            generatedBy: strategy
        )
        
        modelContext.insert(persistentAddress)
        try modelContext.save()
        
        // Update cached values
        updateCachedAddresses()
        
        return persistentAddress
    }
    
    // MARK: - Internal Address Management
    
    /// Mark address as used when transaction is detected
    func markAddressAsUsed(address: String, transaction: PersistentTransaction?) async {
        guard let persistentAddress = await getAddressByString(address) else {
            print("⚠️ Address not found in database: \(address)")
            return
        }
        
        // Update usage statistics
        persistentAddress.isUsed = true
        persistentAddress.receivedTransactionCount += 1
        
        if persistentAddress.firstUsedAt == nil {
            persistentAddress.firstUsedAt = Date()
        }
        persistentAddress.lastUsedAt = Date()
        
        if let transaction = transaction {
            persistentAddress.totalReceivedSats += transaction.amount
        }
        
        do {
            try modelContext.save()
            print("✅ Marked address as used: \(address)")
        } catch {
            print("❌ Failed to mark address as used: \(error)")
        }
    }
    
    /// Check if an address belongs to this wallet
    func isOwnAddress(_ address: String) async -> Bool {
        return isAddressInDatabase(address)
    }
    
    /// Get all addresses (for internal use or settings display)
    func getAllAddresses(type: AddressType? = nil) async -> [PersistentAddress] {
        let descriptor: FetchDescriptor<PersistentAddress>
        
        if let type = type {
            descriptor = FetchDescriptor<PersistentAddress>(
                predicate: #Predicate<PersistentAddress> { address in
                    address.addressType == type.rawValue && address.isActive
                },
                sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<PersistentAddress>(
                predicate: #Predicate<PersistentAddress> { address in
                    address.isActive
                },
                sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
            )
        }
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get unused address count (for gap limit monitoring)
    func getUnusedAddressCount(type: AddressType) async -> Int {
        return getUnusedAddressCountSync(type: type)
    }
    
    /// Validate we haven't exceeded gap limit
    func validateGapLimit() async throws {
        let unusedCount = getUnusedAddressCountSync(type: .onchain)
        if unusedCount >= Self.maxUnusedOnchainAddresses {
            throw AddressError.gapLimitExceeded(unusedCount: unusedCount)
        }
    }
    
    /// Get address object by string (for transaction linking)
    /// - Parameter address: The address string to look up
    /// - Returns: The PersistentAddress if found, nil otherwise
    func getAddressByString(_ address: String) async -> PersistentAddress? {
        return getAddressByStringSync(address)
    }
    
    // MARK: - Private Methods
    
    /// Perform the actual address loading operations
    /// Now uses address history instead of generating new addresses
    private func performLoadAddresses() async {
        do {
            // Load Ark address from history or generate new
            let arkAddr = try await getCurrentReceiveAddress(type: .ark)
            arkAddress = arkAddr.address
            print("✅ Ark address loaded: \(arkAddress)")
        } catch {
            print("❌ Failed to get Ark address: \(error)")
            self.error = "Failed to get Ark address: \(error)"
        }
        
        do {
            // Load onchain address from history or generate new
            let onchainAddr = try await getCurrentReceiveAddress(type: .onchain)
            onchainAddress = onchainAddr.address
            print("✅ Onchain address loaded: \(onchainAddress)")
        } catch {
            print("❌ Failed to get onchain address: \(error)")
            // Don't overwrite error if we already have one from Ark address
            if self.error == nil {
                self.error = "Failed to get onchain address: \(error)"
            }
        }
        
        // Clear error if both addresses loaded successfully
        if !arkAddress.isEmpty && !onchainAddress.isEmpty {
            error = nil
        }
    }
    
    /// Update cached address values from database
    private func updateCachedAddresses() {
        if let arkAddr = getMostRecentArkAddress() {
            arkAddress = arkAddr.address
        }
        if let onchainAddr = getUnusedOnchainAddress() {
            onchainAddress = onchainAddr.address
        }
    }
    
    // MARK: - Database Query Helpers
    
    /// Get most recent Ark address (can be used or unused)
    private func getMostRecentArkAddress() -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { address in
                address.addressType == "ark" && address.isActive
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Get most recent unused onchain address
    private func getUnusedOnchainAddress() -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { address in
                address.addressType == "onchain" && !address.isUsed && address.isActive
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Check if address exists in database
    private func isAddressInDatabase(_ address: String) -> Bool {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { addr in
                addr.address == address && addr.isActive
            }
        )
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return !results.isEmpty
    }
    
    /// Get address by string (synchronous implementation)
    private func getAddressByStringSync(_ address: String) -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { addr in
                addr.address == address && addr.isActive
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Count unused addresses for gap limit tracking
    private func getUnusedAddressCountSync(type: AddressType) -> Int {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { address in
                address.addressType == type.rawValue && !address.isUsed && address.isActive
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    /// Get next derivation index for onchain address
    private func getNextDerivationIndex() -> Int {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate<PersistentAddress> { address in
                address.addressType == "onchain" && address.isActive
            },
            sortBy: [SortDescriptor(\.derivationIndex, order: .reverse)]
        )
        
        if let highestAddress = try? modelContext.fetch(descriptor).first,
           let highestIndex = highestAddress.derivationIndex {
            return highestIndex + 1
        }
        
        return 0  // First onchain address
    }
}
