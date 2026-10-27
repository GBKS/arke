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
import os

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
    
    /// What the shadow wallet said about one tier of an onchain send
    enum OnchainTierFee: Equatable, Sendable {
        /// Exact fee in satoshis
        case fee(UInt64)
        /// Amount plus this tier's fee exceeds the shadow wallet's spendable balance
        case insufficientFunds
    }

    /// Estimate the fee for one onchain send at every priority tier in one
    /// pass: the estimator syncs once (the only network step), then builds
    /// one transaction per tier locally. Costs the same as a single-tier
    /// estimate, so the send flow can quote all three tiers at once and a
    /// tier switch needs no new estimate.
    ///
    /// Every tier gets a result. A tier the wallet cannot fund is reported
    /// as such rather than dropped: after "Max" at one tier every faster
    /// tier is unfundable by construction, and a quote with holes would be
    /// read as "not priced yet". Any other build error aborts the whole
    /// quote, since all tiers share the same inputs.
    ///
    /// When every tier is unfundable but bark's own onchain balance covers
    /// the amount, the shadow wallet is behind (it only learns addresses
    /// from its own scans; backlog "BDK fee estimator is blind to onchain
    /// funds that arrived after its one full scan"): run one full scan and
    /// quote again, once.
    /// - Parameters:
    ///   - address: Destination Bitcoin address
    ///   - amountSats: Amount to send in satoshis
    ///   - feeRates: Rates per tier, as published by `FeeRateService`
    /// - Throws: When the estimator cannot be created, a sync fails, or a
    ///   build fails for a reason other than funds
    func estimateOnchainFees(address: String, amountSats: UInt64, feeRates: OnchainFeeRates) async throws -> [FeePriority: OnchainTierFee] {
        guard let ffiWallet = wallet as? BarkWalletFFI else {
            throw BarkErrorArke.commandFailed("BDK wallet not available")
        }

        let feeEstimator = try await ffiWallet.ensureFeeEstimator()
        try await feeEstimator.sync(fullScan: false)

        var tiers = try Self.quoteTiers(with: feeEstimator, address: address, amountSats: amountSats, feeRates: feeRates)

        let allUnfundable = tiers.values.allSatisfy { $0 == .insufficientFunds }
        let barkSpendable = onchainBalance?.spendableSat ?? 0
        if allUnfundable, barkSpendable >= Int(clamping: amountSats) {
            Self.logger.info("Fee estimator finds no funds for \(amountSats) sats while bark holds \(barkSpendable) spendable; running one full scan and quoting again")
            try await feeEstimator.sync(fullScan: true)
            tiers = try Self.quoteTiers(with: feeEstimator, address: address, amountSats: amountSats, feeRates: feeRates)
        }
        return tiers
    }

    private static func quoteTiers(
        with feeEstimator: BDKFeeEstimator,
        address: String,
        amountSats: UInt64,
        feeRates: OnchainFeeRates
    ) throws -> [FeePriority: OnchainTierFee] {
        // One build per distinct rate, shared by every tier at that rate:
        // BDK's coin selection is not deterministic between builds, and two
        // tiers at the same rate must not show two different fees
        var byRate: [UInt64: OnchainTierFee] = [:]
        var tiers: [FeePriority: OnchainTierFee] = [:]
        for priority in FeePriority.allCases {
            let rate = feeRates.rate(for: priority)
            if byRate[rate] == nil {
                do {
                    byRate[rate] = .fee(try feeEstimator.estimateFee(
                        address: address,
                        amountSats: amountSats,
                        feeRateSatPerVb: rate
                    ))
                } catch let error as BDKFeeEstimatorError where error.isInsufficientFunds {
                    byRate[rate] = .insufficientFunds
                }
            }
            if let result = byRate[rate] {
                tiers[priority] = result
            }
        }
        return tiers
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
