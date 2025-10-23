//
//  OnchainBalanceModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

struct OnchainBalanceModel: Codable {
    let totalSat: Int
    let trustedSpendableSat: Int
    let immatureSat: Int
    let trustedPendingSat: Int
    let untrustedPendingSat: Int
    let confirmedSat: Int
    
    enum CodingKeys: String, CodingKey {
        case totalSat = "total_sat"
        case trustedSpendableSat = "trusted_spendable_sat"
        case immatureSat = "immature_sat"
        case trustedPendingSat = "trusted_pending_sat"
        case untrustedPendingSat = "untrusted_pending_sat"
        case confirmedSat = "confirmed_sat"
    }
    
    // Computed properties for convenience
    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
    
    var trustedSpendableBTC: Double {
        Double(trustedSpendableSat) / 100_000_000
    }
    
    var confirmedBTC: Double {
        Double(confirmedSat) / 100_000_000
    }
}
