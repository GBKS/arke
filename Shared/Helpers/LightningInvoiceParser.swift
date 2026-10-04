//
//  LightningInvoiceParser.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/5/25.
//

import Foundation

// MARK: - Lightning Invoice Data Models

struct LightningInvoiceArke {
    let amountSatoshis: UInt64?
    let description: String?
    let timestamp: Date?
    let network: Network
    let paymentHash: String?
    
    enum Network: String, CaseIterable {
        case mainnet = "bc"
        case testnet = "tb"
        case regtest = "rt"
        case simnet = "sb"
    }
}

enum LightningInvoiceParseError: Error, LocalizedError {
    case invalidBech32Encoding
    case bitConversionFailed
    case payloadTooShort
    case unknownAmountUnit(Character)
    case invalidNumericAmount
    
    var errorDescription: String? {
        switch self {
        case .invalidBech32Encoding:
            return "Invalid bech32 encoding"
        case .bitConversionFailed:
            return "Failed to convert bit groups"
        case .payloadTooShort:
            return "Invoice payload is too short"
        case .unknownAmountUnit(let unit):
            return "Unknown amount unit: \(unit)"
        case .invalidNumericAmount:
            return "Cannot parse numeric amount"
        }
    }
}

// MARK: - Lightning Invoice Parser

struct LightningInvoiceParser {
    
    // MARK: - Public API
    
    /// Parse a Lightning Network BOLT-11 invoice string
    /// - Parameter invoice: The invoice string to parse
    /// - Returns: A parsed LightningInvoice or throws an error
    static func parse(_ invoice: String) throws -> LightningInvoiceArke {
        // 1) Bech32 decode
        guard let (hrp, data5) = Self.bech32Decode(invoice) else {
            throw LightningInvoiceParseError.invalidBech32Encoding
        }

        // 2) Parse network from HRP
        let network = Self.parseNetwork(from: hrp)
        
        // 3) Parse amount from HRP
        let amountSatoshis = try Self.parseAmount(from: hrp)

        // 4) Parse description, timestamp, and payment hash from payload
        let (description, timestamp, paymentHash) = try Self.parsePayload(data5)
        
        return LightningInvoiceArke(
            amountSatoshis: amountSatoshis,
            description: description,
            timestamp: timestamp,
            network: network,
            paymentHash: paymentHash
        )
    }
    
    /// Quick extraction of amount and description (legacy API compatibility)
    static func extractAmountAndDescription(fromInvoice invoice: String) -> (amountSat: UInt64?, description: String?) {
        do {
            let parsed = try parse(invoice)
            return (parsed.amountSatoshis, parsed.description)
        } catch {
            return (nil, nil)
        }
    }
    
    /// Extract payment hash from a BOLT-11 invoice
    /// - Parameter invoice: The invoice string to parse
    /// - Returns: The payment hash as a hex string, or nil if parsing fails
    static func extractPaymentHash(fromInvoice invoice: String) -> String? {
        do {
            let parsed = try parse(invoice)
            return parsed.paymentHash
        } catch {
            return nil
        }
    }
}

// MARK: - Private Implementation

private extension LightningInvoiceParser {
    
    // MARK: - Bech32 Decoding
    
    static let bech32Charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func bech32Decode(_ input: String) -> (hrp: String, data: [UInt8])? {
        let lower = input.lowercased()
        guard let pos = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[..<pos])
        let dataPart = lower[lower.index(after: pos)...]
        var data = [UInt8]()
        for ch in dataPart {
            guard let idx = bech32Charset.firstIndex(of: ch) else { return nil }
            data.append(UInt8(idx))
        }
        return (hrp, data)
    }

    // Convert array of 5-bit values to bytes (8-bit)
    static func convertBits(from data: [UInt8], fromBits: Int = 5, toBits: Int = 8, pad: Bool = false) -> [UInt8]? {
        var acc = 0
        var bits = 0
        let maxv = (1 << toBits) - 1
        var ret = [UInt8]()
        for value in data {
            if (value >> fromBits) != 0 { return nil } // invalid value
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                let v = (acc >> bits) & maxv
                ret.append(UInt8(v))
            }
        }
        if pad {
            if bits > 0 {
                let v = (acc << (toBits - bits)) & maxv
                ret.append(UInt8(v))
            }
        } else {
            if bits >= fromBits { return nil }
            if ( (acc << (toBits - bits)) & maxv ) != 0 { return nil }
        }
        return ret
    }
    
    // MARK: - Network Parsing
    
    static func parseNetwork(from hrp: String) -> LightningInvoiceArke.Network {
        // hrp format: "ln" + network + optional amount
        // e.g., "lnbc2500u", "lntb", "lnrt1000m"
        if hrp.hasPrefix("lnbc") {
            return .mainnet
        } else if hrp.hasPrefix("lntb") {
            return .testnet
        } else if hrp.hasPrefix("lnrt") {
            return .regtest
        } else if hrp.hasPrefix("lnsb") {
            return .simnet
        } else {
            // Default to mainnet if unknown
            return .mainnet
        }
    }

    // MARK: - Amount Parsing
    
    /// 21 million BTC in satoshis
    static let maxAmountSatoshis: Double = 2_100_000_000_000_000

    /// Parse amount from HRP, returns amount in satoshis
    /// Supports units: (no suffix) = BTC, m = milli, u = micro, n = nano, p = pico
    static func parseAmount(from hrp: String) throws -> UInt64? {
        // Find first digit in string
        guard let digitsStart = hrp.firstIndex(where: { $0.isNumber }) else {
            return nil // No amount specified
        }
        
        let numericAndUnit = String(hrp[digitsStart...]) // e.g. "2500u"
        
        // Separate numeric part and optional unit
        let lastChar = numericAndUnit.last!
        let numericPart: String
        let unit: Character?
        
        if lastChar.isNumber {
            numericPart = numericAndUnit
            unit = nil
        } else {
            unit = lastChar
            numericPart = String(numericAndUnit.dropLast())
        }
        
        // Digits only: Double also accepts "1e500", "inf" and hex floats,
        // none of which BOLT-11 allows
        guard !numericPart.isEmpty,
              numericPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double(numericPart) else {
            throw LightningInvoiceParseError.invalidNumericAmount
        }
        
        // BOLT-11 unit rules: no suffix = BTC, m = milliBTC, u = microBTC, n = nanoBTC, p = picoBTC
        // Convert to satoshis: 1 BTC = 100_000_000 sat
        let sats: Double
        switch unit {
        case nil:
            sats = value * 100_000_000.0
        case "m":
            sats = value * 100_000.0
        case "u":
            sats = value * 100.0
        case "n":
            sats = value * 0.1
        case "p":
            // p (pico-BTC) => each unit is 0.000000000001 BTC -> that's 0.0001 sats (millisats)
            sats = value * 0.0001
        default:
            throw LightningInvoiceParseError.unknownAmountUnit(unit!)
        }
        
        // Round to nearest sat. More than the 21M BTC supply is not an
        // amount, and past the integer range the conversion would trap — the
        // HRP is read before any checksum or signature is checked.
        let rounded = sats.rounded(.toNearestOrEven)
        guard rounded <= maxAmountSatoshis else {
            throw LightningInvoiceParseError.invalidNumericAmount
        }
        return UInt64(rounded)
    }
    
    // MARK: - Payload Parsing
    
    static func parsePayload(_ data5: [UInt8]) throws -> (description: String?, timestamp: Date?, paymentHash: String?) {
        // Convert 5-bit groups into a bit stream
        var bits = [UInt8]()
        for w in data5 {
            for i in (0..<5).reversed() {
                let b = (w >> i) & 1
                bits.append(b)
            }
        }
        
        var cursor = 0
        func readBits(_ n: Int) -> UInt64? {
            guard n <= 64 else { return nil }
            guard cursor + n <= bits.count else { return nil }
            var v: UInt64 = 0
            for _ in 0..<n {
                v = (v << 1) | UInt64(bits[cursor])
                cursor += 1
            }
            return v
        }

        // Read timestamp (35 bits)
        guard let timestampValue = readBits(35) else {
            throw LightningInvoiceParseError.payloadTooShort
        }
        
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampValue))
        
        // Parse tags to find description and payment hash
        var foundDescription: String? = nil
        var foundPaymentHash: String? = nil
        
        while cursor + 15 <= bits.count {
            guard let tagTypeVal = readBits(5),
                  let dataLenGroups = readBits(10) else { break }

            let tagType = Int(tagTypeVal)
            let dataLen = Int(dataLenGroups)
            
            // Ensure we have enough bits for the data
            guard cursor + dataLen * 5 <= bits.count else { break }
            
            // Read the data groups for this tag
            var tagGroups = [UInt8]()
            for _ in 0..<dataLen {
                if let g = readBits(5) {
                    tagGroups.append(UInt8(g))
                } else {
                    break
                }
            }

            // BOLT-11 tag types (using bech32 5-bit values directly)
            // Tag type 1 (p) = payment_hash
            // Tag type 13 (d) = description
            
            if tagType == 1 {
                // payment_hash: The data is in 5-bit groups, need to convert to 8-bit bytes
                // Payment hash is 32 bytes (256 bits), which is 52 groups of 5 bits (260 bits, last 4 bits are padding)
                if let bytes = convertBits(from: tagGroups, fromBits: 5, toBits: 8, pad: false) {
                    // Verify we got exactly 32 bytes
                    if bytes.count == 32 {
                        // Convert to hex string
                        foundPaymentHash = bytes.map { String(format: "%02x", $0) }.joined()
                    }
                }
            } else if tagType == 13 {
                // description: convert 5-bit groups to UTF-8 bytes
                if let bytes = convertBits(from: tagGroups, fromBits: 5, toBits: 8, pad: true),
                   let description = String(bytes: bytes, encoding: .utf8),
                   !description.isEmpty {
                    foundDescription = description
                }
            }
            
            // Continue parsing to find all relevant tags
            if foundDescription != nil && foundPaymentHash != nil {
                break // Found everything we need
            }
        }

        return (foundDescription, timestamp, foundPaymentHash)
    }
}
