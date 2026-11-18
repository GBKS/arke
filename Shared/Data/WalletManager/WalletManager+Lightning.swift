//
//  WalletManager+Lightning.swift
//  Arké
//
//  Lightning Network operations
//  Invoice generation, payment, and status checking via the Ark protocol
//

import Foundation
import Bark
import os

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
    // until bark has the preimage (`LightningSettlement`), so a returned
    // status is always `.paid`; anything else throws `LightningSendFailure`.
    // The refresh runs after settlement, not before the send screen shows
    // "Sent" (`Features/Lightning_Send_Settlement.md`).

    /// Pay a Lightning invoice with optional amount (for invoices that may already include an amount)
    func payLightningInvoice(invoice: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        guard let walletOperationsService = walletOperationsService, let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        let knownHash = LightningInvoiceParser.extractPaymentHash(fromInvoice: invoice)
        return try await payLightning(wallet: wallet, knownHash: knownHash) {
            try await walletOperationsService.payLightningInvoice(invoice: invoice, amountSats: amountSats)
        }
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

    /// Start a payment with `pay` (a `wait: false` call), wait until bark has
    /// its preimage, then run the post-transaction refresh.
    /// - Parameter knownHash: the payment hash when known before paying (BOLT11)
    private func payLightning(
        wallet: BarkWalletProtocol,
        knownHash: String? = nil,
        pay: () async throws -> LightningSendStatus
    ) async throws -> LightningSendStatus {
        let started: LightningSendStatus
        do {
            started = try await LightningSettlement.start(
                knownHash: knownHash,
                pendingSends: { try await wallet.pendingLightningSends() },
                pay: pay
            )
        } catch {
            Self.logger.error("❌ Lightning pay call failed with no pending send: \(String(describing: error), privacy: .public)")
            throw error
        }
        if case .inProgress(let send) = started {
            Self.logger.info("⚡ Lightning payment started, waiting for settlement, Payment hash: \(String(send.paymentHash.prefix(16)), privacy: .public)...")
        }

        // In its own task so a dismissed send sheet does not end the wait: the
        // caller still records the payment hash and the refresh still runs
        let waitStarted = ContinuousClock.now
        let settlement = Task {
            try await LightningSettlement.wait(for: started, knownHash: knownHash) { paymentHash in
                try await wallet.lightningSendState(paymentHash: paymentHash)
            }
        }
        let settled: LightningSendStatus
        do {
            settled = try await settlement.value
        } catch {
            let waited = waitStarted.duration(to: .now)
            Self.logger.error("❌ Lightning payment did not settle after \(waited.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
        if case .paid(let paidHash, _) = settled {
            // Device checks read this against the pay call's return; the
            // exported log has no sub-second timestamps of its own
            let waited = waitStarted.duration(to: .now)
            Self.logger.info("⚡ Lightning payment settled after \(waited.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)), privacy: .public) of waiting, Payment hash: \(String(paidHash.prefix(16)), privacy: .public)...")
        }

        // Refresh after "Sent" instead of holding the send screen for it
        if let onTransactionCompleted = walletOperationsService?.onTransactionCompleted {
            Task { await onTransactionCompleted() }
        }
        return settled
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
