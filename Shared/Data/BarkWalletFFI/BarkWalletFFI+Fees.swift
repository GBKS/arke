//
//  BarkWalletFFI+Fees.swift
//  Arke
//
//  Fee estimation for all wallet operations
//  Provides fee calculations for boarding, offboarding, Lightning, and refresh
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

extension BarkWalletFFI {

    // MARK: - Onchain Fee Estimator (shadow BDK wallet)

    /// The lazily created shadow BDK wallet for send-flow fee estimation.
    /// No longer created at wallet startup (Phase 2 of the reader removal):
    /// the first use pays a one-time full scan when the database is fresh,
    /// and each estimate afterwards does an incremental sync. Goes away
    /// entirely once bark exposes an onchain estimate/drain API.
    func ensureFeeEstimator() async throws -> BDKFeeEstimator {
        if let feeEstimator = feeEstimator {
            return feeEstimator
        }

        guard let mnemonic = cachedMnemonic else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        let bdkDataDir = walletDir.appendingPathComponent("bdk", isDirectory: true)
        if !FileManager.default.fileExists(atPath: bdkDataDir.path) {
            try FileManager.default.createDirectory(at: bdkDataDir, withIntermediateDirectories: true)
        }

        Self.logger.debug("Creating fee estimator (lazy, first fee estimate)")
        let estimator = try BDKFeeEstimator(
            mnemonic: mnemonic,
            network: ffiNetwork,
            esploraURL: config.esploraAddress ?? networkConfig.esploraBaseURL,
            dataDir: bdkDataDir
        )

        if estimator.createdFreshDatabase {
            Self.logger.info("Fee estimator database is fresh - running one-time full scan")
            try await estimator.sync(fullScan: true)
        }

        feeEstimator = estimator
        return estimator
    }

    // MARK: - Fee Estimation

    func estimateArkoorPaymentFee(amountSats: UInt64) async throws -> FeeEstimate {
        // Estimate fee for Arkoor (Ark-to-Ark) payment operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateArkoorPaymentFee(amountSats: amountSats)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating Arkoor payment fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate Arkoor payment fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating Arkoor payment fee: \(error)")
            throw error
        }
    }
    
    func estimateBoardFee(amountSats: UInt64) async throws -> FeeEstimate {
        // Estimate fee for boarding operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 100, feeSats: 100, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateBoardFee(amountSats: amountSats)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating board fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate board fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating board fee: \(error)")
            throw error
        }
    }
    
    func estimateLightningReceiveFee(amountSats: UInt64) async throws -> FeeEstimate {
        // Estimate fee for Lightning receive operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateLightningReceiveFee(amountSats: amountSats)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating lightning receive fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate lightning receive fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating lightning receive fee: \(error)")
            throw error
        }
    }
    
    func estimateLightningSendFee(amountSats: UInt64) async throws -> FeeEstimate {
        // Estimate fee for Lightning send operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateLightningSendFee(amountSats: amountSats)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating lightning send fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate lightning send fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating lightning send fee: \(error)")
            throw error
        }
    }
    
    func estimateOffboardFee(address: String, vtxoIds: [String]) async throws -> FeeEstimate {
        // Estimate fee for offboarding operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 200, feeSats: 200, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateOffboardFee(address: address, vtxoIds: vtxoIds)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating offboard fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate offboard fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating offboard fee: \(error)")
            throw error
        }
    }
    
    func estimateRefreshFee(vtxoIds: [String]) async throws -> FeeEstimate {
        // Estimate fee for refresh operation
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 75, feeSats: 75, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateRefreshFee(vtxoIds: vtxoIds)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating refresh fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate refresh fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating refresh fee: \(error)")
            throw error
        }
    }
    
    func estimateSendToOnchainFee(address: String, amountSats: UInt64) async throws -> FeeEstimate {
        // Estimate fee for sending from the Ark balance to an onchain address
        
        if isPreview {
            return FeeEstimate(grossAmountSats: 150, feeSats: 150, netAmountSats: 0, vtxosSpent: []) // Mock fee
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.estimateSendOnchainFee(address: address, amountSats: amountSats)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error estimating send onchain fee: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to estimate send onchain fee: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error estimating send onchain fee: \(error)")
            throw error
        }
    }
}
