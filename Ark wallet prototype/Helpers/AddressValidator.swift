//
//  AddressValidator.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import Foundation

enum AddressFormat: String, CaseIterable {
    case bitcoin = "Bitcoin"
    case silentPayments = "Silent Payments"
    case ark = "Ark"
    case lightning = "Lightning"
    case bip353 = "BIP-353"
    case bip21 = "BIP-21"
    
    var displayName: String {
        switch self {
        case .bitcoin:
            return "Bitcoin address"
        case .silentPayments:
            return "Silent payments address"
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
    
    var supportsBitcoinNetworks: Bool {
        switch self {
        case .bitcoin, .silentPayments, .bip21, .ark:
            return true
        case .lightning, .bip353:
            return false
        }
    }
}

struct ParsedAddress {
    let format: AddressFormat
    let network: BitcoinNetwork?
    let originalString: String
    let address: String
    let amount: Int? // Amount in satoshis if specified
    let label: String?
    let message: String?
    
    // Silent payments specific data
    let scanPublicKey: Data? // For silent payments only
    let spendPublicKey: Data? // For silent payments only
    
    /// Convenience computed property for display
    var displayName: String {
        if let network = network {
            return "\(format.displayName) (\(network.displayName))"
        } else {
            return format.displayName
        }
    }
    
    /// Check if this is a Bitcoin-based address format
    var isBitcoin: Bool {
        return format.supportsBitcoinNetworks
    }
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
                format: .lightning,
                network: nil,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil,
                scanPublicKey: nil,
                spendPublicKey: nil
            )
        }
        
        // Check BIP-353 address
        if isBIP353Address(trimmed) {
            return ParsedAddress(
                format: .bip353,
                network: nil,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil,
                scanPublicKey: nil,
                spendPublicKey: nil
            )
        }
        
        // Check Bitcoin address with network detection
        if let network = detectBitcoinNetwork(trimmed) {
            return ParsedAddress(
                format: .bitcoin,
                network: network,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil,
                scanPublicKey: nil,
                spendPublicKey: nil
            )
        }
        
        // Check Silent Payments address with network detection
        if let network = detectSilentPaymentsNetwork(trimmed) {
            let keys = extractSilentPaymentsKeys(trimmed)
            return ParsedAddress(
                format: .silentPayments,
                network: network,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil,
                scanPublicKey: keys?.scanKey,
                spendPublicKey: keys?.spendKey
            )
        }
        
        // Check Ark address with network detection
        if let network = detectArkNetwork(trimmed) {
            return ParsedAddress(
                format: .ark,
                network: network,
                originalString: trimmed,
                address: trimmed,
                amount: nil,
                label: nil,
                message: nil,
                scanPublicKey: nil,
                spendPublicKey: nil
            )
        }
        
        return nil
    }
    
    /// Determines the Bitcoin network for an address
    static func detectBitcoinNetwork(_ address: String) -> BitcoinNetwork? {
        // Mainnet patterns
        if address.range(of: "^bc1[a-z0-9]{39,59}$", options: .regularExpression) != nil ||
           address.range(of: "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$", options: .regularExpression) != nil {
            return .mainnet
        }
        
        // Testnet patterns
        if address.range(of: "^tb1[a-z0-9]{39,59}$", options: .regularExpression) != nil ||
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
        
        // Signet Ark addresses start with "t" (as you mentioned)
        if address.range(of: "^t[a-z0-9]+$", options: .regularExpression) != nil {
            return .signet
        }
        
        // Testnet Ark addresses - need to confirm the pattern
        // TODO: Update this when testnet pattern is confirmed
        if address.range(of: "^tark1[a-z0-9]+$", options: .regularExpression) != nil {
            return .testnet
        }
        
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
    
    /// Determines if the address is a BIP-353 address (₿username.domain.tld format)
    static func isBIP353Address(_ address: String) -> Bool {
        // BIP-353 format: ₿username.domain.tld
        let bip353Pattern = "^₿[a-zA-Z0-9._-]+\\.[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        return address.range(of: bip353Pattern, options: .regularExpression) != nil
    }
    
    /// Parses a BIP-21 Bitcoin URI with network detection
    static func parseBIP21URI(_ uri: String) -> ParsedAddress? {
        // BIP-21 format: bitcoin:address?param1=value1&param2=value2
        guard uri.lowercased().starts(with: "bitcoin:") else { return nil }
        
        let withoutScheme = String(uri.dropFirst(8)) // Remove "bitcoin:"
        
        // Split address and parameters
        let components = withoutScheme.components(separatedBy: "?")
        let address = components.first ?? ""
        
        // Try to detect as Bitcoin address first
        var network: BitcoinNetwork?
        var format: AddressFormat = .bitcoin
        var scanKey: Data?
        var spendKey: Data?
        
        if let bitcoinNetwork = detectBitcoinNetwork(address) {
            network = bitcoinNetwork
            format = .bitcoin
        } else if let silentNetwork = detectSilentPaymentsNetwork(address) {
            network = silentNetwork
            format = .silentPayments
            let keys = extractSilentPaymentsKeys(address)
            scanKey = keys?.scanKey
            spendKey = keys?.spendKey
        } else {
            return nil
        }
        
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
            format: format,
            network: network,
            originalString: uri,
            address: address,
            amount: amount,
            label: label,
            message: message,
            scanPublicKey: scanKey,
            spendPublicKey: spendKey
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
    
    // MARK: - NetworkConfig Integration
    
    /// Parse an address with network validation against a specific NetworkConfig
    static func parseAddress(_ input: String, expectedNetwork networkConfig: NetworkConfig) -> ParsedAddress? {
        guard let parsedAddress = parseAddress(input) else { return nil }
        
        // For non-Bitcoin addresses, just return the parsed result
        guard let addressNetwork = parsedAddress.network else { return parsedAddress }
        
        // Check if the address network matches the expected network
        guard addressNetwork.matches(networkConfig) else { return nil }
        
        return parsedAddress
    }
    
    /// Check if an address is valid for a specific network configuration
    static func isValidAddress(_ input: String, for networkConfig: NetworkConfig) -> Bool {
        return parseAddress(input, expectedNetwork: networkConfig) != nil
    }
    
    /// Get all addresses from a list that match a specific network configuration
    static func filterAddresses(_ addresses: [ParsedAddress], for networkConfig: NetworkConfig) -> [ParsedAddress] {
        return addresses.filter { address in
            // For addresses without networks (Lightning, BIP-353), always include them
            guard let addressNetwork = address.network else { 
                return !address.format.supportsBitcoinNetworks 
            }
            
            // For network-aware addresses (Bitcoin, Ark), check network match
            return addressNetwork.matches(networkConfig)
        }
    }
}
