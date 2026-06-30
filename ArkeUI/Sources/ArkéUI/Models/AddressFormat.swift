//
//  AddressFormat.swift
//  ArkéUI
//
//  Created by Christoph on 11/17/25.
//  Moved into ArkéUI as a pure presentation value type (no SwiftData/Bark).
//

import Foundation

public enum AddressFormat: String, CaseIterable, Codable, Sendable {
    case bitcoin = "Bitcoin"
    case ark = "Ark"
    case lightning = "Lightning"
    case lightningInvoice = "Lightning Invoice"
    case lnurl = "LNURL"
    case bolt12 = "BOLT12"
    case bip353 = "BIP-353"
    case bip21 = "BIP-21"
    case silentPayments = "Silent Payments"

    public var displayName: String {
        switch self {
        case .bitcoin:
            return "Bitcoin address"
        case .ark:
            return "Ark address"
        case .lightning:
            return "Lightning address"
        case .lightningInvoice:
            return "Lightning invoice"
        case .lnurl:
            return "LNURL-pay"
        case .bolt12:
            return "Lightning offer"
        case .bip353:
            return "BIP-353 address"
        case .bip21:
            return "BIP-21 payment URI"
        case .silentPayments:
            return "Silent payments address"
        }
    }

    public var simplifiedDisplayName: String {
        switch self {
        case .bitcoin:
            return "Savings (Bitcoin)"
        case .ark:
            return "Payments (Ark)"
        case .lightning:
            return "Payments (Lightning)"
        case .lightningInvoice:
            return "Payments (Lightning)"
        case .lnurl:
            return "Payments (LNURL)"
        case .bolt12:
            return "Payments (Lightning)"
        case .bip353:
            return "BIP-353 address"
        case .bip21:
            return "BIP-21 payment URI"
        case .silentPayments:
            return "Savings (Silent payments)"
        }
    }

    public var supportsBitcoinNetworks: Bool {
        switch self {
        case .bitcoin, .silentPayments, .bip21, .ark:
            return true
        case .lightning, .lightningInvoice, .lnurl, .bolt12, .bip353:
            return false
        }
    }
}
