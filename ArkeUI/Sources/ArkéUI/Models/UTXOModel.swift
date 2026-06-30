//
//  UTXOModel.swift
//  ArkéUI
//
//  Created by Christoph on 10/17/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark).
//

import SwiftUI

public struct UTXOModel: Codable, Identifiable, Hashable, Sendable {
    public let outpoint: String
    public let amountSat: Int
    public let confirmationHeight: Int?

    enum CodingKeys: String, CodingKey {
        case outpoint
        case amountSat = "amount_sat"
        case confirmationHeight = "confirmation_height"
    }

    public init(outpoint: String, amountSat: Int, confirmationHeight: Int? = nil) {
        self.outpoint = outpoint
        self.amountSat = amountSat
        self.confirmationHeight = confirmationHeight
    }

    // Identifiable conformance using outpoint as the unique identifier
    public var id: String {
        outpoint
    }

    // Computed properties for convenience
    public var amount: Int {
        amountSat
    }

    // Computed properties for convenience
    public var amountBTC: Double {
        Double(amountSat) / 100_000_000
    }

    // Parse transaction hash and output index from outpoint
    public var transactionHash: String {
        String(outpoint.split(separator: ":").first ?? "")
    }

    public var outputIndex: Int {
        Int(outpoint.split(separator: ":").last ?? "0") ?? 0
    }

    // Formatted amount for display
    public var formattedAmount: String {
        return BitcoinFormatter.shared.formatAmount(amountSat)
    }

    // Short outpoint for display (first 8 chars of hash + index)
    public var shortOutpoint: String {
        let hash = transactionHash
        let shortHash = hash.count > 8 ? String(hash.prefix(8)) : hash
        return "\(shortHash):\(outputIndex)"
    }
}

// Array extension for working with multiple UTXOs
public extension Array where Element == UTXOModel {
    var totalSat: Int {
        reduce(0) { $0 + $1.amountSat }
    }

    var totalBTC: Double {
        Double(totalSat) / 100_000_000
    }
}

// MARK: - Sample Data

public extension UTXOModel {
    /// Stable sample values for previews and tests. No database or Bark required.
    static let samples: [UTXOModel] = [
        UTXOModel(
            outpoint: "869a6f6856d1c6db0b0d2b323f13a796538c9f11dfe30a9a5d6c20ecfdcdb002:26",
            amountSat: 501_197,
            confirmationHeight: 274_144
        ),
        UTXOModel(
            outpoint: "2ee54cbb552dd2c3f2eccf29ecad06f70dadc8aafa92ab066415356f84732dee:22",
            amountSat: 1_100_738,
            confirmationHeight: 274_156
        ),
        UTXOModel(
            outpoint: "def456abc123789012345678901234567890abcdef123456789012345678901234:0",
            amountSat: 25_000,
            confirmationHeight: nil
        )
    ]
}

// MARK: - Preview

#Preview("UTXOModel sample data") {
    List(UTXOModel.samples) { utxo in
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(utxo.shortOutpoint)
                    .font(.headline.monospaced())
                Text(utxo.confirmationHeight.map { "Confirmed at \($0)" } ?? "Unconfirmed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(utxo.formattedAmount)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
    }
}
