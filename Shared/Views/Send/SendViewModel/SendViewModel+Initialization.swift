//
//  SendViewModel+Initialization.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Initial setup when SendView appears, handling pre-filled recipients,
//  contacts, and BIP-353 resolution.
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Initial Setup
    
    /// Handles initial setup when view appears
    /// Implements Option C: automatic clipboard check only when SendView is first opened
    func handleInitialSetup(prefilledRecipient: String?, prefilledContact: ContactModel?) async {
        // Check for pre-filled contact first (highest priority)
        if let contact = prefilledContact, let recipient = prefilledRecipient {
            logger.info("Pre-filling contact: \(contact.cachedName)")
            logger.debug("   → Recipient address: \(recipient)")
            
            // Check if this is a BIP-353 address that needs resolution
            if BIP353Resolver.isBIP353Format(recipient) {
                logger.debug("   → Detected BIP-353 address in contact")
                
                do {
                    let resolved = try await BIP353Resolver.resolve(recipient)
                    logger.info("   BIP-353 resolved successfully!")
                    logger.debug("      → Original: \(resolved.originalAddress)")
                    logger.debug("      → Resolved URI: \(resolved.bip21URI)")
                    
                    // Parse the resolved BIP-21 URI instead of the original BIP-353 address
                    if var paymentRequest = AddressValidator.parsePaymentRequest(resolved.bip21URI) {
                        logger.debug("   → Parsed resolved URI into payment request")
                        logger.debug("      → Destinations: \(paymentRequest.destinations.count)")
                        for (index, dest) in paymentRequest.destinations.enumerated() {
                            logger.debug("         [\(index)] format: \(dest.format.rawValue), address: \(dest.shortAddress)")
                        }
                        
                        // Preserve the BIP-353 address as the display string
                        paymentRequest = PaymentRequest(
                            destinations: paymentRequest.destinations,
                            amount: paymentRequest.amount,
                            label: paymentRequest.label,
                            message: paymentRequest.message,
                            originalString: resolved.originalAddress
                        )
                        
                        // Lock in the payment request (ranks destinations, selects optimal, pre-fills amount)
                        currentPaymentRequest = paymentRequest
                        rankedDestinations = paymentRequest.rankedDestinations(context: paymentContext)
                        
                        if let optimal = rankedDestinations.first(where: { $0.viable }) {
                            selectedDestination = optimal.destination
                            logger.debug("   → Selected optimal destination: \(optimal.destination.format.rawValue)")
                            error = nil
                        } else {
                            error = "Cannot send to this contact - no viable payment methods"
                        }
                        
                        // Pre-fill amount if embedded in the payment request
                        if let requestAmount = paymentRequest.amount {
                            logger.debug("   → Pre-filling amount: \(requestAmount) sats")
                            amount = "\(requestAmount)"
                        }
                        
                        // Calculate fees based on destination type
                        await calculateLightningFee()
                        await calculateArkFee()
                        
                        // Switch to contact mode
                        sendMode = .contact(contact)
                        return
                    }
                } catch {
                    logger.warning("   BIP-353 resolution failed: \(error.localizedDescription)")
                    
                    // Try Lightning Address as fallback
                    do {
                        let lightningResolved = try await LightningAddressResolver.resolve(recipient)
                        logger.info("   Lightning Address resolved successfully!")
                        logger.debug("      → Address: \(lightningResolved.originalAddress)")
                        logger.debug("      → Min: \(lightningResolved.minSendableSats) sats, Max: \(lightningResolved.maxSendableSats) sats")
                        
                        // Create Lightning destination
                        let lightningDestination = PaymentDestination(
                            format: .lightning,
                            network: nil,
                            address: recipient
                        )
                        
                        let paymentRequest = PaymentRequest(
                            destinations: [lightningDestination],
                            amount: nil,
                            label: nil,
                            message: nil,
                            originalString: recipient
                        )
                        
                        currentPaymentRequest = paymentRequest
                        rankedDestinations = paymentRequest.rankedDestinations(context: paymentContext)
                        
                        if let optimal = rankedDestinations.first(where: { $0.viable }) {
                            selectedDestination = optimal.destination
                            logger.debug("   → Selected optimal destination: \(optimal.destination.format.rawValue)")
                            self.error = nil
                        } else {
                            self.error = "Cannot send to this contact - no viable payment methods"
                        }
                        
                        await calculateLightningFee()
                        await calculateArkFee()
                        
                        sendMode = .contact(contact)
                        return
                        
                    } catch let lightningError {
                        logger.warning("   Lightning Address resolution also failed: \(lightningError.localizedDescription)")
                        self.error = "Could not resolve address. BIP-353: \(error.localizedDescription), Lightning: \(lightningError.localizedDescription)"
                        sendMode = .manual
                        return
                    }
                }
            }
            
            // Parse the recipient address (non-BIP-353 or fallback)
            if let paymentRequest = AddressValidator.parsePaymentRequest(recipient) {
                logger.debug("   → Parsed payment request")
                logger.debug("      → Destinations: \(paymentRequest.destinations.count)")
                for (index, dest) in paymentRequest.destinations.enumerated() {
                    logger.debug("         [\(index)] format: \(dest.format.rawValue), address: \(dest.shortAddress)")
                }
                
                // Lock in the payment request (ranks destinations, selects optimal, pre-fills amount)
                currentPaymentRequest = paymentRequest
                rankedDestinations = paymentRequest.rankedDestinations(context: paymentContext)
                
                if let optimal = rankedDestinations.first(where: { $0.viable }) {
                    selectedDestination = optimal.destination
                    logger.debug("   → Selected optimal destination: \(optimal.destination.format.rawValue)")
                    error = nil
                } else {
                    error = "Cannot send to this contact - no viable payment methods"
                }
                
                // Pre-fill amount if embedded in the payment request
                if let requestAmount = paymentRequest.amount {
                    logger.debug("   → Pre-filling amount: \(requestAmount) sats")
                    amount = "\(requestAmount)"
                }
                
                // Calculate fees based on destination type
                await calculateLightningFee()
                await calculateArkFee()
                
                // Switch to contact mode
                sendMode = .contact(contact)
            } else {
                error = "Invalid contact address"
                sendMode = .manual
            }
            return
        }
        
        // Check for pre-filled recipient (second priority)
        if let recipient = prefilledRecipient {
            logger.info("Pre-filling recipient: \(recipient)")
            
            // Parse the pre-filled recipient
            if let paymentRequest = AddressValidator.parsePaymentRequest(recipient) {
                // Simple bare address - use manual mode for traditional flow
                // Rich payment request with metadata - use quick mode for better UX
                // Pre-filled recipients are treated as manual source since they could come from various places
                if isSimplePaymentRequest(paymentRequest) {
                    lockInPaymentRequest(paymentRequest)
                } else {
                    await enterQuickMode(paymentRequest: paymentRequest, source: .manual)
                }
            } else {
                // Invalid pre-filled recipient, show in manual input
                manualInput = recipient
                error = "Invalid pre-filled address"
                sendMode = .manual
            }
            return
        }
        
        // No pre-filled data - start in manual mode
        // Don't check clipboard automatically to avoid permission dialogs
        // User can tap the paste button if they want to paste from clipboard
        sendMode = .manual
    }
}
