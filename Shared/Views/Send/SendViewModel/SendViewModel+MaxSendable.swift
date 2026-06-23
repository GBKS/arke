//
//  SendViewModel+MaxSendable.swift
//  Arké
//
//  Created by Assistant on 5/16/26.
//
//  Max sendable amount calculation with iterative fee estimation
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Max Sendable Calculation
    
    /// Calculates the maximum sendable amount for the selected destination, accounting for fees
    /// Uses iterative fee estimation to converge on the exact amount that can be sent
    /// Sets the isSendingMax flag to enable retry logic for Lightning payments
    /// - Returns: Maximum sendable amount in satoshis, or nil if calculation fails
    func calculateMaxSendable() async -> Int? {
        guard let destination = selectedDestination else {
            logger.error("No destination selected")
            return nil
        }
        
        // Set flag to indicate this is a "send max" operation
        // This enables retry logic for Lightning payments with dynamic routing fees
        isSendingMax = true
        
        let balanceSource = PaymentDestinationSelector.balanceSource(for: destination)
        
        guard let initialBalance = PaymentDestinationSelector.availableBalance(
            for: destination,
            context: paymentContext
        ) else {
            logger.error("No balance available for destination")
            return nil
        }
        
        logger.info("Calculating max sendable for \(destination.format.rawValue)")
        logger.debug("   Initial balance: \(initialBalance) sats")
        logger.debug("   Balance source: \(balanceSource.displayName)")
        
        // Route to appropriate calculation method based on destination format
        switch destination.format {
        case .ark:
            return await calculateMaxSendableArk(balance: initialBalance)
            
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            return await calculateMaxSendableLightning(
                destination: destination,
                balance: initialBalance
            )
            
        case .bitcoin, .silentPayments:
            return await calculateMaxSendableOnchain(
                destination: destination,
                balance: initialBalance,
                balanceSource: balanceSource
            )
            
        case .bip353, .bip21:
            // These should be resolved before reaching this point
            logger.warning("Wrapper format reached calculateMaxSendable")
            return nil
        }
    }
    
    // MARK: - Ark Max Sendable
    
    /// Calculate max sendable for Ark-to-Ark payments (no fees)
    private func calculateMaxSendableArk(balance: Int) async -> Int {
        logger.info("Ark-to-Ark: No fees, returning full balance")
        return balance
    }
    
    // MARK: - Lightning Max Sendable
    
    /// Calculate max sendable for Lightning payments with iterative fee estimation
    private func calculateMaxSendableLightning(destination: PaymentDestination, balance: Int) async -> Int? {
        logger.info("Lightning: Starting iterative fee estimation")
        
        var currentAmount = balance
        var previousGross = 0
        
        // Iterate up to 5 times to converge on the correct amount
        for iteration in 1...5 {
            logger.debug("   Iteration \(iteration): Testing amount \(currentAmount) sats")
            
            do {
                let feeEstimate = try await walletManager.estimateLightningSendFee(
                    amountSats: UInt64(currentAmount)
                )
                
                let grossAmount = Int(feeEstimate.grossAmountSats)
                let fee = Int(feeEstimate.feeSats)
                let netAmount = Int(feeEstimate.netAmountSats)
                logger.debug("   → Fee estimate details:")
                logger.debug("      grossAmountSats: \(grossAmount)")
                logger.debug("      feeSats: \(fee)")
                logger.debug("      netAmountSats: \(netAmount)")
                logger.debug("      vtxosSpent count: \(feeEstimate.vtxosSpent.count)")
                if !feeEstimate.vtxosSpent.isEmpty {
                    logger.debug("      vtxosSpent IDs: \(feeEstimate.vtxosSpent.joined(separator: ", "))")
                }
                
                // Check if gross amount fits in balance
                if grossAmount <= balance {
                    // Check if we've converged (gross didn't change)
                    if grossAmount == previousGross && iteration > 1 {
                        logger.info("Lightning: Converged after \(iteration) iterations")
                        logger.debug("   Final amount: \(currentAmount) sats, Fee: \(fee) sats, Gross: \(grossAmount) sats")
                        return currentAmount
                    }
                    
                    // Try to increase amount since we have room
                    previousGross = grossAmount
                    let remainingBalance = balance - grossAmount
                    if remainingBalance > 0 {
                        currentAmount = currentAmount + remainingBalance
                    } else {
                        // Perfect fit
                        return currentAmount
                    }
                } else {
                    // Gross exceeds balance, reduce amount
                    previousGross = grossAmount
                    let excess = grossAmount - balance
                    currentAmount = currentAmount - excess
                    
                    // Sanity check: ensure amount is positive
                    if currentAmount <= 0 {
                        logger.error("Lightning: Cannot send - fee exceeds balance")
                        return nil
                    }
                }
                
            } catch {
                logger.error("Lightning: Fee estimation failed: \(error)")
                // Fall back to conservative estimate (subtract 1% or 100 sats minimum)
                let conservativeFee = max(100, balance / 100)
                logger.debug("   Using conservative fee estimate: \(conservativeFee) sats")
                return balance - conservativeFee
            }
        }
        
        // After 5 iterations, use the last calculated amount
        logger.info("Lightning: Completed 5 iterations, final amount: \(currentAmount) sats")
        return currentAmount
    }
    
    // MARK: - Onchain Max Sendable
    
    /// Calculate max sendable for onchain payments
    private func calculateMaxSendableOnchain(
        destination: PaymentDestination,
        balance: Int,
        balanceSource: PaymentDestinationSelector.BalanceSource
    ) async -> Int? {
        
        if balanceSource == .bitcoin {
            // Use BDK transaction reader to calculate exact max sendable amount
            // This builds an actual drain transaction to determine precise fees
            logger.info("Onchain (BDK): Calculating exact max sendable with BDK")
            
            do {
                let feeRate = onchainFeeRates.rate(for: selectedFeePriority)
                
                // Use BDK transaction reader to calculate exact max sendable
                let result = try await walletManager.calculateOnchainMaxSendable(
                    address: destination.address,
                    feeRateSatPerVb: feeRate
                )
                
                let maxAmount = Int(result.sendAmount)
                let fee = Int(result.fee)
                
                logger.info("Onchain (BDK): Exact calculation complete")
                logger.debug("   Max sendable: \(maxAmount) sats")
                logger.debug("   Fee: \(fee) sats")
                
                return maxAmount > 0 ? maxAmount : nil
                
            } catch {
                logger.error("Onchain (BDK): Calculation failed: \(error)")
                // Fallback to conservative estimate
                let feeRate = onchainFeeRates.rate(for: selectedFeePriority)
                let estimatedFee = PaymentDestinationSelector.estimateOnchainFee(
                    for: destination,
                    amount: balance,
                    feeRate: feeRate
                )
                let maxAmount = balance - estimatedFee
                logger.debug("   Using conservative fallback: \(maxAmount) sats (fee: \(estimatedFee) sats)")
                return maxAmount > 0 ? maxAmount : nil
            }
        }
        
        // Ark balance to onchain (offboarding)
        logger.info("Offboarding: Starting iterative fee estimation")
        
        var currentAmount = balance
        var previousGross = 0
        
        // Iterate up to 5 times to converge on the correct amount
        for iteration in 1...5 {
            logger.debug("   Iteration \(iteration): Testing amount \(currentAmount) sats")
            
            do {
                let feeEstimate = try await walletManager.estimateSendToOnchainFee(
                    address: destination.address,
                    amountSats: UInt64(currentAmount)
                )
                
                let grossAmount = Int(feeEstimate.grossAmountSats)
                let fee = Int(feeEstimate.feeSats)
                logger.debug("   → Fee: \(fee) sats, Gross: \(grossAmount) sats")
                
                // Check if gross amount fits in balance
                if grossAmount <= balance {
                    // Check if we've converged (gross didn't change)
                    if grossAmount == previousGross && iteration > 1 {
                        logger.info("Offboarding: Converged after \(iteration) iterations")
                        logger.debug("   Final amount: \(currentAmount) sats, Fee: \(fee) sats, Gross: \(grossAmount) sats")
                        return currentAmount
                    }
                    
                    // Try to increase amount since we have room
                    previousGross = grossAmount
                    let remainingBalance = balance - grossAmount
                    if remainingBalance > 0 {
                        currentAmount = currentAmount + remainingBalance
                    } else {
                        // Perfect fit
                        return currentAmount
                    }
                } else {
                    // Gross exceeds balance, reduce amount
                    previousGross = grossAmount
                    let excess = grossAmount - balance
                    currentAmount = currentAmount - excess
                    
                    // Sanity check: ensure amount is positive
                    if currentAmount <= 0 {
                        logger.error("Offboarding: Cannot send - fee exceeds balance")
                        return nil
                    }
                }
                
            } catch {
                logger.error("Offboarding: Fee estimation failed: \(error)")
                // Fall back to conservative estimate
                let conservativeFee = 500 // 500 sats conservative estimate
                logger.debug("   Using conservative fee estimate: \(conservativeFee) sats")
                return balance - conservativeFee
            }
        }
        
        // After 5 iterations, use the last calculated amount
        logger.info("Offboarding: Completed 5 iterations, final amount: \(currentAmount) sats")
        return currentAmount
    }
}
