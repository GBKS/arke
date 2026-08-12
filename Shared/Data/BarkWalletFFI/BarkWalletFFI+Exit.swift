//
//  BarkWalletFFI+Exit.swift
//  Arke
//
//  Unilateral exit system for emergency fund recovery
//  Handles exit lifecycle: start, progress, sync, drain, and status
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - Exit Offboarding
    
    func exitVTXO(vtxo_id: String, to address: String) async throws -> String {
        // Exit (offboard) a specific VTXO to a Bitcoin address
        
        if isPreview {
            return "Mock: Exited VTXO \(vtxo_id) to \(address) (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Offboarding specific VTXO via FFI, VTXO ID: \(vtxo_id), Destination: \(address)")
        
        do {
            // Call FFI offboardVtxos with single VTXO ID
            let result = try await wallet.offboardVtxos(vtxoIds: [vtxo_id], bitcoinAddress: address)

            Self.logger.info("VTXO offboard initiated, Txid: \(result.txid)")

            return "VTXO offboard initiated. Txid: \(result.txid)"
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error offboarding VTXO: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to offboard VTXO: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error offboarding VTXO: \(error)")
            throw error
        }
    }
    
    /*
    // Legacy version without address parameter (for compatibility)
    func exitVTXO(vtxo_id: String) async throws -> String {
        print("⚠️ exitVTXO: Requires Bitcoin address for offboarding")
        print("   Use exitVTXO(vtxo_id:to:) with a destination address")
        
        throw BarkWalletFFIError.notSupported("exitVTXO requires a Bitcoin address. Use exitVTXO(vtxo_id:to:address) instead.")
    }
    */
    
    // MARK: - Exit Lifecycle
    
    func startExit() async throws -> String {
        // Start unilateral exit process for entire wallet
        
        if isPreview {
            return "Mock: Started exit process (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Starting unilateral exit for entire wallet via FFI...")
        
        do {
            // Call FFI startExitForEntireWallet method
            try await wallet.startExitForEntireWallet()
            
            Self.logger.info("Unilateral exit started for entire wallet, NOTE: Call progressExits() periodically to advance the exit process, Exit requires an OnchainWallet to broadcast transactions")
            
            return "Unilateral exit started for entire wallet. Call progressExits() to advance the process."
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error starting exit: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to start exit: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error starting exit: \(error)")
            throw error
        }
    }
    
    // Additional method to start exit for specific VTXOs
    func startExitForVTXOs(vtxo_ids: [String]) async throws -> String {
        // Start unilateral exit for specific VTXOs
        
        if isPreview {
            return "Mock: Started exit for \(vtxo_ids.count) VTXOs (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Starting unilateral exit for specific VTXOs via FFI, VTXO count: \(vtxo_ids.count)")
        
        do {
            // Call FFI startExitForVtxos method
            try await wallet.startExitForVtxos(vtxoIds: vtxo_ids)
            
            Self.logger.info("Unilateral exit started for \(vtxo_ids.count) VTXOs, NOTE: Call progressExits() periodically to advance the exit process")
            
            return "Unilateral exit started for \(vtxo_ids.count) VTXOs. Call progressExits() to advance."
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error starting exit: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to start exit: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error starting exit: \(error)")
            throw error
        }
    }
    
    /// Debug function to diagnose exit broadcast failures
    /// Checks UTXO state, exit status, and potential double-spend scenarios
    private func debugExitFailures(statuses: [ExitProgressStatus]) async {
        Self.logger.debug("[EXIT DEBUG] Analyzing exit failures...")
        
        guard let wallet = wallet else {
            Self.logger.warning("Wallet not initialized")
            return
        }
        
        // Filter for failed exits
        let failedExits = statuses.filter { $0.error != nil }
        
        if failedExits.isEmpty {
            Self.logger.info("No failed exits to debug")
            return
        }
        
        Self.logger.debug("Found \(failedExits.count) failed exit(s)")
        
        for (index, status) in failedExits.enumerated() {
            Self.logger.debug("Failed Exit #\(index + 1): VTXO ID: \(status.vtxoId), State: \(String(describing: status.state)), Error: \(status.error ?? "unknown")")
            
            // Get detailed exit status
            do {
                if let exitStatus = try await wallet.getExitStatus(
                    vtxoId: status.vtxoId,
                    includeHistory: true,
                    includeTransactions: true
                ) {
                    Self.logger.debug("Detailed Exit Status: State: \(String(describing: exitStatus.state)), Transaction count: \(exitStatus.transactionCount)")
                    
                    // Check if error message contains transaction IDs
                    if let errorMsg = status.error {
                        // Check if it's a bad-txns-inputs-missingorspent error
                        if errorMsg.contains("bad-txns-inputs-missingorspent") {
                            Self.logger.debug("Diagnosis: Input UTXOs are missing or already spent, Possible causes: 1. Parent VTXO was consumed in an ASP round, 2. Chain reorganization invalidated the input, 3. UTXO was double-spent elsewhere")
                            
                            // Extract parent transaction IDs from error message
                            Self.logger.debug("Extracting transaction IDs from error message")
                            let diagnostics = ExitDiagnostics(esploraURL: config.esploraAddress ?? networkConfig.esploraBaseURL)
                            await diagnostics.extractAndAnalyzeTransactionIds(from: errorMsg)
                        }
                        
                        // Extract transaction IDs from error message if present
                        if errorMsg.contains("tx ") {
                            Self.logger.debug("Raw error message contains transaction references")
                            // Split by common delimiters and look for hex patterns
                            let words = errorMsg.split(whereSeparator: { " ,;:[]()".contains($0) })
                            for word in words {
                                let wordStr = String(word)
                                // Bitcoin txids are 64-character hex strings
                                if wordStr.count == 64 && wordStr.allSatisfy({ $0.isHexDigit }) {
                                    Self.logger.debug("Potential txid: \(wordStr.prefix(8))...\(wordStr.suffix(8))")
                                }
                            }
                        }
                    }
                    
                    if let history = exitStatus.history, !history.isEmpty {
                        Self.logger.debug("State history (\(history.count) entries): \(history.prefix(5).map { String(describing: $0) }.joined(separator: ", "))\(history.count > 5 ? " ... (\(history.count - 5) more)" : "")")
                    }
                    
                    // Try to extract transaction information if available
                    // Note: The actual transaction data structure depends on Bark FFI implementation
                    Self.logger.debug("Transaction details (\(exitStatus.transactionCount) transaction(s)): [TODO: Access transaction hex/structure from ExitTransactionStatus, Parse transaction inputs and outputs, For each input, extract prevout (txid:vout)]")
                } else {
                    Self.logger.warning("Could not get detailed exit status (returned nil)")
                }
            } catch {
                Self.logger.error("Error getting exit status: \(error)")
            }
            
            // Try to get VTXO information to understand the transaction graph
            do {
                print("\n      🔗 VTXO Information:")
                let vtxo = try await wallet.getVtxoById(vtxoId: status.vtxoId)
                print("         ID: \(vtxo.id)")
                print("         Amount: \(vtxo.amountSats) sats")
                print("         State: \(vtxo.state)")
                print("         Expiry: \(vtxo.expiryHeight)")
                
                // Parse the VTXO ID which is in outpoint format (txid:vout)
                let diagnostics = ExitDiagnostics(esploraURL: config.esploraAddress ?? networkConfig.esploraBaseURL)
                await diagnostics.analyzeVtxoOutpoint(vtxoId: status.vtxoId)
            } catch {
                print("         ❌ Error getting VTXO: \(error)")
                print("         (VTXO may have been removed from wallet state)")
            }
        }
        
        // Check overall wallet state
        print("\n   📊 Overall Wallet State:")
        do {
            let spendableVtxos = try await wallet.spendableVtxos()
            print("      Spendable VTXOs: \(spendableVtxos.count)")
            
            let exitVtxos = try await wallet.getExitVtxos()
            print("      VTXOs in exit process: \(exitVtxos.count)")
            
            let pendingExitsTotal = try await wallet.pendingExitsTotalSats()
            print("      Pending exits total: \(pendingExitsTotal) sats")
            
            // Check if any exits are claimable
            let claimableExits = try await wallet.listClaimableExits()
            print("      Claimable exits: \(claimableExits.count)")
            
        } catch {
            print("      ❌ Error checking wallet state: \(error)")
        }
        
        print("\n   💡 Recommendation:")
        if failedExits.allSatisfy({ $0.error?.contains("bad-txns-inputs-missingorspent") == true }) {
            print("      All failures are due to missing/spent inputs.")
            print("      These VTXOs may have been consumed in ASP rounds.")
            print("      Consider canceling these exits if they cannot proceed.")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }
    
    func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus] {
        // Progress unilateral exits (broadcast, fee bump, advance state machine)
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        guard onchainWallet != nil else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }

        Self.logger.debug("Progressing exits via FFI...")

        do {
            let statuses = try await wallet.progressExits(feeRateSatPerVb: feeRateSatPerVb)
            
            Self.logger.info("Progressed \(statuses.count) exits")
            for status in statuses {
                if let error = status.error {
                    Self.logger.debug("VTXO \(status.vtxoId): \(String(describing: status.state)), Error: \(error)")
                } else {
                    Self.logger.debug("VTXO \(status.vtxoId): \(String(describing: status.state))")
                }
            }
            
            // Run diagnostics if any exits failed
            let hasErrors = statuses.contains { $0.error != nil }
            if hasErrors {
                await debugExitFailures(statuses: statuses)
            }
            
            return statuses
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error progressing exits: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to progress exits: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error progressing exits: \(error)")
            throw error
        }
    }
    
    // MARK: - Exit Claiming
    
    func syncExits() async throws {
        // Sync exit state (checks status but doesn't progress)
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        guard onchainWallet != nil else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }

        Self.logger.debug("Syncing exits via FFI...")

        do {
            try await wallet.syncExits()
            Self.logger.info("Exits synced")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error syncing exits: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to sync exits: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error syncing exits: \(error)")
            throw error
        }
    }

    func syncForceExitedVtxos() async throws {
        // Sync the state of VTXOs that have been force-exited (unilateral exit)

        if isPreview {
            return
        }

        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        Self.logger.debug("Syncing force-exited VTXOs via FFI...")

        do {
            try await wallet.syncForceExitedVtxos()
            Self.logger.info("Force-exited VTXOs synced")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error syncing force-exited VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to sync force-exited VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error syncing force-exited VTXOs: \(error)")
            throw error
        }
    }

    func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction {
        // Drain claimable exits to an address
        
        if isPreview {
            return ExitClaimTransaction(psbtBase64: "mock_psbt", feeSats: 1000)
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Draining exits via FFI, VTXO count: \(vtxoIds.isEmpty ? "all" : "\(vtxoIds.count)"), Destination: \(address)")
        
        do {
            let claimTx = try await wallet.drainExits(vtxoIds: vtxoIds, address: address, feeRateSatPerVb: feeRateSatPerVb)
            
            Self.logger.info("Exit claim transaction created, Fee: \(claimTx.feeSats) sats")
            
            return claimTx
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error draining exits: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to drain exits: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error draining exits: \(error)")
            throw error
        }
    }
    
    // MARK: - Exit Claiming
    
    func listClaimableExits() async throws -> [ExitVtxo] {
        // List all exits that are claimable
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let exits = try await wallet.listClaimableExits()
            Self.logger.info("Retrieved \(exits.count) claimable exits")
            return exits
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error listing claimable exits: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to list claimable exits: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error listing claimable exits: \(error)")
            throw error
        }
    }
    
    func getExitVtxos() async throws -> [ExitVtxo] {
        // Get all VTXOs currently in exit process
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let exits = try await wallet.getExitVtxos()
            Self.logger.info("Retrieved \(exits.count) VTXOs in exit process")
            return exits
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting exit VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get exit VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting exit VTXOs: \(error)")
            throw error
        }
    }
    
    // MARK: - Exit Status & Queries
    
    func hasPendingExits() async throws -> Bool {
        // Check if any exits are pending
        
        if isPreview {
            return false
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.hasPendingExits()
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error checking pending exits: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to check pending exits: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error checking pending exits: \(error)")
            throw error
        }
    }
    
    func pendingExitsTotalSats() async throws -> UInt64 {
        // Get total amount in pending exits (sats)
        
        if isPreview {
            return 0
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.pendingExitsTotalSats()
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting pending exits total: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get pending exits total: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting pending exits total: \(error)")
            throw error
        }
    }
    
    func getExitStatus(vtxoId: String, includeHistory: Bool, includeTransactions: Bool) async throws -> ExitTransactionStatus? {
        // Get detailed exit status for a specific VTXO
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.getExitStatus(vtxoId: vtxoId, includeHistory: includeHistory, includeTransactions: includeTransactions)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting exit status: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get exit status: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting exit status: \(error)")
            throw error
        }
    }
    
    func allExitsClaimableAtHeight() async throws -> UInt32? {
        // Get earliest block height when all exits will be claimable
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.allExitsClaimableAtHeight()
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting claimable height: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get claimable height: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting claimable height: \(error)")
            throw error
        }
    }
}
