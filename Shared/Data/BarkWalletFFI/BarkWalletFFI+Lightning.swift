//
//  BarkWalletFFI+Lightning.swift
//  Arke
//
//  Lightning Network operations: invoices, payments, BOLT11/BOLT12
//  Handles send/receive flows and payment claiming
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - Lightning Payment (Send)
    
    func payLightningInvoice(invoice: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus {
        // Pay a Lightning invoice with optional amount
        // If amount is provided, use it; otherwise invoice should have amount encoded
        
        if isPreview {
            let send = LightningSend(invoice: invoice, amountSats: amountSats ?? 0, feeSats: 50, htlcVtxoCount: 1, hasFailedRevocation: false)
            return .inProgress(send: send)
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        // Validate amount if provided
        if let amount = amountSats {
            guard amount > 0 else {
                throw BarkWalletFFIError.configurationError("Amount must be greater than 0")
            }
        }
        
        // Use amount directly (already UInt64?)
        let amountSats = amountSats
        
        if let amount = amountSats {
            Self.logger.debug("Paying Lightning invoice via FFI, Invoice: \(String(invoice.prefix(30)))..., Amount: \(amount) sats (explicit), Wait: \(wait)")
        } else {
            Self.logger.debug("Paying Lightning invoice via FFI, Invoice: \(String(invoice.prefix(30)))..., Amount: from invoice, Wait: \(wait)")
        }
        
        do {
            // Call FFI payLightningInvoice with optional amount and wait parameter
            let status = try await wallet.payLightningInvoice(
                invoice: invoice,
                amountSats: amountSats,
                wait: wait
            )
            
            // Log based on status
            switch status {
            case .paid(let paymentHash, let preimage):
                Self.logger.info("Lightning payment settled, Payment hash: \(String(paymentHash.prefix(16)))..., Preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                Self.logger.info("Lightning payment in progress, Invoice: \(send.invoice), Amount: \(send.amountSats) sats, Fee: \(send.feeSats) sats")
                
                // Extract payment hash and poll for settlement in background
                if let paymentHash = LightningInvoiceParser.extractPaymentHash(fromInvoice: send.invoice) {
                    Task {
                        await pollLightningPaymentStatus(paymentHash: paymentHash)
                    }
                } else {
                    Self.logger.warning("Could not extract payment hash from invoice: \(String(send.invoice.prefix(30)))...")
                }
            case .unknown:
                Self.logger.warning("Lightning payment status unknown after payment attempt")
            }
            
            // Return status
            return status
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error paying Lightning invoice: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to pay Lightning invoice: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error paying Lightning invoice: \(error)")
            throw error
        }
    }
    
    // MARK: - Lightning Invoice Generation (Receive)
    
    func getLightningInvoice(amountSats: UInt64, description: String?) async throws -> String {
        // Generate a Lightning invoice for receiving payment
        
        if isPreview {
            return "lnbc\(amountSats)0n1preview..."
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        // Validate amount
        guard amountSats > 0 else {
            throw BarkWalletFFIError.configurationError("Amount must be greater than 0")
        }
        
        Self.logger.debug("Generating Lightning invoice via FFI, Amount: \(amountSats) sats")
        
        do {
            // Call FFI bolt11Invoice method
            let result = try await wallet.bolt11Invoice(amountSats: amountSats, description: description)
            
            Self.logger.info("Lightning invoice generated, Amount: \(result.amountSats) sats, Invoice: \(String(result.invoice.prefix(30)))...")
            
            // Return the invoice string
            return result.invoice
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error generating Lightning invoice: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to generate Lightning invoice: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error generating Lightning invoice: \(error)")
            throw error
        }
    }
    
    func getLightningInvoiceStatus(invoice: String) async throws -> String {
        // Check the status of a Lightning invoice
        
        if isPreview {
            return "Mock: Invoice status - pending (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Checking Lightning invoice status via FFI, Invoice: \(String(invoice.prefix(30)))...")
        
        do {
            // Call FFI pendingLightningReceives method
            let pendingReceives = try await wallet.pendingLightningReceives()
            
            // Find the invoice in pending receives
            if let receiveStatus = pendingReceives.first(where: { $0.invoice == invoice }) {
                Self.logger.info("Found invoice in pending receives")
                
                // Build status string
                var status = "Invoice Status:\n"
                status += "  Payment Hash: \(receiveStatus.paymentHash)\n"
                status += "  Amount: \(receiveStatus.amountSats) sats\n"
                status += "  State: \(receiveStatus.state)\n"

                switch receiveStatus.state {
                case "htlcs-ready":
                    status += "  Status: Pending (ready to claim)"
                case "preimage-revealed", "settled":
                    status += "  Status: Claimed"
                default: // "awaiting-payment"
                    status += "  Status: Waiting for payment"
                }

                return status
            } else {
                // Invoice not found in pending receives
                // It might be already claimed or never created
                Self.logger.warning("Invoice not found in pending receives")
                return "Invoice not found in pending receives. It may be already claimed or not yet paid."
            }
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error checking invoice status: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to check invoice status: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error checking invoice status: \(error)")
            throw error
        }
    }
    
    // MARK: - Invoice Status & Management
    
    func listLightningInvoices() async throws -> String {
        // List all Lightning invoices
        
        if isPreview {
            return "[]"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Listing Lightning invoices via FFI...")
        
        do {
            // Call FFI pendingLightningReceives method
            let pendingReceives = try await wallet.pendingLightningReceives()
            
            Self.logger.info("Retrieved \(pendingReceives.count) pending Lightning receives")
            
            // Convert to JSON array
            let invoiceList: [[String: Any]] = pendingReceives.map { receive in
                let status: String
                switch receive.state {
                case "htlcs-ready": status = "ready_to_claim"
                case "preimage-revealed", "settled": status = "claimed"
                default: status = "waiting" // "awaiting-payment"
                }
                return [
                    "payment_hash": receive.paymentHash,
                    "invoice": receive.invoice,
                    "amount_sats": receive.amountSats,
                    "state": receive.state,
                    "settled_at": receive.settledAt as Any,
                    "status": status
                ]
            }
            
            // Convert to JSON string
            let jsonData = try JSONSerialization.data(withJSONObject: invoiceList, options: [.prettyPrinted, .sortedKeys])
            
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw BarkWalletFFIError.configurationError("Failed to encode invoice list as JSON string")
            }
            
            return jsonString
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error listing invoices: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to list invoices: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error listing invoices: \(error)")
            throw error
        }
    }
    
    // MARK: - Claiming & Balance
    
    func claimLightningInvoice(invoice: String) async throws -> String {
        // Claim a specific paid Lightning invoice
        // FFI uses tryClaimAllLightningReceives() which claims all pending
        
        if isPreview {
            return "Mock: Claimed invoice (preview mode)"
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Claiming Lightning receives via FFI, Note: FFI claims ALL pending receives, not individual invoices")
        
        do {
            // Call FFI tryClaimAllLightningReceives
            // This claims all pending Lightning receives
            let _ = try await wallet.tryClaimAllLightningReceives(wait: true)
            
            Self.logger.info("Lightning receives claimed successfully, All pending receives have been processed")
            
            return "Successfully claimed all pending Lightning receives"
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error claiming Lightning receives: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to claim Lightning receives: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error claiming Lightning receives: \(error)")
            throw error
        }
    }
    
    func payLightningOffer(offer: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus {
        // Pay a BOLT12 lightning offer
        
        if isPreview {
            let send = LightningSend(invoice: "lnbc...", amountSats: amountSats ?? 0, feeSats: 50, htlcVtxoCount: 1, hasFailedRevocation: false)
            return .inProgress(send: send)
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        guard amountSats ?? 0 > 0 else {
            throw BarkWalletFFIError.configurationError("Amount must be greater than 0 for BOLT12 offers")
        }
        
        if let amt = amountSats {
            Self.logger.debug("Paying Lightning BOLT12 offer via FFI, Offer: \(String(offer.prefix(30)))..., Amount: \(amt) sats, Wait: \(wait)")
        } else {
            Self.logger.debug("Paying Lightning BOLT12 offer via FFI, Offer: \(String(offer.prefix(30)))..., Wait: \(wait)")
        }
        
        do {
            let status = try await wallet.payLightningOffer(offer: offer, amountSats: amountSats, wait: wait)
            
            switch status {
            case .paid(let paymentHash, let preimage):
                Self.logger.info("Lightning BOLT12 payment settled, Payment hash: \(String(paymentHash.prefix(16)))..., Preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                Self.logger.info("Lightning BOLT12 payment in progress, Invoice: \(String(send.invoice.prefix(30)))..., Amount: \(send.amountSats) sats, Fee: \(send.feeSats) sats")
            case .unknown:
                Self.logger.warning("Lightning BOLT12 payment status unknown")
            }
            
            return status
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error paying Lightning offer: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to pay Lightning offer: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error paying Lightning offer: \(error)")
            throw error
        }
    }
    
    func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus {
        // Pay a Lightning address (user@domain format)
        
        if isPreview {
            let send = LightningSend(invoice: "lnbc...", amountSats: amountSats, feeSats: 50, htlcVtxoCount: 1, hasFailedRevocation: false)
            return .inProgress(send: send)
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        guard amountSats > 0 else {
            throw BarkWalletFFIError.configurationError("Amount must be greater than 0 for Lightning addresses")
        }
        
        if let comment = comment {
            Self.logger.debug("Paying Lightning address via FFI, Address: \(lightningAddress), Amount: \(amountSats) sats, Comment: \(comment), Wait: \(wait)")
        } else {
            Self.logger.debug("Paying Lightning address via FFI, Address: \(lightningAddress), Amount: \(amountSats) sats, Wait: \(wait)")
        }
        
        do {
            let status = try await wallet.payLightningAddress(
                lightningAddress: lightningAddress,
                amountSats: amountSats,
                comment: comment,
                wait: wait
            )
            
            switch status {
            case .paid(let paymentHash, let preimage):
                Self.logger.info("Lightning address payment settled, Address: \(lightningAddress), Payment hash: \(String(paymentHash.prefix(16)))..., Preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                Self.logger.info("Lightning address payment in progress, Address: \(lightningAddress), Amount: \(send.amountSats) sats, Fee: \(send.feeSats) sats")
            case .unknown:
                Self.logger.warning("Lightning address payment status unknown")
            }
            
            return status
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error paying Lightning address: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to pay Lightning address: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error paying Lightning address: \(error)")
            throw error
        }
    }

    func payLnurl(lnurl: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus {
        // Pay an LNURL-pay endpoint (bech32-encoded `lnurl...` or Lightning address)

        if isPreview {
            let send = LightningSend(invoice: "lnbc...", amountSats: amountSats, feeSats: 50, htlcVtxoCount: 1, hasFailedRevocation: false)
            return .inProgress(send: send)
        }

        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        guard amountSats > 0 else {
            throw BarkWalletFFIError.configurationError("Amount must be greater than 0 for LNURL payments")
        }

        if let comment = comment {
            Self.logger.debug("Paying LNURL via FFI, Amount: \(amountSats) sats, Comment: \(comment), Wait: \(wait)")
        } else {
            Self.logger.debug("Paying LNURL via FFI, Amount: \(amountSats) sats, Wait: \(wait)")
        }

        do {
            let status = try await wallet.payLnurl(
                lnurl: lnurl,
                amountSats: amountSats,
                comment: comment,
                wait: wait
            )

            switch status {
            case .paid(let paymentHash, let preimage):
                Self.logger.info("LNURL payment settled, Payment hash: \(String(paymentHash.prefix(16)))..., Preimage: \(String(preimage.prefix(16)))...")
            case .inProgress(let send):
                Self.logger.info("LNURL payment in progress, Amount: \(send.amountSats) sats, Fee: \(send.feeSats) sats")
            case .unknown:
                Self.logger.warning("LNURL payment status unknown")
            }

            return status

        } catch let error as Bark.Error {
            Self.logger.error("FFI Error paying LNURL: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to pay LNURL: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error paying LNURL: \(error)")
            throw error
        }
    }

    // MARK: - Payment Status Polling
    
    /// Poll lightning payment status until preimage is available or max attempts reached
    /// - Parameters:
    ///   - paymentHash: The payment hash to check
    ///   - maxAttempts: Maximum number of polling attempts (default: 10)
    ///   - intervalSeconds: Seconds between polling attempts (default: 1)
    private func pollLightningPaymentStatus(paymentHash: String, maxAttempts: Int = 60, intervalSeconds: UInt64 = 1) async {
        Self.logger.debug("Starting Lightning payment status polling, Payment hash: \(String(paymentHash))..., Max attempts: \(maxAttempts)")
        
        for attempt in 1...maxAttempts {
            do {
                let status = try await checkLightningPayment(paymentHash: paymentHash, wait: false)
                
                switch status {
                case .paid(_, let preimage):
                    Self.logger.info("Lightning payment settled on attempt \(attempt)/\(maxAttempts), Preimage: \(String(preimage.prefix(16)))...")
                    return
                case .inProgress:
                    Self.logger.debug("Lightning payment still in progress, Attempt: \(attempt)/\(maxAttempts)")
                case .unknown:
                    Self.logger.warning("Lightning payment not found on attempt \(attempt)/\(maxAttempts)")
                    return
                }
                
                // Wait before next attempt (unless this was the last attempt)
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                }
            } catch {
                Self.logger.warning("Failed to check Lightning payment on attempt \(attempt)/\(maxAttempts): \(error)")
                
                // Wait before retry (unless this was the last attempt)
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                }
            }
        }
        
        Self.logger.warning("Lightning payment polling completed without settlement after \(maxAttempts) attempts")
    }
    
    // MARK: - BOLT12 Offers
    
    func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> LightningSendStatus {
        // Check lightning payment status by payment hash
        
        if isPreview {
            return .unknown
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.checkLightningPayment(paymentHash: paymentHash, wait: wait)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error checking lightning payment: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to check lightning payment: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error checking lightning payment: \(error)")
            throw error
        }
    }
    
    func lightningReceiveState(paymentHash: String) async throws -> LightningReceive {
        // Get lightning receive state by payment hash
        // Throws if the payment hash is unknown (v0.12+ replaces the old optional return)

        if isPreview {
            return LightningReceive(
                paymentHash: paymentHash,
                invoice: "lnbc1preview...",
                amountSats: 0,
                state: "awaiting-payment",
                paymentPreimage: nil,
                settledAt: nil
            )
        }

        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        do {
            return try await wallet.lightningReceiveState(paymentHash: paymentHash)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting lightning receive state: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get lightning receive state: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting lightning receive state: \(error)")
            throw error
        }
    }

    @discardableResult
    func tryClaimLightningReceive(paymentHash: String, wait: Bool) async throws -> LightningReceive {
        // Try to claim a specific lightning receive by payment hash

        if isPreview {
            return LightningReceive(
                paymentHash: paymentHash,
                invoice: "lnbc1preview...",
                amountSats: 0,
                state: "settled",
                paymentPreimage: nil,
                settledAt: Int64(Date().timeIntervalSince1970)
            )
        }

        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }

        Self.logger.debug("Claiming specific Lightning receive via FFI, Payment hash: \(String(paymentHash.prefix(16)))...")

        do {
            let receive = try await wallet.tryClaimLightningReceive(paymentHash: paymentHash, wait: wait)
            Self.logger.info("Lightning receive claimed, state: \(receive.state)")
            return receive
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error claiming lightning receive: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to claim lightning receive: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error claiming lightning receive: \(error)")
            throw error
        }
    }
    
    func claimableLightningReceiveBalanceSats() async throws -> UInt64 {
        // Get claimable lightning receive balance
        
        if isPreview {
            return 0
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.claimableLightningReceiveBalanceSats()
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting claimable lightning receive balance: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get claimable lightning receive balance: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting claimable lightning receive balance: \(error)")
            throw error
        }
    }
    
    func pendingLightningReceives() async throws -> [LightningReceive] {
        // Get all pending lightning receives
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.pendingLightningReceives()
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting pending lightning receives: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get pending lightning receives: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting pending lightning receives: \(error)")
            throw error
        }
    }
    
    func cancelLightningReceive(paymentHash: String) async throws {
        // Cancel a pending lightning receive by payment hash
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Canceling Lightning receive via FFI, Payment hash: \(String(paymentHash.prefix(16)))...")
        
        do {
            try await wallet.cancelLightningReceive(paymentHash: paymentHash)
            Self.logger.info("Lightning receive canceled")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error canceling lightning receive: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to cancel lightning receive: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error canceling lightning receive: \(error)")
            throw error
        }
    }
    
    // MARK: - New Methods (Bark API Update)
    
    func isInvoicePaid(paymentHash: String) async throws -> Bool {
        // Quick boolean check if a payment has settled
        
        if isPreview {
            return false
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.isInvoicePaid(paymentHash: paymentHash)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error checking if invoice paid: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to check if invoice paid: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error checking if invoice paid: \(error)")
            throw error
        }
    }
    
    func lightningSendState(paymentHash: String) async throws -> LightningSendStatus {
        // Non-blocking status check for a specific payment
        
        if isPreview {
            return .unknown
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            return try await wallet.lightningSendState(paymentHash: paymentHash)
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting lightning send state: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get lightning send state: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting lightning send state: \(error)")
            throw error
        }
    }
    
    // MARK: - Stuck Payment Recovery (New in FFI)
    
    func allowLightningSendToExit(paymentHash: String) async throws {
        // Allow a stuck Lightning send (failed payment + failed revocation) to be exited on-chain
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Allowing stuck Lightning send to exit, Payment hash: \(String(paymentHash.prefix(16)))...")
        
        do {
            try await wallet.allowLightningSendToExit(paymentHash: paymentHash)
            Self.logger.info("Stuck Lightning send allowed to exit successfully")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error allowing Lightning send to exit: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to allow Lightning send to exit: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error allowing Lightning send to exit: \(error)")
            throw error
        }
    }
    
    func attemptLightningReceiveExit(paymentHash: String) async throws {
        // Attempt to exit a stuck Lightning receive on-chain
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Attempting Lightning receive exit, Payment hash: \(String(paymentHash.prefix(16)))...")
        
        do {
            try await wallet.attemptLightningReceiveExit(paymentHash: paymentHash)
            Self.logger.info("Lightning receive exit attempted successfully")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error attempting Lightning receive exit: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to attempt Lightning receive exit: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error attempting Lightning receive exit: \(error)")
            throw error
        }
    }
    
    func stuckFailedLightningSends() async throws -> [LightningSend] {
        // Get list of Lightning sends that failed payment AND failed revocation (stuck state)
        
        if isPreview {
            return []
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        do {
            let stuckSends = try await wallet.stuckFailedLightningSends()
            Self.logger.info("Retrieved \(stuckSends.count) stuck failed Lightning sends")
            return stuckSends
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error getting stuck failed Lightning sends: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to get stuck failed Lightning sends: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error getting stuck failed Lightning sends: \(error)")
            throw error
        }
    }
}
