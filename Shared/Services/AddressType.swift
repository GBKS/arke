//
//  AddressType.swift
//  Ark wallet prototype
//
//  Created by Assistant on 1/12/26.
//

import Foundation

/// Type of wallet address
enum AddressType: String, Codable, CaseIterable {
    case ark = "ark"
    case onchain = "onchain"
    
    var displayName: String {
        switch self {
        case .ark: return String(localized: "activity_ark_address")
        case .onchain: return String(localized: "activity_bitcoin_address")
        }
    }
    
    /// Whether this address type can be safely reused
    var canReuse: Bool {
        switch self {
        case .ark: return true  // Ark addresses can be reused
        case .onchain: return false  // Best practice: one-time use for privacy
        }
    }
}
