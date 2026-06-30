//
//  BarkWalletFFI+VTXO.swift
//  Arke
//
//  VTXO management: retrieval, boarding, refresh, and advanced queries
//  Handles onchain to Ark conversion and VTXO lifecycle operations
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import ArkeUI
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - VTXO Retrieval
    
    func getVTXOs() async throws -> [VTXOModel] {
        // Preview mode handling
        if isPreview {
            return VTXOModel.mockVTXOs()
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Fetching VTXOs via FFI...")
        
        do {
            // Call FFI vtxos method
            let ffiVtxos = try await wallet.vtxos()
            
            Self.logger.info("Retrieved \(ffiVtxos.count) VTXOs")
            Self.logger.debug("VTXOs: \(ffiVtxos)")
            
            // Convert FFI Vtxo array to VTXOModel array
            let vtxoModels = ffiVtxos.map { ffiVtxo -> VTXOModel in
                // Map FFI state string to our VTXOState enum
                let state = mapFFIStateToVTXOState(ffiVtxo.state)
                
                // Map FFI kind to our VTXOKind enum
                let kind = mapFFIKindToVTXOKind(ffiVtxo.kind)
                
                // VTXOModel now directly matches FFI Vtxo fields
                return VTXOModel(
                    id: ffiVtxo.id,
                    amountSat: Int(ffiVtxo.amountSats),
                    expiryHeight: Int(ffiVtxo.expiryHeight),
                    kind: kind,
                    state: state,
                    exitDepth: ffiVtxo.exitDepth,
                    exitTxWeightWu: ffiVtxo.exitTxWeightWu
                )
            }
            
            // Log summary
            for (index, vtxo) in vtxoModels.enumerated() {
                Self.logger.debug("VTXO \(index): \(vtxo.shortId), \(vtxo.amountSat) sats, \(vtxo.state.rawValue)")
            }
            
            return vtxoModels
            
        } catch let error as BarkError {
            Self.logger.error("FFI Error fetching VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error fetching VTXOs: \(error)")
            throw error
        }
    }
    
    func getUTXOs() async throws -> [UTXOModel] {
        // Note: FFI layer doesn't expose UTXOs separately
        // This functionality may not be available in the Rust wallet API
        
        if isPreview {
            return []
        }
        
        Self.logger.warning("getUTXOs: Not available in FFI layer, FFI wallet manages UTXOs internally")
        
        // Return empty array
        return []
    }
    
    func refreshVtxosDelegated(vtxoIds: [String]) async throws -> RoundState? {
        // Refreshes specific VTXOs in delegated mode without blocking
        // Returns the round state if a refresh was scheduled, nil otherwise
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Scheduling delegated VTXO refresh via FFI, VTXO IDs: \(vtxoIds)")
        
        do {
            let roundState = try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
            
            if let roundState = roundState {
                Self.logger.info("Delegated VTXO refresh scheduled, Round ID: \(roundState.id)")
            } else {
                Self.logger.info("No refresh needed for specified VTXOs")
            }
            
            return roundState
        } catch let error as BarkError {
            Self.logger.error("FFI Error scheduling delegated VTXO refresh: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to schedule delegated VTXO refresh: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error scheduling delegated VTXO refresh: \(error)")
            throw error
        }
    }
    
    /*
    // Disabling since we always want delegated refreshes in the app
    func refreshVTXOs(vtxo_ids: [String]) async throws -> String {
        // Refresh all VTXOs using maintenance
        
        if isPreview {
            return "Mock: Refreshed all VTXOs (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Running maintenance to refresh VTXOs via FFI, VTXO IDs: \(vtxo_ids)")
        
        do {
            // Call FFI maintenance method
            // This handles VTXO refresh and other maintenance tasks
            let refreshResult = try await wallet.refreshVtxos(vtxoIds: vtxo_ids)
            
            Self.logger.debug("refreshResult \(refreshResult ?? "nil")")
            Self.logger.info("Maintenance completed successfully, VTXOs have been refreshed")
            
            return "Successfully refreshed VTXOs via maintenance"
            
        } catch let error as BarkError {
            Self.logger.error("FFI Error during maintenance: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to refresh VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error during maintenance: \(error)")
            throw error
        }
    }
    */
    
    // MARK: - VTXO Refresh
    // Disabling since we always want delegated refreshes in the app
    /*
    func refreshVTXO(vtxo_id: String) async throws -> String {
        // Refresh a specific VTXO
        
        if isPreview {
            return "Mock: Refreshed VTXO \(vtxo_id) (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Refreshing specific VTXO via FFI, VTXO ID: \(vtxo_id)")
        
        do {
            // Call FFI refreshVtxos with single VTXO ID
            let roundId = try await wallet.refreshVtxos(vtxoIds: [vtxo_id])
            
            if let roundId = roundId {
                Self.logger.info("VTXO refresh initiated, Round ID: \(roundId)")
                return "VTXO refresh initiated. Round ID: \(roundId)"
            } else {
                Self.logger.info("VTXO does not need refresh")
                return "VTXO does not need refresh at this time"
            }
            
        } catch let error as BarkError {
            Self.logger.error("FFI Error refreshing VTXO: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to refresh VTXO: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error refreshing VTXO: \(error)")
            throw error
        }
    }
    */
    
    // MARK: - Boarding (Onchain to Ark)
    
    func board(amount: Int) async throws {
        // "Board" means bringing onchain Bitcoin into Ark
        // This sends onchain Bitcoin funds into the Ark protocol
        
        if isPreview {
            Self.logger.info("Mock: Boarding \(amount) sats (preview mode)")
            return
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        // Ensure onchain wallet is initialized
        guard let onchainWallet = onchainWallet else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }
        
        // Validate amount
        guard amount > 0 else {
            throw BarkWalletFFIError.configurationError("Amount must be greater than 0")
        }
        
        // Convert Int to UInt64 for FFI
        let amountSats = UInt64(amount)
        
        Self.logger.debug("Boarding \(amount) sats via FFI, Converting onchain Bitcoin to Ark VTXOs")
        
        do {
            // Call FFI boardAmount method
            let roundId = try await wallet.boardAmount(onchainWallet: onchainWallet, amountSats: amountSats)
            
            Self.logger.info("Board transaction initiated, VTXO ID: \(roundId.vtxoId), Amount: \(amount) sats, Txid: \(roundId.txid), Waiting for confirmations...")
            
        } catch let error as BarkError {
            Self.logger.error("FFI Error boarding funds: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to board funds: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error boarding funds: \(error)")
            throw error
        }
    }
    
    func boardAll() async throws -> String {
        // Board all available onchain funds into Ark
        
        if isPreview {
            return "Mock: Boarding all funds (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        // Ensure onchain wallet is initialized
        guard let onchainWallet = onchainWallet else {
            throw BarkWalletFFIError.configurationError("Onchain wallet not initialized")
        }
        
        Self.logger.debug("Boarding all available onchain funds via FFI...")
        
        do {
            // Call FFI boardAll method
            let roundId = try await wallet.boardAll(onchainWallet: onchainWallet)
            
            Self.logger.info("Board all transaction initiated, VTXO ID: \(roundId.vtxoId), Txid: \(roundId.txid), All available onchain funds being boarded...")
            
            return "Successfully initiated boarding all funds. VTXO ID: \(roundId.vtxoId), Txid: \(roundId.txid)"
            
        } catch let error as BarkError {
            Self.logger.error("FFI Error boarding all funds: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to board all funds: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error boarding all funds: \(error)")
            throw error
        }
    }
    
    // MARK: - Advanced VTXO Operations (New in FFI)
    
    func allVtxos() async throws -> [Vtxo] {
        // Get all VTXOs (including spent)
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let vtxos = try await wallet.allVtxos()
            Self.logger.info("Retrieved \(vtxos.count) VTXOs (all)")
            return vtxos
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting all VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get all VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting all VTXOs: \(error)")
            throw error
        }
    }
    
    func spendableVtxos() async throws -> [Vtxo] {
        // Get only spendable VTXOs
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let vtxos = try await wallet.spendableVtxos()
            Self.logger.info("Retrieved \(vtxos.count) spendable VTXOs")
            return vtxos
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting spendable VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get spendable VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting spendable VTXOs: \(error)")
            throw error
        }
    }
    
    func getExpiringVtxos(thresholdBlocks: UInt32) async throws -> [Vtxo] {
        // Get VTXOs expiring within threshold blocks
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let vtxos = try await wallet.getExpiringVtxos(thresholdBlocks: thresholdBlocks)
            Self.logger.info("Retrieved \(vtxos.count) expiring VTXOs (within \(thresholdBlocks) blocks)")
            return vtxos
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting expiring VTXOs: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get expiring VTXOs: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting expiring VTXOs: \(error)")
            throw error
        }
    }
    
    func getVtxosToRefresh() async throws -> [Vtxo] {
        // Get VTXOs that should be refreshed
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let vtxos = try await wallet.getVtxosToRefresh()
            Self.logger.info("Retrieved \(vtxos.count) VTXOs needing refresh")
            return vtxos
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting VTXOs to refresh: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get VTXOs to refresh: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting VTXOs to refresh: \(error)")
            throw error
        }
    }
    
    func getVtxoById(vtxoId: String) async throws -> Vtxo {
        // Get a specific VTXO by ID
        
        if isPreview {
            return Vtxo(id: vtxoId, amountSats: 10000, expiryHeight: 0, kind: "mock", state: "spendable", exitDepth: 1, exitTxWeightWu: 500)
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.getVtxoById(vtxoId: vtxoId)
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting VTXO by ID: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get VTXO by ID: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting VTXO by ID: \(error)")
            throw error
        }
    }
    
    func getFirstExpiringVtxoBlockheight() async throws -> UInt32? {
        // Get the block height of the first expiring VTXO
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.getFirstExpiringVtxoBlockheight()
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting first expiring VTXO height: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get first expiring VTXO height: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting first expiring VTXO height: \(error)")
            throw error
        }
    }
    
    func getNextRequiredRefreshBlockheight() async throws -> UInt32? {
        // Get the next block height when a refresh should be performed
        
        if isPreview {
            return nil
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.getNextRequiredRefreshBlockheight()
        } catch let error as BarkError {
            Self.logger.error("FFI Error getting next refresh height: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get next refresh height: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting next refresh height: \(error)")
            throw error
        }
    }
    
    func importVtxo(vtxoBase64: String) async throws {
        // Import a serialized VTXO into the wallet
        
        if isPreview {
            Self.logger.info("Preview mode - skipping VTXO import")
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Importing VTXO via FFI, VTXO data length: \(vtxoBase64.count) chars")
        
        do {
            try await wallet.importVtxo(vtxoBase64: vtxoBase64)
            Self.logger.info("VTXO imported successfully")
        } catch let error as BarkError {
            Self.logger.error("FFI Error importing VTXO: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to import VTXO: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error importing VTXO: \(error)")
            throw error
        }
    }
    
    // MARK: - Type Mapping Helpers
    
    /// Map FFI VTXO kind string to our VTXOKind enum
    private func mapFFIKindToVTXOKind(_ kindString: String) -> VTXOKind {
        // FFI kinds from Rust: "board", "round", "arkoor", "pubkey", "checkpoint", 
        // "server-htlc-send", "server-htlc-receive", "expiry"
        
        switch kindString.lowercased() {
        case "board":
            return .board
        case "round":
            return .round
        case "arkoor":
            return .arkoor
        case "pubkey":
            return .pubkey
        case "checkpoint":
            return .checkpoint
        case "server-htlc-send", "serverhtlcsend":
            return .serverHTLCSend
        case "server-htlc-receive", "serverhtlcreceive":
            return .serverHTLCRecv
        case "expiry":
            return .expiry
        default:
            Self.logger.warning("Unknown VTXO kind: '\(kindString)', defaulting to pubkey")
            return .pubkey
        }
    }
    
    /// Map FFI VTXO state string to our VTXOState enum
    private func mapFFIStateToVTXOState(_ stateString: String) -> VTXOState {
        // FFI states: "spendable", "spent", "locked", etc.
        // Our states: unregisteredBoard, registeredBoard, spent, pending, spendable, locked
        
        switch stateString.lowercased() {
        case "spendable":
            return .spendable
        case "spent":
            return .spent
        case "locked":
            return .locked
        case "pending":
            return .pending
        default:
            // If we can't map it, default to pending
            Self.logger.warning("Unknown VTXO state: '\(stateString)', defaulting to pending")
            return .pending
        }
    }
}
