//
//  SendViewModel+FeeCalculation.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Fee calculation with caching for Lightning and Ark payments to avoid
//  repeated API calls during amount entry.
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Ark Fee Estimation
    
    /// Calculates Ark payment fee for the current amount and destination
    /// Caches the result to avoid repeated API calls for the same amount
    func calculateArkFee() async {
        logger.debug("calculateArkFee() called")
        logger.debug("   → isArkDestination: \(self.isArkDestination)")
        logger.debug("   → selectedDestination: \(self.selectedDestination?.format.rawValue ?? "nil")")
        
        guard isArkDestination else {
            logger.debug("   → Not an Ark destination, clearing cache")
            cachedArkFee = nil
            cachedArkFeeAmount = nil
            return
        }
        
        // Determine the amount to use for fee estimation
        let amountToEstimate: Int
        if let paymentAmount = currentPaymentRequest?.amount {
            // Use embedded payment request amount
            logger.debug("   → Using payment request amount: \(paymentAmount) sats")
            amountToEstimate = paymentAmount
        } else if let enteredAmount = Int(amount), enteredAmount > 0 {
            // Use manually entered amount
            logger.debug("   → Using entered amount: \(enteredAmount) sats")
            amountToEstimate = enteredAmount
        } else {
            // No amount available, clear cache and return
            logger.debug("   → No amount available (paymentRequest: \(self.currentPaymentRequest?.amount?.description ?? "nil"), entered: '\(self.amount)')")
            cachedArkFee = nil
            cachedArkFeeAmount = nil
            return
        }
        
        // Check if we already have a cached fee for this amount
        if cachedArkFee != nil, cachedArkFeeAmount == amountToEstimate {
            logger.debug("   → Using cached fee: \(self.cachedArkFee!) sats")
            return
        }
        
        logger.debug("   → Calling walletManager.estimateArkoorPaymentFee(amountSats: \(amountToEstimate))")
        do {
            let feeEstimate = try await walletManager.estimateArkoorPaymentFee(amountSats: UInt64(amountToEstimate))
            cachedArkFee = Int(feeEstimate.feeSats)
            cachedArkFeeAmount = amountToEstimate
            logger.info("   Ark fee estimated: \(feeEstimate.feeSats) sats for \(amountToEstimate) sats")
        } catch {
            logger.error("   Failed to estimate Ark fee: \(error)")
            // Fall back to zero fee on error (Ark payments typically have no fee)
            cachedArkFee = nil
            cachedArkFeeAmount = nil
        }
    }
    
    // MARK: - Lightning Fee Estimation
    
    /// Calculates Lightning send fee for the current amount and destination
    /// Caches the result to avoid repeated API calls for the same amount
    func calculateLightningFee() async {
        logger.debug("calculateLightningFee() called")
        logger.debug("   → isLightningDestination: \(self.isLightningDestination)")
        logger.debug("   → selectedDestination: \(self.selectedDestination?.format.rawValue ?? "nil")")
        
        guard isLightningDestination else {
            logger.debug("   → Not a Lightning destination, clearing cache")
            cachedLightningFee = nil
            cachedLightningFeeAmount = nil
            return
        }
        
        // Determine the amount to use for fee estimation
        let amountToEstimate: Int
        if let paymentAmount = currentPaymentRequest?.amount {
            // Use embedded payment request amount (e.g., Lightning invoice)
            logger.debug("   → Using payment request amount: \(paymentAmount) sats")
            amountToEstimate = paymentAmount
        } else if let enteredAmount = Int(amount), enteredAmount > 0 {
            // Use manually entered amount
            logger.debug("   → Using entered amount: \(enteredAmount) sats")
            amountToEstimate = enteredAmount
        } else {
            // No amount available, clear cache and return
            logger.debug("   → No amount available (paymentRequest: \(self.currentPaymentRequest?.amount?.description ?? "nil"), entered: '\(self.amount)')")
            cachedLightningFee = nil
            cachedLightningFeeAmount = nil
            return
        }
        
        // Check if we already have a cached fee for this amount
        if cachedLightningFee != nil, cachedLightningFeeAmount == amountToEstimate {
            logger.debug("   → Using cached fee: \(self.cachedLightningFee!) sats")
            return
        }
        
        logger.debug("   → Calling walletManager.estimateLightningSendFee(amountSats: \(amountToEstimate))")
        do {
            let feeEstimate = try await walletManager.estimateLightningSendFee(amountSats: UInt64(amountToEstimate))
            cachedLightningFee = Int(feeEstimate.feeSats)
            cachedLightningFeeAmount = amountToEstimate
            logger.info("   Lightning fee estimated: \(feeEstimate.feeSats) sats for \(amountToEstimate) sats")
        } catch {
            logger.error("   Failed to estimate Lightning fee: \(error)")
            // Fall back to static estimate on error
            cachedLightningFee = nil
            cachedLightningFeeAmount = nil
        }
    }
    
    // MARK: - Debounced Fee Updates
    
    /// Updates the Lightning fee estimate with debouncing
    /// This should be called when the amount changes
    @MainActor
    func updateLightningFeeEstimate() {
        // Cancel any pending estimation
        lightningFeeEstimationTask?.cancel()
        
        // Schedule new estimation with delay
        lightningFeeEstimationTask = Task { @MainActor in
            // Wait for user to stop typing
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Perform estimation
            await calculateLightningFee()
        }
    }
    
    /// Updates the Ark fee estimate with debouncing
    /// This should be called when the amount changes
    @MainActor
    func updateArkFeeEstimate() {
        // Cancel any pending estimation
        arkFeeEstimationTask?.cancel()
        
        // Schedule new estimation with delay
        arkFeeEstimationTask = Task { @MainActor in
            // Wait for user to stop typing
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Perform estimation
            await calculateArkFee()
        }
    }
    
    // MARK: - Task Storage
    
    /// Storage for the debounced Lightning estimation task
    private static var lightningFeeEstimationTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    private var lightningFeeEstimationTask: Task<Void, Never>? {
        get {
            Self.lightningFeeEstimationTaskStorage[ObjectIdentifier(self)]
        }
        set {
            Self.lightningFeeEstimationTaskStorage[ObjectIdentifier(self)] = newValue
        }
    }
    
    /// Storage for the debounced Ark estimation task
    private static var arkFeeEstimationTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    private var arkFeeEstimationTask: Task<Void, Never>? {
        get {
            Self.arkFeeEstimationTaskStorage[ObjectIdentifier(self)]
        }
        set {
            Self.arkFeeEstimationTaskStorage[ObjectIdentifier(self)] = newValue
        }
    }
}
