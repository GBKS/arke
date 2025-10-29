//
//  VTXOModel.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation

enum VTXOState: String, Codable, CaseIterable, Sendable {
    case unregisteredBoard = "UnregisteredBoard"
    case registeredBoard = "RegisteredBoard"
    case spent = "Spent"
    case pending = "Pending"
    case spendable = "Spendable"
}

enum PolicyType: String, Codable, CaseIterable, Sendable {
    case pubkey = "pubkey"
    case multisig = "multisig"
}

struct VTXOModel: Codable, Identifiable, Hashable, Sendable {
    let id: String // Now uses the outpoint format from JSON
    let amountSat: Int
    let policyType: PolicyType
    let userPubkey: String
    let serverPubkey: String
    let expiryHeight: Int
    let exitDelta: Int
    let chainAnchor: String
    let exitDepth: Int
    let arkoorDepth: Int
    let state: VTXOState
    
    // Coding keys to match the JSON structure
    enum CodingKeys: String, CodingKey {
        case id
        case amountSat = "amount_sat"
        case policyType = "policy_type"
        case userPubkey = "user_pubkey"
        case serverPubkey = "server_pubkey"
        case expiryHeight = "expiry_height"
        case exitDelta = "exit_delta"
        case chainAnchor = "chain_anchor"
        case exitDepth = "exit_depth"
        case arkoorDepth = "arkoor_depth"
        case state
    }
    
    init(id: String, amountSat: Int, policyType: PolicyType, userPubkey: String, 
         serverPubkey: String, expiryHeight: Int, exitDelta: Int, 
         chainAnchor: String, exitDepth: Int, arkoorDepth: Int, state: VTXOState) {
        self.id = id
        self.amountSat = amountSat
        self.policyType = policyType
        self.userPubkey = userPubkey
        self.serverPubkey = serverPubkey
        self.expiryHeight = expiryHeight
        self.exitDelta = exitDelta
        self.chainAnchor = chainAnchor
        self.exitDepth = exitDepth
        self.arkoorDepth = arkoorDepth
        self.state = state
    }
    
    // Computed properties for convenience
    var formattedAmount: String {
        return BitcoinFormatter.formatAmount(amountSat)
    }
    
    var shortId: String {
        if id.count > 12 {
            return String(id.prefix(8)) + "..."
        }
        return id
    }
    
    // Extract txid and vout from the id (which is in format "txid:vout")
    var txid: String {
        return String(id.split(separator: ":").first ?? "")
    }
    
    var vout: Int {
        if let voutString = id.split(separator: ":").last {
            return Int(voutString) ?? 0
        }
        return 0
    }
    
    var outpoint: String {
        return id
    }
    
    var shortTxid: String {
        let txidValue = txid
        if txidValue.count > 8 {
            return String(txidValue.prefix(8)) + "..."
        }
        return txidValue
    }
    
    var isSpent: Bool {
        return state == .spent
    }
}

// Extension for parsing and mock data
extension VTXOModel {
    static func parseFromJSON(_ jsonData: Data) throws -> [VTXOModel] {
        let decoder = JSONDecoder()
        return try decoder.decode([VTXOModel].self, from: jsonData)
    }
    
    static func parseFromJSONString(_ jsonString: String) throws -> [VTXOModel] {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "VTXOModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
        }
        return try parseFromJSON(data)
    }
    
    static func mockVTXOs() -> [VTXOModel] {
        return [
            VTXOModel(
                id: "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
                amountSat: 1000,
                policyType: .pubkey,
                userPubkey: "0395fe00abc5cbb5b8949f70a0b9ff161ef4fed549323c598fee8d47c531b226d2",
                serverPubkey: "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
                expiryHeight: 274399,
                exitDelta: 12,
                chainAnchor: "e334ea46d851b90c173f4ce923f220a37baa4e0a52c5dfcb07f5c89902b79ef2:0",
                exitDepth: 1,
                arkoorDepth: 0,
                state: .unregisteredBoard
            ),
            VTXOModel(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:1",
                amountSat: 25000,
                policyType: .pubkey,
                userPubkey: "03abc123def456789012345678901234567890abcdef123456789012345678901234",
                serverPubkey: "02def456abc123789012345678901234567890abcdef123456789012345678901234",
                expiryHeight: 274500,
                exitDelta: 10,
                chainAnchor: "def456abc123789012345678901234567890abcdef123456789012345678901234:0",
                exitDepth: 2,
                arkoorDepth: 1,
                state: .registeredBoard
            )
        ]
    }
    
    // Legacy parsing method (kept for backward compatibility if needed)
    static func parseFromWalletOutput(_ output: String) -> [VTXOModel] {
        // This method would need to be updated based on the actual output format
        // For now, returning empty array as the format has changed significantly
        return []
    }
}
