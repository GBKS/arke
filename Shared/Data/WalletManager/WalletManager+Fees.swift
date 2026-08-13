//
//  WalletManager+Fees.swift
//  Arké
//
//  Fee estimation operations
//  All operations delegate to the wallet's fee estimation methods
//

import Foundation
import Bark
import ArkeUI

extension WalletManager {

    // MARK: - Onchain Fee Rates

    /// Latest known onchain fee rates (fallback defaults until the first
    /// successful Esplora fetch)
    var onchainFeeRates: OnchainFeeRates {
        feeRateService?.feeRates ?? .default
    }

    /// Onchain fee rates, refreshed from Esplora when the cache is stale.
    /// Never throws; falls back to last-known-good or default rates.
    /// - Parameter maxAge: Maximum cache age; pass 0 to force a fresh fetch
    func currentFeeRates(maxAge: TimeInterval = 300) async -> OnchainFeeRates {
        guard let feeRateService else { return .default }
        return await feeRateService.currentRates(maxAge: maxAge)
    }

    // MARK: - Fee Estimation
    
    /// Estimate the fee for an Arkoor payment
    /// - Parameter amountSats: Amount in satoshis to send
    /// - Returns: Estimated fee in satoshis
    func estimateArkoorPaymentFee(amountSats: UInt64) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateArkoorPaymentFee(amountSats: amountSats)
    }
    
    /// Estimate the fee for boarding funds to Ark
    /// - Parameter amountSats: Amount in satoshis to board
    /// - Returns: Estimated fee in satoshis
    func estimateBoardFee(amountSats: UInt64) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateBoardFee(amountSats: amountSats)
    }
    
    /// Estimate the fee for receiving Lightning payments
    /// - Parameter amountSats: Amount in satoshis to receive
    /// - Returns: Estimated fee in satoshis
    func estimateLightningReceiveFee(amountSats: UInt64) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateLightningReceiveFee(amountSats: amountSats)
    }
    
    /// Estimate the fee for sending Lightning payments
    /// - Parameter amountSats: Amount in satoshis to send
    /// - Returns: Estimated fee in satoshis
    func estimateLightningSendFee(amountSats: UInt64) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateLightningSendFee(amountSats: amountSats)
    }
    
    /// Estimate the fee for offboarding funds from Ark
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - vtxoIds: Array of VTXO IDs to offboard
    /// - Returns: Estimated fee in satoshis
    func estimateOffboardFee(address: String, vtxoIds: [String]) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateOffboardFee(address: address, vtxoIds: vtxoIds)
    }
    
    /// Estimate the fee for refreshing VTXOs
    /// - Parameter vtxoIds: Array of VTXO IDs to refresh
    /// - Returns: Estimated fee in satoshis
    func estimateRefreshFee(vtxoIds: [String]) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateRefreshFee(vtxoIds: vtxoIds)
    }
    
    /// Estimate the fee for sending an onchain transaction
    /// - Parameters:
    ///   - address: The destination Bitcoin address
    ///   - amountSats: Amount in satoshis to send
    /// - Returns: Estimated fee in satoshis
    func estimateSendToOnchainFee(address: String, amountSats: UInt64) async throws -> FeeEstimate {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.estimateSendToOnchainFee(address: address, amountSats: amountSats)
    }
    
    // MARK: - Onchain Fee Estimation
    
    /// Estimate fee for a specific onchain Bitcoin transaction amount
    /// Uses BDK's transaction builder to determine the exact fee based on
    /// actual UTXO selection and transaction size
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - amountSats: Amount to send in satoshis
    ///   - feeRateSatPerVb: Fee rate in satoshis per vByte
    /// - Returns: Estimated fee in satoshis
    /// - Throws: Error if calculation fails or the estimator can't be created
    func estimateOnchainFeeWithBDK(address: String, amountSats: UInt64, feeRateSatPerVb: UInt64) async throws -> UInt64 {
        guard let ffiWallet = wallet as? BarkWalletFFI else {
            throw BarkErrorArke.commandFailed("BDK wallet not available")
        }

        // Created lazily on first use; a fresh database full-scans once
        let feeEstimator = try await ffiWallet.ensureFeeEstimator()

        // Sync to ensure we have the latest UTXOs
        // Use incremental sync for speed (not full scan)
        try await feeEstimator.sync(fullScan: false)

        // Estimate fee using BDK's transaction builder
        // This builds an actual transaction to determine exact fees
        return try feeEstimator.estimateFee(
            address: address,
            amountSats: amountSats,
            feeRateSatPerVb: feeRateSatPerVb
        )
    }
    
    // MARK: - Onchain Max Sendable
    
    /// Calculate maximum sendable amount for onchain Bitcoin transactions
    /// Uses BDK's transaction builder to determine the exact amount that can be sent
    /// after accounting for fees based on actual UTXO selection and transaction size
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - feeRateSatPerVb: Fee rate in satoshis per vByte
    /// - Returns: Tuple of (sendable amount, fee) both in satoshis
    /// - Throws: Error if calculation fails or the estimator can't be created
    func calculateOnchainMaxSendable(address: String, feeRateSatPerVb: UInt64) async throws -> (sendAmount: UInt64, fee: UInt64) {
        guard let ffiWallet = wallet as? BarkWalletFFI else {
            throw BarkErrorArke.commandFailed("BDK wallet not available")
        }

        // Created lazily on first use; a fresh database full-scans once
        let feeEstimator = try await ffiWallet.ensureFeeEstimator()

        // Sync to ensure we have the latest UTXOs
        // Use incremental sync for speed (not full scan)
        try await feeEstimator.sync(fullScan: false)

        // Calculate max sendable using BDK's drain wallet feature
        // This builds an actual transaction to determine exact fees
        return try feeEstimator.calculateMaxSendable(
            address: address,
            feeRateSatPerVb: feeRateSatPerVb
        )
    }
}
