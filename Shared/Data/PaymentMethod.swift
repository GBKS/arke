//
//  PaymentMethod.swift
//  Ark wallet prototype
//
//  Payment method types for bark movements
//

import Foundation

/// Represents different payment method types supported by bark
/// Uses heuristic detection to identify payment types from address strings
enum PaymentMethod: Codable, Hashable, Sendable {
    case ark(address: String)
    case bitcoin(address: String)
    case invoice(value: String)
    case offer(value: String)
    case lightningAddress(value: String)
    case outputScript(hex: String)
    case unknown(value: String)
    
    // MARK: - Detection
    
    /// Detect payment method type from a string using heuristics
    /// - Parameter string: The address/payment identifier string
    /// - Returns: Detected payment method with the original value
    static func detect(from string: String) -> PaymentMethod {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ark addresses (ark1...)
        if trimmed.hasPrefix("ark1") {
            return .ark(address: trimmed)
        }
        
        // Lightning BOLT11 invoices (lnbc, lntb, lnbcrt for mainnet/testnet/regtest)
        if trimmed.hasPrefix("lnbc") || trimmed.hasPrefix("lntb") || trimmed.hasPrefix("lnbcrt") {
            return .invoice(value: trimmed)
        }
        
        // Lightning BOLT12 offers (lno1)
        if trimmed.hasPrefix("lno1") {
            return .offer(value: trimmed)
        }
        
        // Lightning addresses (email format)
        if trimmed.contains("@") && !trimmed.contains(" ") {
            let components = trimmed.split(separator: "@")
            if components.count == 2 && !components[1].isEmpty {
                return .lightningAddress(value: trimmed)
            }
        }
        
        // Bitcoin bech32/bech32m addresses (bc1, tb1, bcrt1)
        if trimmed.hasPrefix("bc1") || trimmed.hasPrefix("tb1") || trimmed.hasPrefix("bcrt1") {
            return .bitcoin(address: trimmed)
        }
        
        // Bitcoin legacy addresses (1, 3 for mainnet, m, n, 2 for testnet)
        if let first = trimmed.first, "13mn2".contains(first) {
            return .bitcoin(address: trimmed)
        }
        
        // Hex-encoded output scripts (even length hex string)
        if trimmed.count % 2 == 0 && trimmed.count > 0 && trimmed.allSatisfy({ $0.isHexDigit }) {
            return .outputScript(hex: trimmed)
        }
        
        // Unknown/custom
        return .unknown(value: trimmed)
    }
    
    // MARK: - Properties
    
    /// The original string value
    var value: String {
        switch self {
        case .ark(let address): return address
        case .bitcoin(let address): return address
        case .invoice(let value): return value
        case .offer(let value): return value
        case .lightningAddress(let value): return value
        case .outputScript(let hex): return hex
        case .unknown(let value): return value
        }
    }
    
    /// Display name for UI
    var displayType: String {
        switch self {
        case .ark: return "Ark"
        case .bitcoin: return "Bitcoin"
        case .invoice: return "Lightning Invoice"
        case .offer: return "Lightning Offer"
        case .lightningAddress: return "Lightning Address"
        case .outputScript: return "Output Script"
        case .unknown: return L10n.dataUnknown
        }
    }
    
    /// Short display name for compact UI
    var shortDisplayType: String {
        switch self {
        case .ark: return "Ark"
        case .bitcoin: return "BTC"
        case .invoice: return "LN Invoice"
        case .offer: return "LN Offer"
        case .lightningAddress: return "LN Address"
        case .outputScript: return "Script"
        case .unknown: return "?"
        }
    }
    
    /// System icon name (SF Symbols)
    var systemIcon: String {
        switch self {
        case .ark: return "cube.box.fill"
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .invoice, .offer, .lightningAddress: return "bolt.fill"
        case .outputScript: return "chevron.left.forwardslash.chevron.right"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// Icon color name for theming
    var iconColorName: String {
        switch self {
        case .ark: return "purple"
        case .bitcoin: return "orange"
        case .invoice, .offer, .lightningAddress: return "yellow"
        case .outputScript: return "blue"
        case .unknown: return "gray"
        }
    }
    
    /// Whether this is a Lightning-based payment method
    var isLightning: Bool {
        switch self {
        case .invoice, .offer, .lightningAddress:
            return true
        default:
            return false
        }
    }
    
    /// Whether this is an onchain payment method
    var isOnchain: Bool {
        switch self {
        case .bitcoin, .outputScript:
            return true
        default:
            return false
        }
    }
    
    /// Whether this is an offchain Ark payment
    var isArkOffchain: Bool {
        if case .ark = self {
            return true
        }
        return false
    }
    
    /// Whether this payment method represents a single-use identifier that should not be saved as a persistent address
    var isSingleUse: Bool {
        switch self {
        case .invoice:
            return true  // Lightning invoices are single-use and expire
        case .ark, .bitcoin, .lightningAddress, .offer, .outputScript, .unknown:
            return false
        }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    enum PaymentMethodType: String, Codable {
        case ark
        case bitcoin
        case invoice
        case offer
        case lightningAddress = "lightning-address"
        case outputScript = "output-script"
        case unknown
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .ark(let address):
            try container.encode(PaymentMethodType.ark, forKey: .type)
            try container.encode(address, forKey: .value)
        case .bitcoin(let address):
            try container.encode(PaymentMethodType.bitcoin, forKey: .type)
            try container.encode(address, forKey: .value)
        case .invoice(let value):
            try container.encode(PaymentMethodType.invoice, forKey: .type)
            try container.encode(value, forKey: .value)
        case .offer(let value):
            try container.encode(PaymentMethodType.offer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .lightningAddress(let value):
            try container.encode(PaymentMethodType.lightningAddress, forKey: .type)
            try container.encode(value, forKey: .value)
        case .outputScript(let hex):
            try container.encode(PaymentMethodType.outputScript, forKey: .type)
            try container.encode(hex, forKey: .value)
        case .unknown(let value):
            try container.encode(PaymentMethodType.unknown, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PaymentMethodType.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        
        switch type {
        case .ark:
            self = .ark(address: value)
        case .bitcoin:
            self = .bitcoin(address: value)
        case .invoice:
            self = .invoice(value: value)
        case .offer:
            self = .offer(value: value)
        case .lightningAddress:
            self = .lightningAddress(value: value)
        case .outputScript:
            self = .outputScript(hex: value)
        case .unknown:
            self = .unknown(value: value)
        }
    }
}

// MARK: - Character Extension

extension Character {
    /// Check if character is a valid hexadecimal digit
    var isHexDigit: Bool {
        return isNumber || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
