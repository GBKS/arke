//
//  SendViewModel+StateManagement.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  State transitions between send modes (manual, contact, quick)
//  and destination ranking logic.
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Payment Request Locking
    
    /// Locks in a payment request and switches to manual confirmed mode
    func lockInPaymentRequest(_ paymentRequest: PaymentRequest) async {
        logger.info("Locking in payment request with \(paymentRequest.destinations.count) destination(s)")
        
        // Store the payment request
        currentPaymentRequest = paymentRequest
        
        // Rank destinations using the selector (with real fee estimation)
        rankedDestinations = await paymentRequest.rankedDestinations(context: paymentContext)
        
        logger.debug("Ranked destinations:")
        for (index, ranked) in rankedDestinations.enumerated() {
            let viableIcon = ranked.viable ? "✓" : "✗"
            logger.debug("   \(viableIcon) [\(index + 1)] \(ranked.destination.format.displayName)")
            logger.debug("      Balance: \(ranked.balanceSource.displayName)")
            logger.debug("      Available: \(ranked.availableBalance?.description ?? "N/A") sats")
            logger.debug("      Fee: ~\(ranked.estimatedFee?.description ?? "N/A") sats")
            logger.debug("      Reason: \(ranked.reason)")
        }
        
        // Select the optimal (first viable) destination
        if let optimal = rankedDestinations.first(where: { $0.viable }) {
            selectedDestination = optimal.destination
            logger.info("Auto-selected optimal destination: \(optimal.destination.format.displayName)")
            
            // Populate manualInput with the address so it shows in the UI
            let addressToDisplay = paymentRequest.originalString
            manualInput = addressToDisplay
            logger.debug("   → Set manualInput to: \(addressToDisplay)")
            
            // Clear any previous errors
            error = nil
            
            // Switch to manual confirmed mode
            sendMode = .manual
            recipientState = .valid
            
            // Calculate fees based on destination type
            Task {
                await calculateLightningFee()
                await calculateArkFee()
                await estimateOnchainFee()
            }
        } else {
            selectedDestination = nil
            // Show error explaining why no destinations are viable
            let reasons = rankedDestinations.map { "\($0.destination.format.displayName): \($0.reason)" }
            error = "Cannot send payment. " + reasons.joined(separator: "; ")
            logger.warning("No viable destinations found")
            return
        }
        
        // Pre-fill amount for payment requests with embedded amounts
        if let requestAmount = paymentRequest.amount {
            logger.debug("   → Pre-filling amount: \(requestAmount) sats")
            amount = "\(requestAmount)"
        }
    }
    
    // MARK: - Destination Ranking
    
    /// Ranks a single destination for manual entry mode
    /// This ensures fee calculation and viability checking work when typing addresses manually
    func rankManualDestination(_ destination: PaymentDestination) async {
        logger.debug("Ranking manual destination: \(destination.format.displayName)")
        
        // Create a minimal payment request with just this destination
        let paymentRequest = PaymentRequest(
            destinations: [destination],
            amount: nil,
            label: nil,
            message: nil,
            originalString: destination.address
        )
        
        // Rank the destination (with real fee estimation)
        rankedDestinations = await paymentRequest.rankedDestinations(context: paymentContext)
        
        logger.debug("   → Ranked with fee: \(self.rankedDestinations.first?.estimatedFee?.description ?? "N/A") sats")
        logger.debug("   → Viable: \(self.rankedDestinations.first?.viable ?? false)")
        if let reason = self.rankedDestinations.first?.reason {
            logger.debug("   → Reason: \(reason)")
        }
    }
    
    // MARK: - State Clearing
    
    /// Clears all state and returns to manual entry mode
    func clearAll() {
        logger.debug("Clearing all state, returning to manual entry")
        sendMode = .manual
        manualInput = ""
        amount = ""
        selectedDestination = nil
        rankedDestinations = []
        currentPaymentRequest = nil
        error = nil
        recipientState = .idle
        sendModalState = nil
        cachedLightningFee = nil
        cachedLightningFeeAmount = nil
        cachedArkFee = nil
        cachedArkFeeAmount = nil
        resolvedLNURL = nil
        isSendingMax = false
    }
    
    // MARK: - Amount & Mode Updates
    
    /// Updates the amount and recalculates fees if needed
    /// Should be called when the user changes the amount in the UI
    func updateAmount(_ newAmount: String) async {
        amount = newAmount
        
        // Clear the "send max" flag since user manually changed the amount
        isSendingMax = false
        
        // Recalculate fees based on destination type
        if isLightningDestination {
            await calculateLightningFee()
        }
        if isArkDestination {
            await calculateArkFee()
        }
    }
    
    /// Enters quick mode with a payment request and calculates fees
    func enterQuickMode(paymentRequest: PaymentRequest, source: PaymentRequestSource) async {
        // Store the payment request
        currentPaymentRequest = paymentRequest
        
        // Rank destinations (with real fee estimation)
        rankedDestinations = await paymentRequest.rankedDestinations(context: paymentContext)
        
        // Select the optimal destination
        if let optimal = rankedDestinations.first(where: { $0.viable }) {
            selectedDestination = optimal.destination
            
            // Pre-fill amount if embedded in the payment request
            if let requestAmount = paymentRequest.amount {
                amount = "\(requestAmount)"
            }
            
            // Calculate fees based on destination type
            await calculateLightningFee()
            await calculateArkFee()
        }
        
        // Set the mode
        sendMode = .quick(paymentRequest, source: source)
    }
}
