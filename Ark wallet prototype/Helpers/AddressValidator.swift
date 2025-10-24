//
//  AddressValidator.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import Foundation

enum AddressType: String, CaseIterable {
    case bitcoin = "Bitcoin"
    case ark = "Ark"
    case lightning = "Lightning"
    case bip353 = "BIP-353"
    case bip21 = "BIP-21"
    
    var displayName: String {
        switch self {
        case .bitcoin:
            return "Bitcoin address"
        case .ark:
            return "Ark address"
        case .lightning:
            return "Lightning address"
        case .bip353:
            return "BIP-353 address"
        case .bip21:
            return "BIP-21 payment URI"
        }
    }
}

struct ParsedAddress {
    let type: AddressType
    let originalString: String
    let address: String
    let amount: Int? // Amount in satoshis if specified
    let label: String?
    let message: String?
}

class AddressValidator {
    
    /// Validates and parses various address formats
    static func parseAddress(_ input: String) -> ParsedAddress? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check BIP-21 URI first (most specific)
        if let bip21 = parseBIP21URI(trimmed) {
            return bip21
        }
        
        // Check Lightning address
        if isLightningAddress(trimmed) {
            return ParsedAddress(
                type: .lightning,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil
            )
        }
        
        // Check BIP-353 address
        if isBIP353Address(trimmed) {
            return ParsedAddress(
                type: .bip353,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil
            )
        }
        
        // Check Bitcoin address
        if isBitcoinAddress(trimmed) {
            return ParsedAddress(
                type: .bitcoin,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil
            )
        }
        
        // Check Ark address
        if isArkAddress(trimmed) {
            return ParsedAddress(
                type: .ark,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil
            )
        }
        
        return nil
    }
    
    /// Determines if the address is a Bitcoin network address (taproot, segwit, etc.)
    static func isBitcoinAddress(_ address: String) -> Bool {
        let bitcoinPatterns = [
            "^bc1[a-z0-9]{39,59}$",  // Bech32 (segwit v0 and v1/taproot mainnet)
            "^tb1[a-z0-9]{39,59}$",  // Bech32 (segwit testnet)
            "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$", // Legacy P2PKH and P2SH mainnet
            "^[2mn][a-km-zA-HJ-NP-Z1-9]{25,34}$" // Legacy testnet
        ]
        
        return bitcoinPatterns.contains { pattern in
            address.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    /// Determines if the address is an Ark address
    static func isArkAddress(_ address: String) -> Bool {
        let arkPattern = "^ark1[a-z0-9]+$"
        return address.range(of: arkPattern, options: .regularExpression) != nil
    }
    
    /// Determines if the address is a Lightning address (user@domain.com format)
    static func isLightningAddress(_ address: String) -> Bool {
        // Lightning address format: username@domain.tld
        let lightningPattern = "^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        return address.range(of: lightningPattern, options: .regularExpression) != nil
    }
    
    /// Determines if the address is a BIP-353 address (₿username.domain.tld format)
    static func isBIP353Address(_ address: String) -> Bool {
        // BIP-353 format: ₿username.domain.tld
        let bip353Pattern = "^₿[a-zA-Z0-9._-]+\\.[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        return address.range(of: bip353Pattern, options: .regularExpression) != nil
    }
    
    /// Parses a BIP-21 Bitcoin URI
    static func parseBIP21URI(_ uri: String) -> ParsedAddress? {
        // BIP-21 format: bitcoin:address?param1=value1&param2=value2
        guard uri.lowercased().starts(with: "bitcoin:") else { return nil }
        
        let withoutScheme = String(uri.dropFirst(8)) // Remove "bitcoin:"
        
        // Split address and parameters
        let components = withoutScheme.components(separatedBy: "?")
        let address = components.first ?? ""
        
        // Validate the address part
        guard isBitcoinAddress(address) else { return nil }
        
        var amount: Int?
        var label: String?
        var message: String?
        
        // Parse query parameters if they exist
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
        }
        
        return ParsedAddress(
            type: .bip21,
            originalString: uri,
            address: address,
            amount: amount,
            label: label,
            message: message
        )
    }
    
    /// Parses URL query parameters
    private static func parseQueryParameters(_ queryString: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        let pairs = queryString.components(separatedBy: "&")
        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            if keyValue.count == 2 {
                let key = keyValue[0]
                let value = keyValue[1]
                parameters[key] = value
            }
        }
        
        return parameters
    }
    
    /// Checks if the input is any valid address format
    static func isValidAddress(_ input: String) -> Bool {
        return parseAddress(input) != nil
    }
}