//
//  WalletManager+Lightning.swift
//  Arké
//
//  Lightning Network operations
//  Invoice generation, payment, and status checking via the Ark protocol
//

import Foundation
import Bark
import OSLog

extension WalletManager {
    
    // MARK: - Lightning Invoice Operations
    
    /// Generate a Lightning invoice for receiving payment
    func getLightningInvoice(amountSats: UInt64, description: String?) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getLightningInvoice(amountSats: amountSats, description: description)
    }
    
    // MARK: - Lightning Payment Operations
    
    // Every pay call starts the payment with `wait: false` and then waits
    // until bark has the preimage (`LightningSettlement`), so the returned
    // status is `.paid` and the send screen never says "Sent" at handoff.

    /// Pay a Lightning invoice with optional amount (for invoices that may already include an amount)
    func payLightningInvoice(invoice: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        guard let walletOperationsService = walletOperationsService, let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        let paymentHash = LightningInvoiceParser.extractPaymentHash(fromInvoice: invoice)
        let settled = try await payLightning(wallet: wallet, paymentHash: paymentHash) {
            try await walletOperationsService.payLightningInvoice(invoice: invoice, amountSats: amountSats)
        }
        // Refresh after "Sent" instead of holding the send screen for it
        if let onTransactionCompleted = walletOperationsService.onTransactionCompleted {
            Task { await onTransactionCompleted() }
        }
        return settled
    }
    
    /// Pay a Lightning address (user@domain format)
    func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await payLightning(wallet: wallet) {
            try await wallet.payLightningAddress(lightningAddress: lightningAddress, amountSats: amountSats, comment: comment, wait: false)
        }
    }

    /// Pay an LNURL-pay endpoint (bech32 `lnurl...` or Lightning address)
    func payLnurl(lnurl: String, amountSats: UInt64, comment: String?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await payLightning(wallet: wallet) {
            try await wallet.payLnurl(lnurl: lnurl, amountSats: amountSats, comment: comment, wait: false)
        }
    }
    
    /// Pay a BOLT12 Lightning offer
    func payLightningOffer(offer: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await payLightning(wallet: wallet) {
            try await wallet.payLightningOffer(offer: offer, amountSats: amountSats, wait: false)
        }
    }
    
    /// Start a payment with `pay` (a `wait: false` call) and wait until bark
    /// has its preimage
    /// - Parameter paymentHash: the hash when known before paying (BOLT11)
    private func payLightning(
        wallet: BarkWalletProtocol,
        paymentHash: String? = nil,
        pay: () async throws -> LightningSendStatus
    ) async throws -> LightningSendStatus {
        // Without a hash, the only way to find this call's send after an error
        var pendingBefore: Set<String>?
        if paymentHash == nil {
            pendingBefore = try? await Set(wallet.pendingLightningSends().map(\.paymentHash))
        }
        
        let started: LightningSendStatus
        do {
            started = try await pay()
        } catch {
            // With `wait: false` bark returns a transient error of the HTLC or
            // payment step instead of retrying it in the call, and keeps the
            // send for its daemon to finish (`run_action_loop`, bark-0.8.1).
            // Reporting that as a failure invites paying twice, so wait for
            // this call's send if one appeared.
            let appeared = (try? await wallet.pendingLightningSends().filter { send in
                if let paymentHash { return send.paymentHash == paymentHash }
                guard let pendingBefore else { return false }
                return !pendingBefore.contains(send.paymentHash)
            }) ?? []
            guard appeared.count == 1, let send = appeared.first else {
                throw error
            }
            Self.logger.warning("⚠️ Lightning pay call failed but its send is pending, waiting for it, Payment hash: \(String(send.paymentHash.prefix(16)), privacy: .public)..., Error: \(error.localizedDescription, privacy: .public)")
            started = .inProgress(send: send)
        }
        
        // In its own task so closing the send screen does not end the wait:
        // the caller still records the payment hash and the refresh still runs
        let settlement = Task {
            try await LightningSettlement.wait(for: started, paymentHash: paymentHash) { paymentHash in
                try await wallet.lightningSendState(paymentHash: paymentHash)
            }
        }
        do {
            let settled = try await settlement.value
            if case .paid(let paidHash, _) = settled {
                Self.logger.info("⚡ Lightning payment settled, Payment hash: \(String(paidHash.prefix(16)), privacy: .public)...")
            }
            return settled
        } catch {
            Self.logger.error("❌ Lightning payment failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
    
    // MARK: - Lightning Status & Management
    
    /// Get the current status of a Lightning invoice
    func getLightningInvoiceStatus(invoice: String) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.getLightningInvoiceStatus(invoice: invoice)
    }
    
    /// List all Lightning invoices
    func listLightningInvoices() async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.listLightningInvoices()
    }
    
    
    /// Claim a Lightning invoice
    func claimLightningInvoice(invoice: String) async throws -> String {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.claimLightningInvoice(invoice: invoice)
    }
}
