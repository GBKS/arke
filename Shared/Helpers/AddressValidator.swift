//
//  AddressValidator.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import Foundation
import ArkeUI

class AddressValidator {
    
    /// Validates and parses various address formats into a payment request
    static func parsePaymentRequest(_ input: String) -> PaymentRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check BIP-21 URI first (can contain multiple destinations)
        if let bip21 = parseBIP21URI(trimmed) {
            return bip21
        }
        
        // Check Lightning URI (lightning:invoice format)
        if let lightningURI = parseLightningURI(trimmed) {
            return lightningURI
        }
        
        // For all other formats, parse as a payment request
        return parseSingleFormatRequest(trimmed)
    }
    
    /// Parses a single-format payment request (non-URI formats)
    /// Returns a PaymentRequest with embedded metadata (amount, label, etc.) if available
    private static func parseSingleFormatRequest(_ input: String) -> PaymentRequest? {
        // Check LNURL format (more specific than Lightning Address, check first)
        if LNURLResolver.isLNURL(input) {
            let destination = PaymentDestination(
                format: .lnurl,
                network: nil,  // Network-agnostic
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check Lightning address
        if isLightningAddress(input) {
            let destination = PaymentDestination(
                format: .lightning,
                network: nil,
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check Lightning invoice using dedicated parser (extracts amount and description)
        if isLightningInvoice(input) {
            return parseLightningInvoiceRequest(input)
        }
        
        // Check Lightning Offer (BOLT12)
        if isLightningOffer(input) {
            let destination = PaymentDestination(
                format: .bolt12,
                network: nil, // BOLT12 offers are network-agnostic
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check BIP-353 address
        if isBIP353Address(input) {
            let destination = PaymentDestination(
                format: .bip353,
                network: nil,
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check Bitcoin address with network detection
        if let network = detectBitcoinNetwork(input) {
            let destination = PaymentDestination(
                format: .bitcoin,
                network: network,
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check Silent Payments address with network detection
        if let network = detectSilentPaymentsNetwork(input) {
            let keys = extractSilentPaymentsKeys(input)
            let destination = PaymentDestination(
                format: .silentPayments,
                network: network,
                address: input,
                scanPublicKey: keys?.scanKey,
                spendPublicKey: keys?.spendKey
            )
            return PaymentRequest(destination: destination)
        }
        
        // Check Ark address with network detection
        if let network = detectArkNetwork(input) {
            let destination = PaymentDestination(
                format: .ark,
                network: network,
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        return nil
    }
    
    /// Parses a single payment destination (helper for BIP-21 parsing)
    /// Returns just the destination without metadata (for use in multi-destination contexts)
    private static func parseSingleDestination(_ input: String) -> PaymentDestination? {
        // Check Ark address with network detection
        if let network = detectArkNetwork(input) {
            return PaymentDestination(
                format: .ark,
                network: network,
                address: input
            )
        }
        
        // Check Lightning address
        if isLightningAddress(input) {
            return PaymentDestination(
                format: .lightning,
                network: nil,
                address: input
            )
        }
        
        // Check Lightning invoice
        if isLightningInvoice(input),
           let paymentRequest = parseLightningInvoiceRequest(input),
           let destination = paymentRequest.primaryDestination {
            return destination
        }
        
        // Check Lightning Offer (BOLT12)
        if isLightningOffer(input) {
            return PaymentDestination(
                format: .bolt12,
                network: nil, // BOLT12 offers are network-agnostic
                address: input
            )
        }
        
        // Check Bitcoin address with network detection
        if let network = detectBitcoinNetwork(input) {
            return PaymentDestination(
                format: .bitcoin,
                network: network,
                address: input
            )
        }
        
        // Check Silent Payments address with network detection
        if let network = detectSilentPaymentsNetwork(input) {
            let keys = extractSilentPaymentsKeys(input)
            return PaymentDestination(
                format: .silentPayments,
                network: network,
                address: input,
                scanPublicKey: keys?.scanKey,
                spendPublicKey: keys?.spendKey
            )
        }
        
        return nil
    }
    
    /// Determines the Bitcoin network for an address
    static func detectBitcoinNetwork(_ address: String) -> BitcoinNetwork? {
        // Normalize to lowercase for case-insensitive comparison (bech32/bech32m are case-insensitive)
        let normalized = address.lowercased()
        
        // Mainnet patterns
        // - bc1 (bech32/bech32m): SegWit v0 (39-59 chars) and Taproot (up to 90 chars total, so up to 87 after bc1)
        // - Legacy: 1... (P2PKH) and 3... (P2SH)
        if normalized.range(of: "^bc1[a-z0-9]{39,87}$", options: .regularExpression) != nil ||
           address.range(of: "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$", options: .regularExpression) != nil {
            return .mainnet
        }
        
        // Testnet patterns
        // - tb1 (bech32/bech32m): Same length constraints as mainnet
        // - Legacy: 2..., m..., n... (P2PKH and P2SH)
        if normalized.range(of: "^tb1[a-z0-9]{39,87}$", options: .regularExpression) != nil ||
           address.range(of: "^[2mn][a-km-zA-HJ-NP-Z1-9]{25,34}$", options: .regularExpression) != nil {
            return .testnet
        }
        
        // Signet patterns (uses same prefixes as testnet but different magic bytes)
        // Note: At the string level, signet addresses look identical to testnet
        // You might need additional context or user selection to differentiate
        
        // Regtest patterns (same as testnet for most address types)
        // Note: Regtest typically uses same address formats as testnet
        
        return nil
    }
    
    /// Determines the Bitcoin network for a silent payments address
    static func detectSilentPaymentsNetwork(_ address: String) -> BitcoinNetwork? {
        // Mainnet silent payments: sp1...
        if address.hasPrefix("sp1") && isValidSilentPaymentsAddress(address) {
            return .mainnet
        }
        
        // Testnet silent payments: tsp1...
        if address.hasPrefix("tsp1") && isValidSilentPaymentsAddress(address) {
            return .testnet
        }
        
        // Signet silent payments: ssp1...
        if address.hasPrefix("ssp1") && isValidSilentPaymentsAddress(address) {
            return .signet
        }
        
        // Regtest silent payments: rsp1...
        if address.hasPrefix("rsp1") && isValidSilentPaymentsAddress(address) {
            return .regtest
        }
        
        return nil
    }
    
    /// Validates a silent payments address according to BIP-352
    static func isValidSilentPaymentsAddress(_ address: String) -> Bool {
        // Check if it has a valid silent payments prefix
        let validPrefixes = ["sp1", "tsp1", "ssp1", "rsp1"]
        guard validPrefixes.contains(where: { address.hasPrefix($0) }) else {
            return false
        }
        
        // Decode using bech32m
        guard let decoded = decodeBech32m(address) else {
            return false
        }
        
        // Silent payments addresses should have exactly 66 bytes of data
        // (33 bytes for scan public key + 33 bytes for spend public key)
        return decoded.data.count == 66
    }
    
    /// Extracts the scan and spend public keys from a silent payments address
    static func extractSilentPaymentsKeys(_ address: String) -> (scanKey: Data, spendKey: Data)? {
        guard let decoded = decodeBech32m(address),
              decoded.data.count == 66 else {
            return nil
        }
        
        let scanKey = decoded.data.prefix(33)
        let spendKey = decoded.data.suffix(33)
        
        return (scanKey: Data(scanKey), spendKey: Data(spendKey))
    }
    
    /// Basic bech32m decoder for silent payments validation
    private static func decodeBech32m(_ address: String) -> (hrp: String, data: Data)? {
        // This is a simplified bech32m decoder for validation purposes
        // In production, you'd want a full implementation that handles all edge cases
        
        guard let separatorIndex = address.lastIndex(of: "1") else { return nil }
        
        let hrp = String(address[..<separatorIndex])
        let data = String(address[address.index(after: separatorIndex)...])
        
        // Basic character set validation for bech32m
        let validChars = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        guard data.allSatisfy({ validChars.contains($0) }) else { return nil }
        
        // Convert bech32 string to 5-bit groups then to bytes
        // This is a simplified version - full implementation would include checksum verification
        let fiveBitGroups = data.dropLast(6).compactMap { validChars.firstIndex(of: $0)?.utf16Offset(in: validChars) }
        
        // Convert from 5-bit groups to 8-bit bytes
        var bytes: [UInt8] = []
        var accumulator = 0
        var bitsCount = 0
        
        for value in fiveBitGroups {
            accumulator = (accumulator << 5) | value
            bitsCount += 5
            
            if bitsCount >= 8 {
                bytes.append(UInt8((accumulator >> (bitsCount - 8)) & 0xFF))
                bitsCount -= 8
            }
        }
        
        return (hrp: hrp, data: Data(bytes))
    }
    
    /// Method for checking if an address is a valid Bitcoin address
    static func isBitcoinAddress(_ address: String) -> Bool {
        return detectBitcoinNetwork(address) != nil
    }
    
    /// Determines the Ark network for an address
    static func detectArkNetwork(_ address: String) -> BitcoinNetwork? {
        // Mainnet Ark addresses start with "ark1"
        if address.range(of: "^ark1[a-z0-9]+$", options: .regularExpression) != nil {
            return .mainnet
        }
        
        // Signet Ark addresses start with "tark1"
        // Based on actual Signet Ark address format: tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4gm679lqwudrzghz7a2rx7wuup9cpqq6ssw20
        if address.range(of: "^tark1[a-z0-9]+$", options: .regularExpression) != nil {
            return .signet
        }
        
        // Testnet Ark addresses - pattern to be confirmed
        // TODO: Update this when testnet pattern is confirmed
        // Possibly uses a different prefix like "tpub1" or similar
        
        // Regtest Ark addresses - typically same as testnet
        // TODO: Update this when regtest pattern is confirmed
        
        return nil
    }
    
    /// Determines if the address is an Ark address
    static func isArkAddress(_ address: String) -> Bool {
        return detectArkNetwork(address) != nil
    }
    
    /// Determines if the address is a silent payments address
    static func isSilentPaymentsAddress(_ address: String) -> Bool {
        return detectSilentPaymentsNetwork(address) != nil
    }
    
    /// Determines if the address is a Lightning address (user@domain.com format)
    static func isLightningAddress(_ address: String) -> Bool {
        // Lightning address format: username@domain.tld
        let lightningPattern = "^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        return address.range(of: lightningPattern, options: .regularExpression) != nil
    }
    
    /// Parses a Lightning invoice using the dedicated LightningInvoiceParser
    /// Returns a PaymentRequest with amount and description if present in the invoice
    private static func parseLightningInvoiceRequest(_ input: String) -> PaymentRequest? {
        // Try detailed parsing first
        if let lightningInvoice = try? LightningInvoiceParser.parse(input) {
            // Convert Lightning network to BitcoinNetwork
            let bitcoinNetwork: BitcoinNetwork? = {
                switch lightningInvoice.network {
                case .mainnet:
                    return .mainnet
                case .testnet:
                    return .testnet
                case .regtest:
                    return .regtest
                case .simnet:
                    return .signet  // Map simnet to signet
                }
            }()
            
            let destination = PaymentDestination(
                format: .lightningInvoice,
                network: bitcoinNetwork,
                address: input
            )
            
            // Convert amount from UInt64? to Int?
            let amountSats: Int? = lightningInvoice.amountSatoshis.map { Int($0) }
            
            // Create PaymentRequest with embedded amount and description
            return PaymentRequest(
                destination: destination,
                amount: amountSats,
                label: lightningInvoice.description,
                message: nil
            )
        }
        
        // If detailed parsing fails, fall back to basic validation
        if isLightningInvoice(input) {
            let destination = PaymentDestination(
                format: .lightningInvoice,
                network: nil,
                address: input
            )
            return PaymentRequest(destination: destination)
        }
        
        return nil
    }
    
    /// Helper to get Lightning invoice amount (for payment request metadata)
    private static func extractLightningInvoiceInfo(_ input: String) -> (amount: Int?, description: String?) {
        if let lightningInvoice = try? LightningInvoiceParser.parse(input) {
            let amountInt: Int? = {
                if let amount = lightningInvoice.amountSatoshis {
                    return Int(amount)
                }
                return nil
            }()
            return (amount: amountInt, description: lightningInvoice.description)
        }
        return (amount: nil, description: nil)
    }

    /// Determines if the address is a Lightning invoice (BOLT11 format)
    static func isLightningInvoice(_ invoice: String) -> Bool {
        let trimmed = invoice.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // BOLT11 Lightning invoices start with network-specific prefixes
        let lightningInvoicePrefixes = ["lnbc", "lntb", "lnbcrt", "lnsb"]
        
        return lightningInvoicePrefixes.contains { prefix in
            trimmed.hasPrefix(prefix)
        }
    }
    
    /// Determines if the address is a Lightning Offer (BOLT12 format)
    static func isLightningOffer(_ offer: String) -> Bool {
        let trimmed = offer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // BOLT12 Lightning offers start with "lno1"
        return trimmed.hasPrefix("lno1")
    }
    

    
    /// Determines if the address is a BIP-353 address (₿username@domain.tld format)
    static func isBIP353Address(_ address: String) -> Bool {
        // BIP-353 format: ₿username@domain.tld
        let bip353Pattern = "^₿[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        return address.range(of: bip353Pattern, options: .regularExpression) != nil
    }
    
    /// Parses a BIP-21 Bitcoin URI with all payment destinations
    static func parseBIP21URI(_ uri: String) -> PaymentRequest? {
        guard uri.lowercased().starts(with: "bitcoin:") else { return nil }
        
        let withoutScheme = String(uri.dropFirst(8)) // Remove "bitcoin:"
        
        // Split address and parameters
        let components = withoutScheme.components(separatedBy: "?")
        let primaryAddress = components.first ?? ""
        
        var destinations: [PaymentDestination] = []
        var amount: Int?
        var label: String?
        var message: String?
        
        // Parse primary address as first destination (if present)
        // BIP-21 allows empty address when alternative payment methods are provided
        if !primaryAddress.isEmpty {
            if let destination = parseSingleDestination(primaryAddress) {
                destinations.append(destination)
            } else {
                return nil // Invalid primary address format
            }
        }
        
        // Parse query parameters for amount, metadata, and alternative destinations
        if components.count > 1 {
            let queryString = components[1]
            let parameters = parseQueryParameters(queryString)
            
            // Parse amount (BTC to satoshis conversion)
            if let amountString = parameters["amount"],
               let amountDouble = Double(amountString) {
                amount = Int(amountDouble * 100_000_000) // Convert BTC to satoshis
            }
            
            label = parameters["label"]?.removingPercentEncoding
            message = parameters["message"]?.removingPercentEncoding
            
            // Parse alternative payment destinations
            
            // Ark address alternative
            if let arkAddress = parameters["ark"],
               let arkDestination = parseSingleDestination(arkAddress) {
                destinations.append(arkDestination)
            }
            
            // Lightning invoice alternative (both "lightning" and "ln" are common)
            if let lightningParam = parameters["lightning"] ?? parameters["ln"] {
                if let lightningDestination = parseSingleDestination(lightningParam) {
                    destinations.append(lightningDestination)
                    
                    // If amount wasn't specified in BIP-21 but is in Lightning invoice, use that
                    if amount == nil {
                        let invoiceInfo = extractLightningInvoiceInfo(lightningParam)
                        amount = invoiceInfo.amount
                        // Also use invoice description as label if not set
                        if label == nil {
                            label = invoiceInfo.description
                        }
                    }
                }
            }
            
            // Lightning Offer alternative (BOLT12)
            if let lightningOfferParam = parameters["lno"] {
                if isLightningOffer(lightningOfferParam) {
                    let destination = PaymentDestination(
                        format: .bolt12,
                        network: nil, // BOLT12 offers are network-agnostic
                        address: lightningOfferParam
                    )
                    destinations.append(destination)
                }
            }
            
            // Silent Payments alternative
            if let spAddress = parameters["sp"],
               let spDestination = parseSingleDestination(spAddress) {
                destinations.append(spDestination)
            }
            
            // Support for additional Bitcoin addresses (for unified QR codes)
            if let altAddress = parameters["address"],
               let altDestination = parseSingleDestination(altAddress) {
                destinations.append(altDestination)
            }
        }
        
        // Ensure at least one valid destination was found
        guard !destinations.isEmpty else {
            return nil
        }
        
        return PaymentRequest(
            destinations: destinations,
            amount: amount,
            label: label,
            message: message,
            originalString: uri
        )
    }
    
    /// Parses a Lightning URI (lightning:invoice or lightning:lnurl format)
    static func parseLightningURI(_ uri: String) -> PaymentRequest? {
        guard uri.lowercased().starts(with: "lightning:") else { return nil }
        
        let withoutScheme = String(uri.dropFirst(10)) // Remove "lightning:"
        
        // Check if it's an LNURL first (lightning:LNURL1...)
        if LNURLResolver.isLNURL(withoutScheme) {
            let destination = PaymentDestination(
                format: .lnurl,
                network: nil,
                address: withoutScheme
            )
            return PaymentRequest(destination: destination)
        }
        
        // Otherwise, parse as a Lightning invoice
        return parseLightningInvoiceRequest(withoutScheme)
    }
    
    /// Parses URL query parameters
    /// Note: Parameter keys are normalized to lowercase for case-insensitive matching
    private static func parseQueryParameters(_ queryString: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        let pairs = queryString.components(separatedBy: "&")
        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            if keyValue.count == 2 {
                let key = keyValue[0].lowercased()  // Normalize to lowercase for case-insensitive matching
                let value = keyValue[1]
                parameters[key] = value
            }
        }
        
        return parameters
    }
    
    /// Checks if the input is any valid address format
    static func isValidPaymentRequest(_ input: String) -> Bool {
        return parsePaymentRequest(input) != nil
    }
    
    // MARK: - NetworkConfig Integration
    
    /// Parse a payment request with network validation against a specific NetworkConfig
    static func parsePaymentRequest(_ input: String, expectedNetwork networkConfig: NetworkConfig) -> PaymentRequest? {
        guard let paymentRequest = parsePaymentRequest(input) else { return nil }
        
        // Filter to only destinations compatible with the network
        return paymentRequest.filtered(for: networkConfig)
    }
    
    /// Check if a payment request is valid for a specific network configuration
    static func isValidPaymentRequest(_ input: String, for networkConfig: NetworkConfig) -> Bool {
        return parsePaymentRequest(input, expectedNetwork: networkConfig) != nil
    }
    
    /// Get all payment requests from a list that match a specific network configuration
    static func filterPaymentRequests(_ requests: [PaymentRequest], for networkConfig: NetworkConfig) -> [PaymentRequest] {
        return requests.compactMap { $0.filtered(for: networkConfig) }
    }
}
