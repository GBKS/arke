//
//  ArkConfigModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import Foundation

struct ArkConfigModel: Codable {
    let ark: String?
    let bitcoind: String?
    let bitcoindCookie: String?
    let bitcoindUser: String?
    let bitcoindPass: String?
    let esplora: String?
    let vtxoRefreshExpiryThreshold: Int
    let fallbackFeeRateKvb: Int
    
    enum CodingKeys: String, CodingKey {
        case ark
        case bitcoind
        case bitcoindCookie = "bitcoind_cookie"
        case bitcoindUser = "bitcoind_user"
        case bitcoindPass = "bitcoind_pass"
        case esplora
        case vtxoRefreshExpiryThreshold = "vtxo_refresh_expiry_threshold"
        case fallbackFeeRateKvb = "fallback_fee_rate_kvb"
    }
    
    // Computed properties for convenience
    var hasArkEndpoint: Bool {
        ark != nil && !ark!.isEmpty
    }
    
    var hasEsploraEndpoint: Bool {
        esplora != nil && !esplora!.isEmpty
    }
    
    var hasBitcoindConnection: Bool {
        bitcoind != nil && !bitcoind!.isEmpty
    }
    
    var arkURL: URL? {
        guard let ark = ark else { return nil }
        return URL(string: ark)
    }
    
    var esploraURL: URL? {
        guard let esplora = esplora else { return nil }
        return URL(string: esplora)
    }
    
    var bitcoindURL: URL? {
        guard let bitcoind = bitcoind else { return nil }
        return URL(string: bitcoind)
    }
    
    // Formatted fallback fee rate in sat/vB
    var fallbackFeeRateSatPerVB: Double {
        Double(fallbackFeeRateKvb) / 1000.0
    }
    
    // Check if using signet endpoints (based on common signet domain patterns)
    var isSignetConfig: Bool {
        let signetKeywords = ["signet", "testnet"]
        let arkContainsSignet = signetKeywords.contains { keyword in
            ark?.lowercased().contains(keyword) ?? false
        }
        let esploraContainsSignet = signetKeywords.contains { keyword in
            esplora?.lowercased().contains(keyword) ?? false
        }
        return arkContainsSignet || esploraContainsSignet
    }
    
    // Configuration summary for display
    var configurationSummary: String {
        var summary = [String]()
        
        if hasArkEndpoint {
            summary.append("ARK: \(ark!)")
        }
        if hasEsploraEndpoint {
            summary.append("Esplora: \(esplora!)")
        }
        if hasBitcoindConnection {
            summary.append("Bitcoin Core: \(bitcoind!)")
        }
        
        summary.append("Fee Rate: \(Int(fallbackFeeRateSatPerVB)) sat/vB")
        summary.append("Refresh Threshold: \(vtxoRefreshExpiryThreshold) blocks")
        
        return summary.joined(separator: "\n")
    }
}