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
        rerankForTypedAmount()
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
        // Same ownership as the onchain quote: the newest request owns the
        // flag, an older reply is dropped (review F2, 2026-10-27)
        lightningFeeRequestGeneration += 1
        let generation = lightningFeeRequestGeneration
        isEstimatingLightningFee = true
        defer {
            if generation == lightningFeeRequestGeneration {
                isEstimatingLightningFee = false
            }
        }
        do {
            let feeEstimate = try await walletManager.estimateLightningSendFee(amountSats: UInt64(amountToEstimate))
            guard generation == lightningFeeRequestGeneration else {
                logger.debug("   Dropping Lightning fee reply from superseded request \(generation)")
                return
            }
            cachedLightningFee = Int(feeEstimate.feeSats)
            cachedLightningFeeAmount = amountToEstimate
            logger.info("   Lightning fee estimated: \(feeEstimate.feeSats) sats for \(amountToEstimate) sats")
        } catch {
            guard generation == lightningFeeRequestGeneration else { return }
            // The row shows "unavailable"; no static stand-in anywhere
            logger.error("   Failed to estimate Lightning fee: \(error)")
            cachedLightningFee = nil
            cachedLightningFeeAmount = nil
        }
        rerankForTypedAmount()
    }
    
    // MARK: - Offboard Fee Estimation (bitcoin address paid from Payments)

    /// Asks bark what paying the selected bitcoin address from the Payments
    /// balance costs for the current amount. Only bark can price it: the
    /// server's offboard rate and the per-VTXO expiry table
    /// (`Features/Send_Onchain_From_Payments.md` §2.2). Cached per address
    /// and amount; a failed estimate leaves the row "unavailable", which
    /// blocks Send for this source.
    func calculateOffboardFee() async {
        guard isPaymentsOnchainSend, let destination = selectedDestination else {
            clearOffboardFee()
            return
        }

        // One key for request, cache and row (review F4, 2026-10-28: a
        // request amount that differed from the typed one left the row
        // "estimating" for good)
        guard let amountToEstimate = offboardEstimateAmount, amountToEstimate >= max(1, minimumSendAmount) else {
            clearOffboardFee()
            return
        }

        if currentOffboardFee(amountSats: amountToEstimate) != nil {
            logger.debug("Offboard fee still current for \(amountToEstimate) sats")
            isEstimatingOffboardFee = false
            return
        }

        offboardFeeRequestGeneration += 1
        let generation = offboardFeeRequestGeneration
        isEstimatingOffboardFee = true
        defer {
            if generation == offboardFeeRequestGeneration {
                isEstimatingOffboardFee = false
            }
        }

        logger.info("Quoting offboard fee for \(amountToEstimate) sats from Payments")
        do {
            let estimate = try await walletManager.estimateSendToOnchainFee(
                address: destination.address,
                amountSats: UInt64(amountToEstimate)
            )
            guard generation == offboardFeeRequestGeneration else {
                logger.debug("Dropping offboard fee reply from superseded request \(generation)")
                return
            }
            cachedOffboardFee = Int(estimate.feeSats)
            cachedOffboardFeeAmount = amountToEstimate
            cachedOffboardFeeAddress = destination.address
            logger.info("Offboard fee quoted: \(estimate.feeSats) sats for \(amountToEstimate) sats")
        } catch {
            guard generation == offboardFeeRequestGeneration else { return }
            logger.error("Failed to quote offboard fee: \(error)")
            clearOffboardFee()
        }
        rerankForTypedAmount()
    }

    /// Forgets the offboard fee and any request still open for it
    func clearOffboardFee() {
        offboardFeeRequestGeneration += 1
        isEstimatingOffboardFee = false
        cachedOffboardFee = nil
        cachedOffboardFeeAmount = nil
        cachedOffboardFeeAddress = nil
    }

    /// Debounced offboard fee update; the row says "estimating" from the
    /// first keystroke so the gate never passes a stale or missing fee
    @MainActor
    func updateOffboardFeeEstimate() {
        offboardFeeEstimationTask?.cancel()

        guard isPaymentsOnchainSend else {
            clearOffboardFee()
            return
        }
        if let amountInt = offboardEstimateAmount, amountInt >= max(1, minimumSendAmount) {
            if currentOffboardFee(amountSats: amountInt) == nil {
                offboardFeeRequestGeneration += 1
                isEstimatingOffboardFee = true
            }
        } else {
            clearOffboardFee()
            return
        }

        offboardFeeEstimationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            await calculateOffboardFee()
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
    
    /// Storage for the debounced offboard estimation task
    private static var offboardFeeEstimationTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]

    private var offboardFeeEstimationTask: Task<Void, Never>? {
        get {
            Self.offboardFeeEstimationTaskStorage[ObjectIdentifier(self)]
        }
        set {
            Self.offboardFeeEstimationTaskStorage[ObjectIdentifier(self)] = newValue
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
