//
//  BarkWalletFFI+Configuration.swift
//  Arke
//
//  Configuration and server information management
//  Provides access to wallet configuration, ASP server info, and network settings
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import ArkeUI
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - Configuration & Server Info
    
    func getConfig() async throws -> ArkConfigModel {
        // Get wallet configuration
        
        if isPreview {
            // Return mock config
            return ArkConfigModel(
                serverAddress: "https://preview.asp.com",
                esploraAddress: "https://preview.esplora.com",
                bitcoindAddress: nil,
                bitcoindCookiefile: nil,
                bitcoindUser: nil,
                bitcoindPass: nil,
                network: "signet",
                vtxoRefreshExpiryThreshold: 144,
                vtxoExitMargin: 512,
                htlcRecvClaimDelta: 72,
                fallbackFeeRate: 10,
                roundTxRequiredConfirmations: 1,
                daemonSyncIntervalSecs: 60,
                offboardRequiredConfirmations: 1,
                daemonManualSync: false,
                lightningReceiveClaimRetries: 3
            )
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Fetching wallet config via FFI...")
        
        // Call FFI config method (doesn't throw)
        let ffiConfig = await wallet.config()
        
        printFullConfig()

        // Convert FFI Network enum to string.
        // `Config` no longer carries the network (Bark 0.11) — use the stored one.
        let networkString = Self.convertFFINetworkToString(self.ffiNetwork)
        
        // Convert FFI Config to ArkConfigModel (1:1 mapping of all fields)
        let configModel = ArkConfigModel(
            serverAddress: ffiConfig.serverAddress,
            esploraAddress: ffiConfig.esploraAddress,
            bitcoindAddress: ffiConfig.bitcoindAddress,
            bitcoindCookiefile: ffiConfig.bitcoindCookiefile,
            bitcoindUser: ffiConfig.bitcoindUser,
            bitcoindPass: ffiConfig.bitcoindPass,
            network: networkString,
            vtxoRefreshExpiryThreshold: ffiConfig.vtxoRefreshExpiryThreshold,
            vtxoExitMargin: ffiConfig.vtxoExitMargin,
            htlcRecvClaimDelta: ffiConfig.htlcRecvClaimDelta,
            fallbackFeeRate: ffiConfig.fallbackFeeRate,
            roundTxRequiredConfirmations: ffiConfig.roundTxRequiredConfirmations,
            daemonSyncIntervalSecs: ffiConfig.daemonSyncIntervalSecs,
            offboardRequiredConfirmations: ffiConfig.offboardRequiredConfirmations,
            daemonManualSync: ffiConfig.daemonManualSync,
            lightningReceiveClaimRetries: ffiConfig.lightningReceiveClaimRetries
        )
        
        return configModel
    }
    
    // MARK: - Helpers
    
    /// Print the entire config object for debugging
    func printFullConfig() {
        let networkString = Self.convertFFINetworkToString(self.ffiNetwork)
        Self.logger.debug("Full Config Object: Server Address: \(self.config.serverAddress), Esplora Address: \(self.config.esploraAddress ?? "nil"), Bitcoind Address: \(self.config.bitcoindAddress ?? "nil"), Bitcoind Cookie File: \(self.config.bitcoindCookiefile ?? "nil"), Bitcoind User: \(self.config.bitcoindUser ?? "nil"), Bitcoind Pass: \(self.config.bitcoindPass != nil ? "[REDACTED]" : "nil"), Network: \(networkString), VTXO Refresh Expiry Threshold: \(self.config.vtxoRefreshExpiryThreshold.map { String($0) } ?? "nil"), VTXO Exit Margin: \(self.config.vtxoExitMargin.map { String($0) } ?? "nil"), HTLC Recv Claim Delta: \(self.config.htlcRecvClaimDelta.map { String($0) } ?? "nil"), Fallback Fee Rate: \(self.config.fallbackFeeRate.map { String($0) } ?? "nil"), Round Tx Required Confirmations: \(self.config.roundTxRequiredConfirmations.map { String($0) } ?? "nil")")
    }
    
    func getArkInfo() async throws -> ArkInfoModel {
        // Get ASP/Ark server information
        
        if isPreview {
            // Create a sample fee schedule for preview
            let sampleFeeSchedule = FeeSchedule(
                board: BoardFeeStructure(minFeeSat: 0, baseFeeSat: 0, ppm: 0),
                offboard: OffboardFeeStructure(
                    baseFeeSat: 0,
                    fixedAdditionalVb: 212,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                ),
                refresh: RefreshFeeStructure(
                    baseFeeSat: 0,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 0),
                        PpmExpiryEntry(expiryBlocksThreshold: 288, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                ),
                lightningReceive: LightningReceiveFeeStructure(baseFeeSat: 0, ppm: 0),
                lightningSend: LightningSendFeeStructure(
                    minFeeSat: 20,
                    baseFeeSat: 0,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                )
            )
            
            return ArkInfoModel(
                network: "signet",
                serverPubkey: "02preview0000000000000000000000000000000000000000000000000000000000",
                roundInterval: "30s",
                nbRoundNonces: 256,
                vtxoExitDelta: 512,
                vtxoExpiryDelta: 1024,
                htlcSendExpiryDelta: 72,
                htlcExpiryDelta: 144,
                maxVtxoAmount: 100000000,
                requiredBoardConfirmations: 6,
                maxUserInvoiceCltvDelta: 288,
                minBoardAmount: 10000,
                maxVtxoExitDepth: 10,
                lnReceiveAntiDosRequired: false,
                feeSchedule: sampleFeeSchedule
            )
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Fetching Ark server info via FFI...")
        
        // Call FFI arkInfo method
        guard let ffiArkInfo = await wallet.arkInfo() else {
            Self.logger.warning("Ark server info not available (not connected)")
            throw BarkWalletFFIError.configurationError("Ark server info not available. Wallet may not be connected to ASP.")
        }
        
        Self.logger.info("Ark server info retrieved")
        
        // Convert FFI ArkInfo to ArkInfoModel
        let networkString = Self.convertFFINetworkToString(ffiArkInfo.network)
        
        // Convert round interval from seconds to string format like "30s"
        let roundIntervalString = "\(ffiArkInfo.roundIntervalSecs)s"
        
        // NOTE: Some fields may not be available in older FFI ArkInfo versions
        // FFI ArkInfo provides all fields we need - 1:1 mapping
        
        // Log the FFI ArkInfo fields
        Self.logger.debug("FFI ArkInfo fields: roundIntervalSecs: \(ffiArkInfo.roundIntervalSecs), nbRoundNonces: \(ffiArkInfo.nbRoundNonces), vtxoExitDelta: \(ffiArkInfo.vtxoExitDelta), vtxoExpiryDelta: \(ffiArkInfo.vtxoExpiryDelta), htlcSendExpiryDelta: \(ffiArkInfo.htlcSendExpiryDelta), htlcExpiryDelta: \(ffiArkInfo.htlcExpiryDelta), maxVtxoAmountSats: \(ffiArkInfo.maxVtxoAmountSats.map { String($0) } ?? "nil"), requiredBoardConfirmations: \(ffiArkInfo.requiredBoardConfirmations), maxUserInvoiceCltvDelta: \(ffiArkInfo.maxUserInvoiceCltvDelta), minBoardAmountSats: \(ffiArkInfo.minBoardAmountSats), maxVtxoExitDepth: \(ffiArkInfo.maxVtxoExitDepth), lnReceiveAntiDosRequired: \(ffiArkInfo.lnReceiveAntiDosRequired), feeScheduleJson: \(ffiArkInfo.feeScheduleJson)")
        
        // Parse fee schedule from JSON string
        let feeSchedule = FeeSchedule.from(jsonString: ffiArkInfo.feeScheduleJson)
        if feeSchedule != nil {
            Self.logger.info("Fee schedule parsed successfully")
        } else {
            Self.logger.warning("Failed to parse fee schedule JSON")
        }
        
        let arkInfoModel = ArkInfoModel(
            network: networkString,
            serverPubkey: ffiArkInfo.serverPubkey,
            roundInterval: roundIntervalString,
            nbRoundNonces: Int(ffiArkInfo.nbRoundNonces),
            vtxoExitDelta: Int(ffiArkInfo.vtxoExitDelta),
            vtxoExpiryDelta: Int(ffiArkInfo.vtxoExpiryDelta),
            htlcSendExpiryDelta: Int(ffiArkInfo.htlcSendExpiryDelta),
            htlcExpiryDelta: Int(ffiArkInfo.htlcExpiryDelta),
            maxVtxoAmount: ffiArkInfo.maxVtxoAmountSats.map { Int($0) },
            requiredBoardConfirmations: Int(ffiArkInfo.requiredBoardConfirmations),
            maxUserInvoiceCltvDelta: Int(ffiArkInfo.maxUserInvoiceCltvDelta),
            minBoardAmount: Int(ffiArkInfo.minBoardAmountSats),
            maxVtxoExitDepth: ffiArkInfo.maxVtxoExitDepth,
            lnReceiveAntiDosRequired: ffiArkInfo.lnReceiveAntiDosRequired,
            feeSchedule: feeSchedule
        )
        
        Self.logger.info("ArkInfoModel constructed from FFI data, all fields mapped directly from FFI ArkInfo")
        
        return arkInfoModel
    }
    
    /// Convert FFI Network enum back to string
    private static func convertFFINetworkToString(_ network: Network) -> String {
        switch network {
        case .bitcoin:
            return "bitcoin"
        case .testnet:
            return "testnet"
        case .signet:
            return "signet"
        case .regtest:
            return "regtest"
        }
    }
    
    // MARK: - Network Configuration Updates
    
    /// Update the network configuration after wallet creation/import
    /// This ensures the wallet's networkConfig reflects the actual network being used
    func updateNetworkConfig(_ newConfig: NetworkConfig) {
        Self.logger.info("Updating network configuration to: \(newConfig.name)")
        self.networkConfig = newConfig
    }
}
