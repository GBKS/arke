//
//  SendViewModel+PaymentExecution.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Payment execution with routing to different payment methods
//  (onchain, Lightning, Ark) and LNURL-pay invoice resolution.
//

import SwiftUI
import ArkeUI
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - LNURL-Pay Resolution
    
    /// Requests a Lightning invoice from an LNURL-pay callback URL
    private func requestLightningInvoice(callback: String, amountMillisats: Int, comment: String?) async throws -> String {
        // Construct the callback URL with amount parameter
        guard var urlComponents = URLComponents(string: callback) else {
            throw SendError.invalidFormat("Invalid LNURL-pay callback URL")
        }
        
        // Add amount parameter (in millisatoshis)
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "amount", value: String(amountMillisats)))
        
        // Add comment if provided
        if let comment = comment, !comment.isEmpty {
            queryItems.append(URLQueryItem(name: "comment", value: comment))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw SendError.invalidFormat("Failed to construct LNURL-pay callback URL")
        }
        
        // Make the HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30  // Increased to 30 seconds for slow LNURL servers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        logger.debug("   → Requesting invoice from: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        logger.debug("   → Received response (\(data.count) bytes)")
        
        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                logger.error("   HTTP \(httpResponse.statusCode): \(body)")
                throw SendError.invalidFormat("LNURL-pay callback returned HTTP \(httpResponse.statusCode)")
            }
        }
        
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? "(binary data)"
            logger.error("   Invalid JSON response: \(body)")
            throw SendError.invalidFormat("Invalid JSON response from LNURL-pay callback")
        }
        
        logger.debug("   → Response JSON: \(json)")
        
        // Check for error response
        if let status = json["status"] as? String, status == "ERROR" {
            let reason = json["reason"] as? String ?? "Unknown error"
            throw SendError.invalidFormat("LNURL-pay error: \(reason)")
        }
        
        // Extract the invoice (pr = payment request)
        guard let invoice = json["pr"] as? String else {
            throw SendError.invalidFormat("No invoice returned from LNURL-pay callback")
        }
        
        return invoice
    }
    
    // MARK: - Payment Execution
    
    /// Executes the payment using the current send state
    func executeSend(paymentRequest: PaymentRequest? = nil, destinationId: UUID? = nil, amount: String? = nil) async throws {
        logger.info("executeSend() called")
        logger.debug("   → paymentRequest provided: \(paymentRequest != nil)")
        logger.debug("   → destinationId provided: \(destinationId?.uuidString ?? "nil")")
        logger.debug("   → amount provided: \(amount ?? "nil")")
        
        // Compute ranked destinations from payment request if provided, otherwise use state
        let rankedDestinations: [PaymentDestinationSelector.RankedDestination]
        if let request = paymentRequest {
            rankedDestinations = await request.rankedDestinations(context: paymentContext)
            logger.debug("   → Using payment request with \(request.destinations.count) destination(s)")
            for (index, dest) in request.destinations.enumerated() {
                logger.debug("      [\(index)] format: \(dest.format.rawValue), address: \(dest.shortAddress)")
            }
        } else {
            rankedDestinations = self.rankedDestinations
            logger.debug("   → Using state rankedDestinations: \(rankedDestinations.count)")
        }
        
        // Determine the destination to use
        let destination: PaymentDestination
        if let destId = destinationId,
           let found = rankedDestinations.first(where: { $0.destination.id == destId })?.destination {
            destination = found
            logger.debug("   → Selected destination by ID: \(destination.format.rawValue)")
        } else if let selected = selectedDestination {
            destination = selected
            logger.debug("   → Using selectedDestination: \(destination.format.rawValue)")
        } else if let firstViable = rankedDestinations.first(where: { $0.viable })?.destination {
            destination = firstViable
            logger.debug("   → Using first viable destination: \(destination.format.rawValue)")
        } else {
            logger.error("   No viable destination found!")
            throw SendError.noDestinationSelected
        }
        
        logger.debug("   → Final destination format: \(destination.format.rawValue)")
        logger.debug("   → Final destination address: \(destination.address)")
        logger.debug("   → Final destination network: \(destination.network?.displayName ?? "N/A")")
        
        // Check if amount is locked (Lightning invoice with embedded amount)
        let amountLocked: Bool
        if let request = paymentRequest {
            amountLocked = destination.format == .lightningInvoice && request.amount != nil
            logger.debug("   → amountLocked computed from paymentRequest: \(amountLocked) (format: \(destination.format.rawValue), request.amount: \(request.amount ?? 0))")
        } else {
            amountLocked = isAmountLocked
            logger.debug("   → amountLocked from state: \(amountLocked)")
        }
        
        logger.debug("   → Final amountLocked: \(amountLocked)")
        
        // For Lightning invoices with embedded amounts, we don't need to validate the amount field
        if amountLocked {
            logger.debug("   → Taking amountLocked early return path (line 152)")
            logger.debug("   → Will call payLightningInvoice with nil amount")
            error = nil
            
            // Pay the Lightning invoice without passing an amount
            let status = try await walletManager.payLightningInvoice(invoice: destination.address, amountSats: nil)
            // Log payment status for debugging
            switch status {
            case .paid(let paymentHash, let preimage):
                logger.info("   Payment settled immediately, hash: \(String(paymentHash.prefix(16)))..., preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                logger.info("   Payment in progress, fee: \(send.feeSats) sats")
            case .unknown:
                logger.warning("   Payment status unknown")
            }
            return
        }
        
        // Determine the amount to use (parameter override or state)
        let amountString = amount ?? self.amount
        logger.debug("   → Amount string to parse: '\(amountString)'")
        
        // For all other cases, validate the amount field
        guard let amountInt = Int(amountString) else {
            logger.error("   ❌ Failed to parse amount as Int: '\(amountString)'")
            throw SendError.invalidAmount
        }
        logger.debug("   → Parsed amount: \(amountInt) sats")
        
        // Validate amount against viability using FRESH balance data and REAL fee estimates
        // The ranking now includes real Lightning fee estimation via the paymentContext
        let freshRanking = await PaymentDestinationSelector.rankDestination(
            destination,
            amount: amountInt,
            context: paymentContext  // This reads CURRENT balance from walletManager and estimates fees
        )
        logger.debug("   → Fresh ranking: viable=\(freshRanking?.viable ?? false), reason=\(freshRanking?.reason ?? "nil")")
        
        // Use fresh ranking, or fall back to cached ranking if fresh ranking failed
        if let ranked = freshRanking ?? rankedDestinations.first(where: { $0.destination.id == destination.id }) {
            logger.debug("   → Using ranking: viable=\(ranked.viable), availableBalance=\(ranked.availableBalance ?? -1), estimatedFee=\(ranked.estimatedFee ?? -1)")
            
            if !ranked.viable {
                logger.error("   ❌ Destination not viable: \(ranked.reason)")
                throw SendError.destinationNotViable(ranked.reason)
            }
            
            // Check if amount + fee exceeds available balance
            let totalRequired = amountInt + (ranked.estimatedFee ?? 0)
            if let availableBalance = ranked.availableBalance, totalRequired > availableBalance {
                logger.error("   ❌ Insufficient balance: need \(totalRequired) sats, have \(availableBalance) sats")
                throw SendError.insufficientBalance(required: totalRequired, available: availableBalance)
            }
            logger.debug("   ✅ Balance check passed: totalRequired=\(totalRequired), availableBalance=\(ranked.availableBalance ?? -1)")
        } else {
            logger.warning("   ⚠️ No ranking available (fresh or cached) - skipping viability check")
        }
        
        error = nil
        
        // Route to the appropriate payment method based on destination format
        logger.info("   → ROUTING payment to format: \(destination.format.rawValue)")
        logger.debug("   → About to enter switch statement for payment routing")
        
        switch destination.format {
        case .bitcoin, .silentPayments:
            logger.info("   → Sending onchain to: \(destination.address)")
            let feeRate = onchainFeeRates.rate(for: selectedFeePriority)
            logger.debug("   → Using fee rate: \(feeRate) sat/vB (priority: \(self.selectedFeePriority.rawValue))")
            _ = try await walletManager.sendOnchain(to: destination.address, amount: amountInt, feeRateSatPerVb: feeRate)
            
        case .lightningInvoice:
            // Check if the invoice already has an embedded amount
            let invoiceHasAmount = paymentRequest?.amount != nil || currentPaymentRequest?.amount != nil
            logger.info("   → Paying Lightning invoice: \(destination.shortAddress)")
            logger.debug("   → Invoice has embedded amount: \(invoiceHasAmount)")
            
            // For send-max operations with no embedded amount, implement retry logic
            if isSendingMax && !invoiceHasAmount {
                logger.debug("   → Send-max mode: enabling retry logic")
                try await executeWithRetry(
                    destination: destination,
                    initialAmount: amountInt,
                    maxRetries: 3
                )
            } else {
                // Normal payment - no retry
                let status: LightningSendStatus
                if invoiceHasAmount {
                    status = try await walletManager.payLightningInvoice(invoice: destination.address, amountSats: nil)
                } else {
                    status = try await walletManager.payLightningInvoice(invoice: destination.address, amountSats: UInt64(amountInt))
                }
                logLightningPaymentStatus(status, label: "Lightning invoice payment")
            }
            
        case .lightning:
            // Lightning address - use the direct FFI method
            logger.info("   → Paying Lightning address: \(destination.address)")
            
            // For send-max operations, implement retry logic with fee adjustment
            if isSendingMax {
                logger.debug("   → Send-max mode: enabling retry logic")
                try await executeWithRetry(
                    destination: destination,
                    initialAmount: amountInt,
                    maxRetries: 3
                )
            } else {
                // Normal payment - no retry
                let status = try await walletManager.payLightningAddress(
                    lightningAddress: destination.address,
                    amountSats: UInt64(amountInt),
                    comment: nil
                )
                logLightningPaymentStatus(status, label: "Lightning address payment")
            }
            
        case .lnurl:
            logger.info("   → Paying LNURL: \(destination.address)")
            
            // Get resolved LNURL data (should be cached from clipboard/QR resolution)
            if resolvedLNURL == nil {
                // Fallback: resolve now if not cached
                logger.debug("   → LNURL not cached, resolving now...")
                resolvedLNURL = try await LNURLResolver.resolve(destination.address)
            }
            
            guard let lnurlData = resolvedLNURL else {
                throw SendError.invalidFormat("LNURL resolution failed")
            }
            
            // Validate amount is within LNURL limits
            if amountInt < lnurlData.minSendableSats || amountInt > lnurlData.maxSendableSats {
                throw SendError.invalidFormat("Amount must be between \(lnurlData.minSendableSats) and \(lnurlData.maxSendableSats) sats")
            }
            
            // Request invoice from LNURL callback
            logger.debug("   → Requesting invoice from LNURL callback...")
            let amountMillisats = amountInt * 1000
            let invoice = try await requestLightningInvoice(
                callback: lnurlData.callback,
                amountMillisats: amountMillisats,
                comment: nil  // No comment support in v1
            )
            
            logger.debug("   → Got invoice: \(invoice)")
            
            // Verify invoice amount matches requested amount
            if let parsedInvoice = try? LightningInvoiceParser.parse(invoice),
               let invoiceAmount = parsedInvoice.amountSatoshis,
               invoiceAmount != UInt64(amountInt) {
                throw SendError.invalidFormat("Invoice amount (\(invoiceAmount) sats) doesn't match requested amount (\(amountInt) sats)")
            }
            
            // Pay the invoice via Bark (existing flow)
            logger.debug("   → Paying invoice via Bark...")
            let status = try await walletManager.payLightningInvoice(
                invoice: invoice,
                amountSats: nil  // Amount is embedded in invoice
            )
            // Log payment status
            switch status {
            case .paid(let paymentHash, let preimage):
                logger.info("   LNURL payment settled, hash: \(String(paymentHash.prefix(16)))..., preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                logger.info("   LNURL payment in progress, fee: \(send.feeSats) sats")
            case .unknown:
                logger.warning("   LNURL payment status unknown")
            }
            
        case .bolt12:
            // BOLT12 offers require explicit amount and use dedicated payment method
            // The offer is resolved into an invoice internally by the wallet
            logger.info("   → Paying BOLT12 offer: \(destination.shortAddress)")
            
            // For send-max operations, implement retry logic
            if isSendingMax {
                logger.debug("   → Send-max mode: enabling retry logic")
                try await executeWithRetry(
                    destination: destination,
                    initialAmount: amountInt,
                    maxRetries: 3
                )
            } else {
                // Normal payment - no retry
                let status = try await walletManager.payLightningOffer(offer: destination.address, amountSats: UInt64(amountInt))
                logLightningPaymentStatus(status, label: "BOLT12 payment")
            }
            
        case .ark:
            logger.info("   → Sending Ark to: \(destination.address)")
            _ = try await walletManager.send(to: destination.address, amount: amountInt)
            
        case .bip353:
            // BIP-353 should have been resolved to another format by now
            // This is a fallback - try to send as Ark
            logger.warning("   WARNING: BIP-353 destination reached executeSend without resolution!")
            logger.warning("   → BIP-353 address: \(destination.address)")
            logger.warning("   → Attempting to send as Ark (this will likely fail)")
            _ = try await walletManager.send(to: destination.address, amount: amountInt)
            
        case .bip21:
            // BIP-21 should never be a final destination format
            logger.error("   ERROR: BIP-21 destination reached executeSend!")
            throw SendError.invalidFormat("BIP-21 is a wrapper format and should be resolved before sending")
        }
    }
    
    // MARK: - Retry Logic for Send-Max
    
    /// Executes a Lightning payment with retry logic for send-max operations
    /// Automatically adjusts amount downward if payment fails due to routing fee differences
    private func executeWithRetry(
        destination: PaymentDestination,
        initialAmount: Int,
        maxRetries: Int
    ) async throws {
        var currentAmount = initialAmount
        var attemptNumber = 1
        
        while attemptNumber <= maxRetries {
            logger.info("   → Attempt \(attemptNumber)/\(maxRetries): Trying amount \(currentAmount) sats")
            
            do {
                let status: LightningSendStatus
                
                switch destination.format {
                case .lightning:
                    status = try await walletManager.payLightningAddress(
                        lightningAddress: destination.address,
                        amountSats: UInt64(currentAmount),
                        comment: nil
                    )
                case .lightningInvoice:
                    status = try await walletManager.payLightningInvoice(
                        invoice: destination.address,
                        amountSats: UInt64(currentAmount)
                    )
                case .bolt12:
                    status = try await walletManager.payLightningOffer(
                        offer: destination.address,
                        amountSats: UInt64(currentAmount)
                    )
                default:
                    throw SendError.invalidFormat("Unsupported format for retry logic")
                }
                
                // Payment succeeded
                logLightningPaymentStatus(status, label: "Send-max payment (attempt \(attemptNumber))")
                logger.info("   ✅ Send-max payment succeeded on attempt \(attemptNumber)")
                return
                
            } catch {
                logger.warning("   ⚠️ Attempt \(attemptNumber) failed: \(error)")
                
                // Check if this looks like an insufficient balance error
                let errorString = error.localizedDescription.lowercased()
                if errorString.contains("insufficient") || errorString.contains("balance") {
                    // Reduce amount and retry
                    if attemptNumber < maxRetries {
                        // Reduce by 10 sats each retry (conservative adjustment for routing fee variance)
                        currentAmount -= 10
                        
                        if currentAmount <= 0 {
                            logger.error("   ❌ Amount reduced to zero or below, cannot retry")
                            throw error
                        }
                        
                        logger.info("   → Reducing amount to \(currentAmount) sats and retrying...")
                        attemptNumber += 1
                    } else {
                        logger.error("   ❌ Max retries reached, payment failed")
                        throw error
                    }
                } else {
                    // Different error type, don't retry
                    logger.error("   ❌ Non-balance error, not retrying: \(error)")
                    throw error
                }
            }
        }
    }
    
    /// Helper to log Lightning payment status consistently
    private func logLightningPaymentStatus(_ status: LightningSendStatus, label: String) {
        switch status {
        case .paid(let paymentHash, let preimage):
            logger.info("   \(label) settled, hash: \(String(paymentHash.prefix(16)))..., preimage: \(String(preimage.prefix(16)))...")
        case .inProgress(let send):
            logger.info("   \(label) in progress, fee: \(send.feeSats) sats")
        case .unknown:
            logger.warning("   \(label) status unknown")
        }
    }
    
    // MARK: - Error Definitions
    
    /// Custom errors for send operations
    enum SendError: LocalizedError {
        case noDestinationSelected
        case invalidAmount
        case destinationNotViable(String)
        case insufficientBalance(required: Int, available: Int)
        case invalidFormat(String)
        
        var errorDescription: String? {
            switch self {
            case .noDestinationSelected:
                return "No payment destination selected"
            case .invalidAmount:
                return "Invalid amount"
            case .destinationNotViable(let reason):
                return "Cannot send: \(reason)"
            case .insufficientBalance(let required, let available):
                return "Amount + fees (\(required) sats) exceeds available balance (\(available) sats)"
            case .invalidFormat(let message):
                return message
            }
        }
    }
    
}
