//
//  BarkWalletFFI+Balance.swift
//  Arke
//
//  Balance and address operations for Ark and onchain wallets
//  Handles balance retrieval and address generation
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - Ark Balance & Address
    
    func getArkBalance() async throws -> ArkBalanceResponse {
        // Preview mode handling
        if isPreview {
            return ArkBalanceResponse(
                spendableSat: 50000,
                pendingLightningSendSat: 0,
                pendingInRoundSat: 0,
                pendingExitSat: 0,
                pendingBoardSat: 0
            )
        }
        
        // Log wallet initialization status
        Self.logger.debug("Wallet initialized: \(self.wallet != nil) at \(Date())")
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Fetching balance via FFI")
        
        do {
            // Call FFI balance method
            let ffiBalance = try await wallet.balance()
            
            Self.logger.info("Balance retrieved - Spendable: \(ffiBalance.spendableSats) sats")
            Self.logger.debug("Pending Lightning Send: \(ffiBalance.pendingLightningSendSats) sats")
            Self.logger.debug("Pending in round: \(ffiBalance.pendingInRoundSats) sats")
            Self.logger.debug("Pending exit: \(ffiBalance.pendingExitSats) sats")
            Self.logger.debug("Pending board: \(ffiBalance.pendingBoardSats) sats")
            
            // Convert FFI Balance to ArkBalanceResponse
            let response = ArkBalanceResponse(
                spendableSat: Int(ffiBalance.spendableSats),
                pendingLightningSendSat: Int(ffiBalance.pendingLightningSendSats),
                pendingInRoundSat: Int(ffiBalance.pendingInRoundSats),
                pendingExitSat: Int(ffiBalance.pendingExitSats),
                pendingBoardSat: Int(ffiBalance.pendingBoardSats)
            )
            
            return response
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error fetching balance: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get balance: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error fetching balance: \(error)")
            throw error
        }
    }
    
    func getArkAddress() async throws -> String {
        // Log call stack to trace where this is being called from
#if DEBUG
        Self.logger.debug("[ADDRESS TRACE] getArkAddress() CALLED")
        // Note: Ark addresses can be safely reused without privacy concerns.
        // The Rust wallet manages address derivation and tracks all previously
        // generated addresses for incoming payment detection.
        Self.logger.debug("Call stack:")
        Thread.callStackSymbols.prefix(6).enumerated().forEach { index, symbol in
            Self.logger.debug("  \(index): \(symbol)")
        }
#endif
        
        // Preview mode handling
        if isPreview {
            return "ark1preview0000000000000000000000000000000000000000000000000000000"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Generating new address via FFI")
        Self.logger.debug("Current wallet state - Wallet exists: \(self.wallet != nil), Server: \(self.config.serverAddress), Esplora: \(self.config.esploraAddress ?? "nil")")
        
        // Try to get server info first to diagnose connection
        Self.logger.debug("Attempting to fetch server info before address generation")
        if let arkInfo = await wallet.arkInfo() {
            Self.logger.debug("Server connected! ArkInfo available - Round interval: \(arkInfo.roundIntervalSecs)s, VTXO expiry: \(arkInfo.vtxoExpiryDelta) blocks")
        } else {
            Self.logger.warning("Cannot fetch ArkInfo (returns nil - server may not be connected). This explains why address generation will fail")
        }
        
        do {
            // Call FFI newAddressWithIndex method to get address with index
            let addressWithIndex = try await wallet.newAddressWithIndex()
            
            Self.logger.info("New address generated - Address: \(addressWithIndex.address), Index: \(addressWithIndex.index)")
            
            return addressWithIndex.address
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error generating address: \(error)")
            Self.logger.debug("BarkError details - Type: \(type(of: error)), Description: \(error.localizedDescription)")
            
            // Check if this looks like a connection error. Bark 0.11 collapsed the
            // granular error cases into `.Inner(message:)`, so inspect the message.
            if case .Inner(let message) = error,
               message.localizedCaseInsensitiveContains("connect") || message.localizedCaseInsensitiveContains("server") {
                Self.logger.debug("Likely a server connection error - Message: \(message)")
                Self.logger.debug("Hint: The Rust wallet may need an explicit connection step or is still initializing the network.")
            }
            
            throw BarkWalletFFIError.configurationError("Failed to generate address: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error generating address: \(error)")
            throw error
        }
    }
    
    // MARK: - Onchain Balance & Address
    
    func getOnchainAddress() async throws -> String {
        // Get a Bitcoin onchain address from the BDK onchain wallet
        
        if isPreview {
            return "tb1preview00000000000000000000000000000000000000000000"
        }
        
        // Ensure onchain wallet is initialized
        guard let onchainWallet = onchainWallet else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }
        
        Self.logger.debug("Generating onchain address from built-in wallet")
        
        do {
            // Get address from built-in OnchainWallet
            let address = try await onchainWallet.newAddress()
            
            Self.logger.info("Onchain address generated: \(address)")
            
            return address
            
        } catch {
            Self.logger.error("Error generating onchain address: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to generate onchain address: \(error.localizedDescription)")
        }
    }
    
    func getOnchainBalance() async throws -> OnchainBalanceResponse {
        // Get onchain Bitcoin balance from the BDK wallet
        // This waits for initial sync to complete to avoid returning stale data
        
        if isPreview {
            return OnchainBalanceResponse(
                totalSat: 0,
                confirmedSat: 0,
                pendingSat: 0
            )
        }
        
        // Ensure onchain wallet is initialized
        guard let onchainWallet = onchainWallet else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }
        
        Self.logger.debug("Fetching onchain balance via FFI")
        
        do {
            // Call built-in wallet's balance method
            let ffiBalance = try await onchainWallet.balance()
            
            Self.logger.info("Onchain balance retrieved - Total: \(ffiBalance.totalSats) sats")
            Self.logger.debug("Confirmed: \(ffiBalance.confirmedSats) sats, Pending: \(ffiBalance.pendingSats) sats")
            
            // Convert FFI OnchainBalance to OnchainBalanceResponse (direct 1:1 mapping)
            let response = OnchainBalanceResponse(
                totalSat: Int(ffiBalance.totalSats),
                confirmedSat: Int(ffiBalance.confirmedSats),
                pendingSat: Int(ffiBalance.pendingSats)
            )
            
            return response
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error fetching onchain balance: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get onchain balance: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error fetching onchain balance: \(error)")
            throw error
        }
    }
}
