//
//  WalletManager+Lightning.swift
//  Arké
//
//  Lightning Network operations
//  Invoice generation, payment, and status checking via the Ark protocol
//

import Foundation
import Bark

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
    
    /// Pay a Lightning invoice with optional amount (for invoices that may already include an amount)
    func payLightningInvoice(invoice: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        guard let walletOperationsService = walletOperationsService else {
            throw BarkErrorArke.commandFailed("Wallet operations service not initialized")
        }
        return try await walletOperationsService.payLightningInvoice(invoice: invoice, amountSats: amountSats)
    }
    
    /// Pay a Lightning address (user@domain format)
    func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.payLightningAddress(lightningAddress: lightningAddress, amountSats: amountSats, comment: comment, wait: true)
    }

    /// Pay an LNURL-pay endpoint (bech32 `lnurl...` or Lightning address)
    func payLnurl(lnurl: String, amountSats: UInt64, comment: String?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.payLnurl(lnurl: lnurl, amountSats: amountSats, comment: comment, wait: true)
    }
    
    /// Pay a BOLT12 Lightning offer
    func payLightningOffer(offer: String, amountSats: UInt64?) async throws -> LightningSendStatus {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        return try await wallet.payLightningOffer(offer: offer, amountSats: amountSats, wait: true)
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
