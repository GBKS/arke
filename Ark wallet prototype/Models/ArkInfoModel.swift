//
//  ArkInfoModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import Foundation

struct ArkInfoModel: Codable {
    let network: String
    let serverPubkey: String
    let roundInterval: String
    let nbRoundNonces: Int
    let vtxoExitDelta: Int
    let vtxoExpiryDelta: Int
    let htlcExpiryDelta: Int
    let maxVtxoAmount: Int
    let maxArkoorDepth: Int
    let requiredBoardConfirmations: Int
    
    enum CodingKeys: String, CodingKey {
        case network
        case serverPubkey = "server_pubkey"
        case roundInterval = "round_interval"
        case nbRoundNonces = "nb_round_nonces"
        case vtxoExitDelta = "vtxo_exit_delta"
        case vtxoExpiryDelta = "vtxo_expiry_delta"
        case htlcExpiryDelta = "htlc_expiry_delta"
        case maxVtxoAmount = "max_vtxo_amount"
        case maxArkoorDepth = "max_arkoor_depth"
        case requiredBoardConfirmations = "required_board_confirmations"
    }
    
    // Computed properties for convenience
    var maxVtxoAmountBTC: Double {
        Double(maxVtxoAmount) / 100_000_000
    }
    
    var isSignetNetwork: Bool {
        network.lowercased() == "signet"
    }
    
    var isMainnetNetwork: Bool {
        network.lowercased() == "mainnet"
    }
    
    var isTestnetNetwork: Bool {
        network.lowercased() == "testnet"
    }
    
    // Parse round interval (assumes format like "30s")
    var roundIntervalSeconds: Int? {
        guard roundInterval.hasSuffix("s") else { return nil }
        let numberString = String(roundInterval.dropLast())
        return Int(numberString)
    }
    
    // Formatted server pubkey for display (first 8 and last 8 characters)
    var serverPubkeyShort: String {
        guard serverPubkey.count >= 16 else { return serverPubkey }
        let start = serverPubkey.prefix(8)
        let end = serverPubkey.suffix(8)
        return "\(start)...\(end)"
    }
}