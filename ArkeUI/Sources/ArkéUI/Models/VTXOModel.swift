//
//  VTXOModel.swift
//  ArkéUI
//
//  Created by Christoph on 10/16/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark). Mapping from Bark's `Vtxo` lives app-side in
//  `VTXOModel+Bark.swift`, keeping this type free of Bark/FFI (which breaks
//  previews).
//

import SwiftUI

public enum VTXOState: String, Codable, CaseIterable, Sendable {
    case unregisteredBoard = "UnregisteredBoard"
    case registeredBoard = "RegisteredBoard"
    case spent = "Spent"
    case pending = "Pending"
    case spendable = "Spendable"
    case locked = "Locked"
    /// The VTXO is in (or has completed) a unilateral exit — the funds were
    /// moved onchain rather than forfeited in the protocol. Distinct from `.spent`.
    case exited = "Exited"
}

public extension VTXOState {
    var displayName: String {
        switch self {
        case .unregisteredBoard:
            return "Unregistered Board"
        case .registeredBoard:
            return "Registered Board"
        case .spent:
            return "Spent"
        case .pending:
            return "Pending"
        case .spendable:
            return "Spendable"
        case .locked:
            return "Locked"
        case .exited:
            return "Exited"
        }
    }

    var iconName: String {
        switch self {
        case .unregisteredBoard:
            return "clock.arrow.circlepath"
        case .registeredBoard:
            return "checkmark.circle"
        case .spent:
            return "xmark.circle"
        case .pending:
            return "hourglass"
        case .spendable:
            return "bitcoinsign.circle"
        case .locked:
            return "lock.circle"
        case .exited:
            return "arrow.up.forward.square"
        }
    }

    var iconColor: Color {
        switch self {
        case .unregisteredBoard:
            return .Arke.orange
        case .registeredBoard:
            return .Arke.green
        case .spent:
            return .gray
        case .pending:
            return .Arke.blue
        case .spendable:
            return .Arke.green
        case .locked:
            return .Arke.purple
        case .exited:
            return .Arke.orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .unregisteredBoard:
            return .Arke.orange.opacity(0.2)
        case .registeredBoard:
            return .Arke.green.opacity(0.2)
        case .spent:
            return .gray.opacity(0.2)
        case .pending:
            return .Arke.blue.opacity(0.2)
        case .spendable:
            return .Arke.green.opacity(0.3)
        case .locked:
            return .Arke.purple.opacity(0.3)
        case .exited:
            return .Arke.orange.opacity(0.2)
        }
    }

    var textColor: Color {
        switch self {
        case .unregisteredBoard:
            return .Arke.orange
        case .registeredBoard:
            return .Arke.green
        case .spent:
            return .gray
        case .pending:
            return .Arke.blue
        case .spendable:
            return .Arke.green
        case .locked:
            return .Arke.purple
        case .exited:
            return .Arke.orange
        }
    }
}

public enum VTXOKind: String, Codable, CaseIterable, Sendable {
    case pubkey = "pubkey"
    case checkpoint = "checkpoint"
    case serverHTLCSend = "server-htlc-send"
    case serverHTLCRecv = "server-htlc-receive"
    case expiry = "expiry"
    case board = "board"
    case round = "round"
    case arkoor = "arkoor"
}

public extension VTXOKind {
    var displayName: String {
        switch self {
        case .pubkey:
            return "Public Key"
        case .checkpoint:
            return "Checkpoint"
        case .serverHTLCSend:
            return "Server HTLC Send"
        case .serverHTLCRecv:
            return "Server HTLC Receive"
        case .expiry:
            return "Expiry"
        case .board:
            return "Board"
        case .round:
            return "Round"
        case .arkoor:
            return "Arkoor"
        }
    }
}

/// VTXO model that matches what Bark FFI provides
/// Only contains fields directly available from the Rust wallet
public struct VTXOModel: Codable, Identifiable, Hashable, Sendable {
    /// VTXO id in format "txid:vout"
    public let id: String
    /// Amount in satoshis
    public let amountSat: Int
    /// Expiry height (0 if unknown)
    public let expiryHeight: Int
    /// Type of VTXO (e.g., "board", "round", "arkoor", "pubkey")
    public let kind: VTXOKind
    /// State of VTXO (e.g., "spendable", "spent", "locked")
    public let state: VTXOState
    /// Genesis chain length (exit depth)
    public let exitDepth: UInt32
    /// Weight units of exit transaction chain
    public let exitTxWeightWu: UInt64

    // Coding keys to match serialization
    enum CodingKeys: String, CodingKey {
        case id
        case amountSat = "amount_sat"
        case expiryHeight = "expiry_height"
        case kind
        case state
        case exitDepth = "exit_depth"
        case exitTxWeightWu = "exit_tx_weight_wu"
    }

    public init(id: String, amountSat: Int, expiryHeight: Int, kind: VTXOKind, state: VTXOState, exitDepth: UInt32 = 0, exitTxWeightWu: UInt64 = 0) {
        self.id = id
        self.amountSat = amountSat
        self.expiryHeight = expiryHeight
        self.kind = kind
        self.state = state
        self.exitDepth = exitDepth
        self.exitTxWeightWu = exitTxWeightWu
    }

    // Computed properties for convenience
    public var formattedAmount: String {
        return BitcoinFormatter.shared.formatAmount(amountSat)
    }

    public var shortId: String {
        if id.count > 12 {
            return String(id.prefix(8)) + String(localized: "symbol_ellipsis")
        }
        return id
    }

    // Extract txid and vout from the id (which is in format "txid:vout")
    public var txid: String {
        return String(id.split(separator: ":").first ?? "")
    }

    public var vout: Int {
        if let voutString = id.split(separator: ":").last {
            return Int(voutString) ?? 0
        }
        return 0
    }

    public var outpoint: String {
        return id
    }

    public var shortTxid: String {
        let txidValue = txid
        if txidValue.count > 8 {
            return String(txidValue.prefix(8)) + String(localized: "symbol_ellipsis")
        }
        return txidValue
    }

    public var isSpent: Bool {
        return state == .spent
    }
}

// MARK: - Parsing helpers

public extension VTXOModel {
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

    // Legacy parsing method (kept for backward compatibility if needed)
    static func parseFromWalletOutput(_ output: String) -> [VTXOModel] {
        // This method would need to be updated based on the actual output format
        // For now, returning empty array as the format has changed significantly
        return []
    }
}

// MARK: - Sample Data

public extension VTXOModel {
    /// Stable sample values for previews and tests. No database or Bark required.
    static func mockVTXOs() -> [VTXOModel] {
        return [
            VTXOModel(
                id: "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
                amountSat: 1000,
                expiryHeight: 274399,
                kind: .board,
                state: .spendable,
                exitDepth: 1,
                exitTxWeightWu: 500
            ),
            VTXOModel(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:1",
                amountSat: 25000,
                expiryHeight: 274500,
                kind: .round,
                state: .spendable,
                exitDepth: 2,
                exitTxWeightWu: 750
            ),
            VTXOModel(
                id: "def456abc123789012345678901234567890abcdef123456789012345678901234:2",
                amountSat: 5000,
                expiryHeight: 0,
                kind: .arkoor,
                state: .locked,
                exitDepth: 3,
                exitTxWeightWu: 1000
            )
        ]
    }

    /// Convenience alias matching the sample-data naming used elsewhere in ArkéUI.
    static let samples: [VTXOModel] = mockVTXOs()
}

// MARK: - Preview

#Preview("VTXOModel sample data") {
    List(VTXOModel.samples) { vtxo in
        HStack {
            Image(systemName: vtxo.state.iconName)
                .foregroundStyle(vtxo.state.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(vtxo.kind.displayName)
                    .font(.headline)
                Text(vtxo.shortId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(vtxo.formattedAmount)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
    }
}
