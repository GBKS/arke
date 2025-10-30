//
//  AddressService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation

/// Service responsible for managing wallet addresses (Ark and onchain)
@MainActor
@Observable
class AddressService {
    
    // MARK: - Properties
    
    /// Current Ark address
    var arkAddress: String = ""
    
    /// Current onchain address  
    var onchainAddress: String = ""
    
    /// Error message if address operations fail
    var error: String?
    
    // MARK: - Private Properties
    
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    // MARK: - Public Methods
    
    /// Load both Ark and onchain addresses with task deduplication
    func loadAddresses() async {
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
    
    // MARK: - Private Methods
    
    /// Perform the actual address loading operations
    private func performLoadAddresses() async {
        do {
            // Load Ark address
            arkAddress = try await wallet.getArkAddress()
            print("✅ Ark address loaded: \(arkAddress)")
        } catch {
            print("❌ Failed to get Ark address: \(error)")
            self.error = "Failed to get Ark address: \(error)"
        }
        
        do {
            // Load onchain address
            onchainAddress = try await wallet.getOnchainAddress()
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
}