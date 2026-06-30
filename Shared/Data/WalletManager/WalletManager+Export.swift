//
//  WalletManager+Export.swift
//  Arké
//
//  Data export functionality
//  Exports complete wallet state to JSON format for backup or analysis
//

import Foundation
import ArkeUI

extension WalletManager {
    
    // MARK: - Data Export
    
    /// Export all wallet data as JSON
    /// Includes addresses, balances, transactions, VTXOs, UTXOs, config, and metadata
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
                onchainBalance: onchainBalance.map { model in
                    OnchainBalanceResponse(
                        totalSat: model.totalSat,
                        confirmedSat: model.confirmedSat,
                        pendingSat: model.pendingSat
                    )
                }
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
