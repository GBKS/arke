//
//  SendViewModel+Clipboard.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Clipboard operations including detection, parsing, and resolution
//  of payment requests (BIP-353, Lightning Address, BIP-21, invoices).
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Clipboard Availability
    
    /// Checks if clipboard has string content without reading it
    /// On iOS, this is less intrusive and doesn't trigger permission dialogs
    /// On macOS, this freely checks the clipboard
    func checkClipboardAvailability() {
        hasClipboardContent = clipboardService.hasStrings()
        logger.debug("Clipboard availability check: \(self.hasClipboardContent)")
    }
    
    // MARK: - Clipboard Payment Detection
    
    /// Checks clipboard for valid payment requests
    /// This is called when the user explicitly taps the paste button
    /// Returns true if valid payment info was found and processed
    func checkClipboardForAddress() async -> Bool {
        // Only check if we're in manual entry mode
        /*
        guard case .manual = sendMode else {
            logger.debug("Not in manual mode, skipping clipboard check")
            return false
        }
        */
        
        guard let clipboardString = clipboardService.getCurrentString() else {
            logger.debug("No clipboard content found")
            return false
        }
        
        let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("Checking clipboard content: \(trimmedString)")
        
        // Don't clear state yet - only clear after confirming valid payment data
        // This prevents losing user's partial input if clipboard has invalid data
        
        // Check if this looks like a user@domain format (ambiguous between BIP-353 and Lightning Address)
        let isUserAtDomainFormat = BIP353Resolver.isBIP353Format(trimmedString) || 
                                   LightningAddressResolver.isLightningAddressFormat(trimmedString)
        
        if isUserAtDomainFormat && !trimmedString.hasPrefix("₿") {
            // Ambiguous format - try both BIP-353 and Lightning Address in parallel
            logger.debug("Detected ambiguous user@domain format: \(trimmedString)")
            logger.debug("   → Trying BIP-353 and Lightning Address in parallel...")
            
            return await tryParallelResolution(trimmedString)
        }
        
        // Extract the actual LNURL if it has a lightning: prefix
        let actualLNURL: String
        if trimmedString.lowercased().hasPrefix("lightning:") {
            actualLNURL = String(trimmedString.dropFirst(10))
        } else {
            actualLNURL = trimmedString
        }
        
        // Check for LNURL format
        if LNURLResolver.isLNURL(actualLNURL) {
            logger.debug("Detected LNURL: \(actualLNURL)")
            if actualLNURL != trimmedString {
                logger.debug("   → Original had lightning: prefix")
            }
            
            do {
                let resolved = try await LNURLResolver.resolve(actualLNURL)
                logger.info("LNURL resolved successfully!")
                logger.debug("   → Min: \(resolved.minSendableSats) sats, Max: \(resolved.maxSendableSats) sats")
                logger.debug("   → Callback: \(resolved.callback)")
                
                // Check if this is a fixed-amount request (point-of-sale scenario)
                if resolved.isFixedAmount {
                    logger.debug("   Fixed amount detected: \(resolved.fixedAmountSats!) sats (POS mode)")
                }
                
                // Store resolved LNURL for later use during payment
                await MainActor.run {
                    self.resolvedLNURL = resolved
                }
                
                // Parse the LNURL as a payment request (use original trimmedString to preserve lightning: prefix if present)
                guard var paymentRequest = AddressValidator.parsePaymentRequest(trimmedString) else {
                    self.error = "Failed to parse LNURL payment request"
                    return false
                }
                
                // If this is a fixed-amount LNURL, pre-fill the amount
                if let fixedAmount = resolved.fixedAmountSats {
                    logger.debug("   → Pre-filling fixed amount into payment request")
                    paymentRequest = PaymentRequest(
                        destinations: paymentRequest.destinations,
                        amount: fixedAmount,
                        label: paymentRequest.label,
                        message: paymentRequest.message,
                        originalString: paymentRequest.originalString
                    )
                }
                
                // Process the payment request with the amount pre-filled
                return await processClipboardPaymentRequest(paymentRequest)
            } catch {
                logger.error("LNURL resolution failed: \(error.localizedDescription)")
                self.error = "Failed to resolve LNURL: \(error.localizedDescription)"
                return false
            }
        }
        
        // Unambiguous BIP-353 (has ₿ prefix)
        if trimmedString.hasPrefix("₿") && BIP353Resolver.isBIP353Format(trimmedString) {
            logger.debug("Detected unambiguous BIP-353 address: \(trimmedString)")
            
            do {
                let resolved = try await BIP353Resolver.resolve(trimmedString)
                logger.info("BIP-353 resolved successfully!")
                logger.debug("   → Original BIP-353: \(resolved.originalAddress)")
                logger.debug("   → Resolved BIP-21 URI: \(resolved.bip21URI)")
                logger.debug("   → DNSSEC verified: \(resolved.dnssecVerified)")
                
                if !resolved.dnssecVerified {
                    logger.warning("Warning: DNSSEC validation failed for \(trimmedString)")
                    // For v1, just log - future: show security warning to user
                }
                
                return await processClipboardPaymentRequest(resolved.bip21URI, originalBIP353Address: resolved.originalAddress)
            } catch {
                logger.error("BIP-353 resolution failed: \(error.localizedDescription)")
                return false
            }
        }
        
        // Not a recognized address format, process as regular payment request
        return await processClipboardPaymentRequest(trimmedString)
    }
    
    // MARK: - Resolution Helpers
    
    /// Tries both BIP-353 and Lightning Address resolution in parallel for ambiguous user@domain formats
    /// Returns true if either resolution succeeds
    private func tryParallelResolution(_ address: String) async -> Bool {
        // Race both resolution methods - whichever succeeds first wins
        await withTaskGroup(of: ResolutionResult.self) { group in
            // Launch BIP-353 resolution
            group.addTask { [self] in
                do {
                    let resolved = try await BIP353Resolver.resolve(address)
                    self.logger.info("BIP-353 resolution won the race!")
                    self.logger.debug("   → Resolved BIP-21 URI: \(resolved.bip21URI)")
                    self.logger.debug("   → DNSSEC verified: \(resolved.dnssecVerified)")
                    
                    if !resolved.dnssecVerified {
                        self.logger.warning("Warning: DNSSEC validation failed for \(address)")
                    }
                    
                    return .bip353Success(resolved)
                } catch {
                    self.logger.error("BIP-353 resolution failed: \(error.localizedDescription)")
                    return .bip353Failure
                }
            }
            
            // Launch Lightning Address resolution
            group.addTask { [self] in
                do {
                    let resolved = try await LightningAddressResolver.resolve(address)
                    self.logger.info("Lightning Address resolution won the race!")
                    return .lightningSuccess(resolved)
                } catch {
                    self.logger.error("Lightning Address resolution failed: \(error.localizedDescription)")
                    return .lightningFailure
                }
            }
            
            // Wait for first successful result
            var bip353Failed = false
            var lightningFailed = false
            
            for await result in group {
                switch result {
                case .bip353Success(let resolved):
                    // BIP-353 succeeded - cancel other task and use this result
                    group.cancelAll()
                    return await processClipboardPaymentRequest(resolved.bip21URI, originalBIP353Address: resolved.originalAddress)
                    
                case .lightningSuccess:
                    // Lightning Address succeeded - cancel other task and use this result
                    group.cancelAll()
                    return await processClipboardPaymentRequest(address)
                    
                case .bip353Failure:
                    bip353Failed = true
                    
                case .lightningFailure:
                    lightningFailed = true
                }
                
                // If both have failed, give up
                if bip353Failed && lightningFailed {
                    logger.error("Both BIP-353 and Lightning Address resolution failed")
                    
                    // Final fallback: Try parsing as a regular address without validation
                    if AddressValidator.parsePaymentRequest(address) != nil {
                        logger.debug("Falling back to parsing as unvalidated address")
                        return await processClipboardPaymentRequest(address)
                    }
                    
                    return false
                }
            }
            
            return false
        }
    }
    
    /// Result type for parallel resolution
    private enum ResolutionResult {
        case bip353Success(BIP353Resolver.ResolvedBIP353)
        case bip353Failure
        case lightningSuccess(LightningAddressResolver.ResolvedLightningAddress)
        case lightningFailure
    }
    
    /// Attempts to resolve a Lightning Address, falling back to basic parsing if resolution fails
    /// Returns true if address was successfully processed
    private func tryLightningAddressFallback(_ address: String) async -> Bool {
        do {
            let resolved = try await LightningAddressResolver.resolve(address)
            logger.info("Lightning Address validated: \(resolved.originalAddress)")
            logger.debug("   → Min: \(resolved.minSendableSats) sats, Max: \(resolved.maxSendableSats) sats")
            
            // Lightning Address is valid, process it
            return await processClipboardPaymentRequest(address)
        } catch {
            logger.error("Lightning Address resolution failed: \(error.localizedDescription)")
            
            // Final fallback: Try parsing as a regular address without validation
            if AddressValidator.parsePaymentRequest(address) != nil {
                logger.debug("Falling back to parsing as unvalidated Lightning Address")
                return await processClipboardPaymentRequest(address)
            } else {
                logger.debug("Address is not a valid payment request")
                return false
            }
        }
    }
    
    /// Processes a payment request string from clipboard and shows it in the UI
    /// - Parameters:
    ///   - paymentString: The payment request string (BIP-21 URI, address, invoice, etc.)
    ///   - originalBIP353Address: The original BIP-353 address if this was resolved from one
    /// - Returns: true if payment request was successfully processed
    private func processClipboardPaymentRequest(_ paymentString: String, originalBIP353Address: String? = nil) async -> Bool {
        logger.debug("processClipboardPaymentRequest()")
        logger.debug("   → paymentString: \(paymentString)")
        logger.debug("   → originalBIP353Address: \(originalBIP353Address ?? "nil")")
        
        // Check if clipboard contains a valid payment request
        guard var paymentRequest = AddressValidator.parsePaymentRequest(paymentString) else {
            logger.error("   Clipboard content is not a valid payment request")
            return false
        }
        
        logger.info("   Payment request parsed successfully")
        
        // Now that we have valid payment data, clear existing state
        logger.debug("Clearing existing state before applying clipboard data")
        manualInput = ""
        amount = ""
        error = nil
        selectedDestination = nil
        rankedDestinations = []
        currentPaymentRequest = nil
        recipientState = .idle
        logger.debug("   → Initial destinations count: \(paymentRequest.destinations.count)")
        for (index, dest) in paymentRequest.destinations.enumerated() {
            logger.debug("      [\(index)] format: \(dest.format.rawValue), address: \(dest.shortAddress)")
        }
        
        // If this was resolved from a BIP-353 address, preserve that as the original string
        if let bip353Address = originalBIP353Address {
            logger.debug("   → Preserving BIP-353 address as originalString: \(bip353Address)")
            paymentRequest = PaymentRequest(
                destinations: paymentRequest.destinations,
                amount: paymentRequest.amount,
                label: paymentRequest.label,
                message: paymentRequest.message,
                originalString: bip353Address  // Store the human-readable BIP-353 address
            )
        }
        
        // Debug log all payment request details from clipboard
        logger.debug("   Final payment request details:")
        if let bip353 = originalBIP353Address {
            logger.debug("      Resolved from BIP-353: \(bip353)")
        }
        logger.debug("      Destinations: \(paymentRequest.destinations.count)")
        if let primary = paymentRequest.primaryDestination {
            logger.debug("      Primary format: \(primary.format.rawValue) (\(primary.format.displayName))")
            logger.debug("      Primary network: \(primary.network?.displayName ?? "N/A")")
            logger.debug("      Primary address: \(primary.address)")
        }
        logger.debug("      Amount: \(paymentRequest.amount?.description ?? "N/A") sats")
        logger.debug("      Label: \(paymentRequest.label ?? "N/A")")
        logger.debug("      Message: \(paymentRequest.message ?? "N/A")")
        logger.debug("      Has alternatives: \(paymentRequest.hasAlternatives)")
        
        if paymentRequest.hasAlternatives {
            logger.debug("      Alternative destinations:")
            for (index, dest) in paymentRequest.alternativeDestinations.enumerated() {
                logger.debug("         [\(index + 1)] \(dest.format.displayName): \(dest.shortAddress)")
            }
        }
        
        // Always use quick mode for clipboard paste to match QR scanner behavior
        // This provides consistency: automatic input (scan/paste) → quick mode
        logger.debug("   → Using quick mode (clipboard paste)")
        await enterQuickMode(paymentRequest: paymentRequest, source: .clipboard)
        
        return true
    }
    
    /// Processes a pre-parsed payment request from clipboard
    /// This overload is used when the PaymentRequest has already been created and modified
    /// (e.g., for LNURL with fixed amounts pre-filled)
    /// - Parameter paymentRequest: The pre-parsed and potentially modified payment request
    /// - Returns: true if payment request was successfully processed
    private func processClipboardPaymentRequest(_ paymentRequest: PaymentRequest) async -> Bool {
        logger.debug("processClipboardPaymentRequest() [PaymentRequest overload]")
        logger.debug("   → Destinations: \(paymentRequest.destinations.count)")
        logger.debug("   → Amount: \(paymentRequest.amount?.description ?? "N/A") sats")
        
        // Clear existing state
        logger.debug("Clearing existing state before applying clipboard data")
        manualInput = ""
        amount = ""
        error = nil
        selectedDestination = nil
        rankedDestinations = []
        currentPaymentRequest = nil
        recipientState = .idle
        
        // Debug log all payment request details
        logger.debug("   Payment request details:")
        logger.debug("      Destinations: \(paymentRequest.destinations.count)")
        if let primary = paymentRequest.primaryDestination {
            logger.debug("      Primary format: \(primary.format.rawValue) (\(primary.format.displayName))")
            logger.debug("      Primary network: \(primary.network?.displayName ?? "N/A")")
            logger.debug("      Primary address: \(primary.address)")
        }
        logger.debug("      Amount: \(paymentRequest.amount?.description ?? "N/A") sats")
        logger.debug("      Label: \(paymentRequest.label ?? "N/A")")
        logger.debug("      Message: \(paymentRequest.message ?? "N/A")")
        logger.debug("      Has alternatives: \(paymentRequest.hasAlternatives)")
        
        if paymentRequest.hasAlternatives {
            logger.debug("      Alternative destinations:")
            for (index, dest) in paymentRequest.alternativeDestinations.enumerated() {
                logger.debug("         [\(index + 1)] \(dest.format.displayName): \(dest.shortAddress)")
            }
        }
        
        // Always use quick mode for clipboard paste to match QR scanner behavior
        logger.debug("   → Using quick mode (clipboard paste)")
        await enterQuickMode(paymentRequest: paymentRequest, source: .clipboard)
        
        return true
    }
}
