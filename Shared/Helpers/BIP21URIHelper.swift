//
//  BIP21URIHelper.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import Foundation
import ArkeUI

struct BIP21URIHelper {
    /// Converts satoshis to the BTC decimal string BIP-21 expects
    /// - Parameter sats: Amount in satoshis
    /// - Returns: Amount in BTC with 8 decimal places, or nil when not positive
    private static func satoshisToBTC(_ sats: Int) -> String? {
        guard sats > 0 else { return nil }
        let btc = Double(sats) / 100_000_000
        return String(format: "%.8f", btc)
    }
    
    /// Create BIP 21 URI with optional alternative payment destinations.
    /// `amountSats` is whole sats — callers must parse user input first
    /// (a unit-format string like "0.001" used to be passed here and was
    /// silently dropped; Fiat_Rates.md Phase 4 groundwork).
    static func createBIP21URI(
        arkAddress: String? = nil,
        onchainAddress: String? = nil,
        lightningInvoice: String? = nil,
        silentPaymentsAddress: String? = nil,
        amountSats: Int? = nil,
        label: String? = nil,
        message: String? = nil
    ) -> String {
        var components = URLComponents()
        components.scheme = "bitcoin"
        components.path = onchainAddress ?? ""
        
        var queryItems: [URLQueryItem] = []
        
        // Add ark address as alternative payment option
        if let arkAddress = arkAddress {
            queryItems.append(URLQueryItem(name: "ark", value: arkAddress))
        }
        
        // Add lightning invoice as alternative payment option
        if let lightningInvoice = lightningInvoice {
            queryItems.append(URLQueryItem(name: "lightning", value: lightningInvoice))
        }
        
        // Add silent payments address as alternative payment option
        if let silentPaymentsAddress = silentPaymentsAddress {
            queryItems.append(URLQueryItem(name: "sp", value: silentPaymentsAddress))
        }
        
        // Add amount (convert from satoshis to BTC for BIP-21 compliance)
        if let amountSats = amountSats, let btcAmount = satoshisToBTC(amountSats) {
            queryItems.append(URLQueryItem(name: "amount", value: btcAmount))
        }
        
        // Add label
        if let label = label {
            queryItems.append(URLQueryItem(name: "label", value: label))
        }
        
        // Add message
        if let message = message {
            queryItems.append(URLQueryItem(name: "message", value: message))
        }
        
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        return components.url?.absoluteString ?? "bitcoin:\(onchainAddress ?? "")"
    }
    
    /// Create a unified BIP-21 URI from a PaymentRequest with multiple destinations
    static func createBIP21URI(from paymentRequest: PaymentRequest) -> String {
        guard let primaryDestination = paymentRequest.primaryDestination else {
            return ""
        }
        
        // Extract alternative destinations by format
        let arkAddress = paymentRequest.firstDestination(for: .ark)?.address
        let lightningInvoice = paymentRequest.firstDestination(for: .lightningInvoice)?.address
        let silentPaymentsAddress = paymentRequest.firstDestination(for: .silentPayments)?.address
        
        return createBIP21URI(
            arkAddress: arkAddress,
            onchainAddress: primaryDestination.address,
            lightningInvoice: lightningInvoice,
            silentPaymentsAddress: silentPaymentsAddress,
            amountSats: paymentRequest.amount,
            label: paymentRequest.label,
            message: paymentRequest.message
        )
    }
}
