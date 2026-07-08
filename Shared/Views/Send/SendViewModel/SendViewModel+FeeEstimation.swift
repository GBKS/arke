//
//  SendViewModel+FeeEstimation.swift
//  Arké
//
//  Created by Assistant on 5/18/26.
//
//  Fee estimation for onchain Bitcoin transactions using BDK
//

import Foundation
import OSLog
import ArkeUI

extension SendViewModel {
    
    // MARK: - Onchain Fee Estimation
    
    /// Estimates the onchain fee using BDK's transaction builder
    /// Results are cached and only recalculated when amount or fee priority changes
    @MainActor
    func estimateOnchainFee() async {
        guard let destination = selectedDestination else {
            logger.warning("No destination selected")
            return
        }
        
        guard isOnchainDestination else {
            logger.warning("Not an onchain destination")
            return
        }

        // Keep published rates fresh while the send screen stays open
        // (served from FeeRateService's cache when recent, so this is cheap)
        let freshRates = await walletManager.currentFeeRates()
        if freshRates != onchainFeeRates {
            onchainFeeRates = freshRates
            invalidateOnchainFeeCache()
        }

        guard let amountInt = Int(amount), amountInt > 0 else {
            logger.warning("Invalid amount: \(self.amount)")
            cachedOnchainFee = nil
            cachedOnchainFeeAmount = nil
            cachedOnchainFeePriority = nil
            return
        }
        
        // Check if we can use cached value
        if let cached = cachedOnchainFee,
           cachedOnchainFeeAmount == amountInt,
           cachedOnchainFeePriority == selectedFeePriority {
            logger.debug("Using cached fee: \(cached) sats")
            return
        }
        
        logger.info("Calculating fee for \(amountInt) sats at \(self.selectedFeePriority.rawValue) priority")
        
        do {
            let feeRate = onchainFeeRates.rate(for: selectedFeePriority)
            
            let fee = try await walletManager.estimateOnchainFeeWithBDK(
                address: destination.address,
                amountSats: UInt64(amountInt),
                feeRateSatPerVb: feeRate
            )
            
            // Cache the result
            cachedOnchainFee = Int(fee)
            cachedOnchainFeeAmount = amountInt
            cachedOnchainFeePriority = selectedFeePriority
            logger.info("Fee calculated: \(fee) sats (cached)")
            
        } catch {
            logger.error("Failed to estimate fee: \(error)")
            // Keep any existing cache on error
        }
    }
    
    /// Invalidates the onchain fee cache
    /// Call this when conditions change that require fee recalculation
    @MainActor
    func invalidateOnchainFeeCache() {
        cachedOnchainFee = nil
        cachedOnchainFeeAmount = nil
        cachedOnchainFeePriority = nil
        logger.debug("Cache invalidated")
    }
    
    /// Updates the onchain fee estimate with debouncing
    /// This should be called when the amount changes
    @MainActor
    func updateOnchainFeeEstimate() {
        // Cancel any pending estimation
        onchainFeeEstimationTask?.cancel()
        
        // Schedule new estimation with delay
        onchainFeeEstimationTask = Task { @MainActor in
            // Wait for user to stop typing
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Perform estimation
            await estimateOnchainFee()
        }
    }
    
    /// Storage for the debounced estimation task
    private static var onchainFeeEstimationTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    private var onchainFeeEstimationTask: Task<Void, Never>? {
        get {
            Self.onchainFeeEstimationTaskStorage[ObjectIdentifier(self)]
        }
        set {
            Self.onchainFeeEstimationTaskStorage[ObjectIdentifier(self)] = newValue
        }
    }
}
