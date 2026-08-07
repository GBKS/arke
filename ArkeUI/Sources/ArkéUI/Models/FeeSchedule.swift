//
//  FeeSchedule.swift
//  ArkéUI
//
//  Created by Claude on 04/17/26.
//  Moved into ArkéUI as pure, previewable presentation value types
//  (no SwiftData/Bark).
//

import Foundation

/// Represents a PPM (parts per million) fee tier based on VTXO expiry thresholds
public struct PpmExpiryEntry: Codable, Sendable, Equatable {
    public let expiryBlocksThreshold: Int
    public let ppm: Int

    enum CodingKeys: String, CodingKey {
        case expiryBlocksThreshold = "expiry_blocks_threshold"
        case ppm
    }

    public init(expiryBlocksThreshold: Int, ppm: Int) {
        self.expiryBlocksThreshold = expiryBlocksThreshold
        self.ppm = ppm
    }
}

/// Fee structure for boarding operations (receiving on-chain funds)
public struct BoardFeeStructure: Codable, Sendable, Equatable {
    public let minFeeSat: Int
    public let baseFeeSat: Int
    public let ppm: Int

    enum CodingKeys: String, CodingKey {
        case minFeeSat = "min_fee_sat"
        case baseFeeSat = "base_fee_sat"
        case ppm
    }

    public init(minFeeSat: Int, baseFeeSat: Int, ppm: Int) {
        self.minFeeSat = minFeeSat
        self.baseFeeSat = baseFeeSat
        self.ppm = ppm
    }

    /// Calculate the boarding fee for a given amount
    /// - Parameter amountSats: The amount in satoshis
    /// - Returns: The fee in satoshis
    public func calculateFee(amountSats: Int) -> Int {
        let ppmFee = (amountSats * ppm) / 1_000_000
        let totalFee = baseFeeSat + ppmFee
        return max(totalFee, minFeeSat)
    }
}

/// Fee structure for offboarding operations (sending to on-chain)
public struct OffboardFeeStructure: Codable, Sendable, Equatable {
    public let baseFeeSat: Int
    public let fixedAdditionalVb: Int
    public let ppmExpiryTable: [PpmExpiryEntry]

    enum CodingKeys: String, CodingKey {
        case baseFeeSat = "base_fee_sat"
        case fixedAdditionalVb = "fixed_additional_vb"
        case ppmExpiryTable = "ppm_expiry_table"
    }

    public init(baseFeeSat: Int, fixedAdditionalVb: Int, ppmExpiryTable: [PpmExpiryEntry]) {
        self.baseFeeSat = baseFeeSat
        self.fixedAdditionalVb = fixedAdditionalVb
        self.ppmExpiryTable = ppmExpiryTable
    }

    /// Calculate the offboard fee for a given amount and VTXO expiry
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - blocksUntilExpiry: Number of blocks until VTXO expiry
    ///   - feerateSatPerVb: The current feerate in sat/vB (for vbyte calculation)
    /// - Returns: The fee in satoshis
    public func calculateFee(amountSats: Int, blocksUntilExpiry: Int, feerateSatPerVb: Int) -> Int {
        let ppm = getPpm(blocksUntilExpiry: blocksUntilExpiry)
        let ppmFee = (amountSats * ppm) / 1_000_000
        let vbyteFee = fixedAdditionalVb * feerateSatPerVb
        return baseFeeSat + ppmFee + vbyteFee
    }

    /// Get the PPM rate for a given expiry
    /// - Parameter blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: The PPM rate
    public func getPpm(blocksUntilExpiry: Int) -> Int {
        // Find the highest threshold that is less than or equal to blocksUntilExpiry
        // The table should be sorted by expiry_blocks_threshold ascending
        var applicablePpm = 0
        for entry in ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }) {
            if blocksUntilExpiry >= entry.expiryBlocksThreshold {
                applicablePpm = entry.ppm
            } else {
                break
            }
        }
        return applicablePpm
    }
}

/// Fee structure for refresh operations (extending VTXO expiry)
public struct RefreshFeeStructure: Codable, Sendable, Equatable {
    public let baseFeeSat: Int
    public let ppmExpiryTable: [PpmExpiryEntry]

    enum CodingKeys: String, CodingKey {
        case baseFeeSat = "base_fee_sat"
        case ppmExpiryTable = "ppm_expiry_table"
    }

    public init(baseFeeSat: Int, ppmExpiryTable: [PpmExpiryEntry]) {
        self.baseFeeSat = baseFeeSat
        self.ppmExpiryTable = ppmExpiryTable
    }

    /// Calculate the refresh fee for a given amount and VTXO expiry
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: The fee in satoshis
    public func calculateFee(amountSats: Int, blocksUntilExpiry: Int) -> Int {
        let ppm = getPpm(blocksUntilExpiry: blocksUntilExpiry)
        let ppmFee = (amountSats * ppm) / 1_000_000
        return baseFeeSat + ppmFee
    }

    /// Get the PPM rate for a given expiry
    /// - Parameter blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: The PPM rate
    public func getPpm(blocksUntilExpiry: Int) -> Int {
        // Find the highest threshold that is less than or equal to blocksUntilExpiry
        var applicablePpm = 0
        for entry in ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }) {
            if blocksUntilExpiry >= entry.expiryBlocksThreshold {
                applicablePpm = entry.ppm
            } else {
                break
            }
        }
        return applicablePpm
    }

    /// Check if refresh is free for the given expiry
    /// - Parameter blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: True if the refresh fee is zero
    public func isFreeRefresh(blocksUntilExpiry: Int) -> Bool {
        return baseFeeSat == 0 && getPpm(blocksUntilExpiry: blocksUntilExpiry) == 0
    }

    /// The size of the free refresh window: refreshing is free while a VTXO
    /// is fewer than this many blocks away from expiry. Returns `Int.max`
    /// when refreshes are always free and `nil` when they never are.
    public var freeRefreshBlocks: Int? {
        guard baseFeeSat == 0 else { return nil }
        let sorted = ppmExpiryTable.sorted { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }
        for entry in sorted where entry.ppm > 0 {
            return entry.expiryBlocksThreshold > 0 ? entry.expiryBlocksThreshold : nil
        }
        return .max
    }
}

/// Fee structure for receiving Lightning payments
public struct LightningReceiveFeeStructure: Codable, Sendable, Equatable {
    public let baseFeeSat: Int
    public let ppm: Int

    enum CodingKeys: String, CodingKey {
        case baseFeeSat = "base_fee_sat"
        case ppm
    }

    public init(baseFeeSat: Int, ppm: Int) {
        self.baseFeeSat = baseFeeSat
        self.ppm = ppm
    }

    /// Calculate the Lightning receive fee for a given amount
    /// - Parameter amountSats: The amount in satoshis
    /// - Returns: The fee in satoshis
    public func calculateFee(amountSats: Int) -> Int {
        let ppmFee = (amountSats * ppm) / 1_000_000
        return baseFeeSat + ppmFee
    }
}

/// Fee structure for sending Lightning payments
public struct LightningSendFeeStructure: Codable, Sendable, Equatable {
    public let minFeeSat: Int
    public let baseFeeSat: Int
    public let ppmExpiryTable: [PpmExpiryEntry]

    enum CodingKeys: String, CodingKey {
        case minFeeSat = "min_fee_sat"
        case baseFeeSat = "base_fee_sat"
        case ppmExpiryTable = "ppm_expiry_table"
    }

    public init(minFeeSat: Int, baseFeeSat: Int, ppmExpiryTable: [PpmExpiryEntry]) {
        self.minFeeSat = minFeeSat
        self.baseFeeSat = baseFeeSat
        self.ppmExpiryTable = ppmExpiryTable
    }

    /// Calculate the Lightning send fee for a given amount and VTXO expiry
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: The fee in satoshis
    public func calculateFee(amountSats: Int, blocksUntilExpiry: Int) -> Int {
        let ppm = getPpm(blocksUntilExpiry: blocksUntilExpiry)
        let ppmFee = (amountSats * ppm) / 1_000_000
        let totalFee = baseFeeSat + ppmFee
        return max(totalFee, minFeeSat)
    }

    /// Get the PPM rate for a given expiry
    /// - Parameter blocksUntilExpiry: Number of blocks until VTXO expiry
    /// - Returns: The PPM rate
    public func getPpm(blocksUntilExpiry: Int) -> Int {
        // Find the highest threshold that is less than or equal to blocksUntilExpiry
        var applicablePpm = 0
        for entry in ppmExpiryTable.sorted(by: { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }) {
            if blocksUntilExpiry >= entry.expiryBlocksThreshold {
                applicablePpm = entry.ppm
            } else {
                break
            }
        }
        return applicablePpm
    }
}

/// Complete fee schedule from the Ark server
public struct FeeSchedule: Codable, Sendable, Equatable {
    public let board: BoardFeeStructure
    public let offboard: OffboardFeeStructure
    public let refresh: RefreshFeeStructure
    public let lightningReceive: LightningReceiveFeeStructure
    public let lightningSend: LightningSendFeeStructure

    enum CodingKeys: String, CodingKey {
        case board
        case offboard
        case refresh
        case lightningReceive = "lightning_receive"
        case lightningSend = "lightning_send"
    }

    public init(board: BoardFeeStructure, offboard: OffboardFeeStructure, refresh: RefreshFeeStructure, lightningReceive: LightningReceiveFeeStructure, lightningSend: LightningSendFeeStructure) {
        self.board = board
        self.offboard = offboard
        self.refresh = refresh
        self.lightningReceive = lightningReceive
        self.lightningSend = lightningSend
    }

    // MARK: - Convenience methods for checking free operations

    /// Check if boarding is free for the given amount
    public func isFreeBoard(amountSats: Int) -> Bool {
        return board.calculateFee(amountSats: amountSats) == 0
    }

    /// Check if refresh is free for the given expiry
    public func isFreeRefresh(blocksUntilExpiry: Int) -> Bool {
        return refresh.isFreeRefresh(blocksUntilExpiry: blocksUntilExpiry)
    }

    /// Check if Lightning receive is free for the given amount
    public func isFreeLightningReceive(amountSats: Int) -> Bool {
        return lightningReceive.calculateFee(amountSats: amountSats) == 0
    }

    // MARK: - Human-readable fee descriptions

    /// Get a human-readable description of the fee structure for a specific operation
    public func feeDescription(for operation: FeeOperation) -> String {
        switch operation {
        case .board:
            if board.ppm == 0 && board.baseFeeSat == 0 && board.minFeeSat == 0 {
                return "Free"
            }
            var parts: [String] = []
            if board.baseFeeSat > 0 {
                parts.append("\(board.baseFeeSat) sats base")
            }
            if board.ppm > 0 {
                let percent = Double(board.ppm) / 10_000
                parts.append("\(String(format: "%.2f", percent))%")
            }
            if board.minFeeSat > 0 {
                parts.append("min \(board.minFeeSat) sats")
            }
            return parts.joined(separator: " + ")

        case .offboard:
            var parts: [String] = []
            if offboard.baseFeeSat > 0 {
                parts.append("\(offboard.baseFeeSat) sats base")
            }
            if offboard.fixedAdditionalVb > 0 {
                parts.append("\(offboard.fixedAdditionalVb) vB")
            }
            if !offboard.ppmExpiryTable.isEmpty {
                let ppmRanges = offboard.ppmExpiryTable.map { entry in
                    let percent = Double(entry.ppm) / 10_000
                    return "\(String(format: "%.2f", percent))% (≥\(entry.expiryBlocksThreshold) blocks)"
                }
                parts.append(ppmRanges.joined(separator: ", "))
            }
            return parts.isEmpty ? "Free" : parts.joined(separator: " + ")

        case .refresh:
            if refresh.ppmExpiryTable.isEmpty {
                return refresh.baseFeeSat == 0 ? "Free" : "\(refresh.baseFeeSat) sats"
            }
            var parts: [String] = []
            if refresh.baseFeeSat > 0 {
                parts.append("\(refresh.baseFeeSat) sats base")
            }
            let ppmRanges = refresh.ppmExpiryTable.map { entry in
                let percent = Double(entry.ppm) / 10_000
                return "\(String(format: "%.2f", percent))% (≥\(entry.expiryBlocksThreshold) blocks)"
            }
            parts.append(ppmRanges.joined(separator: ", "))
            return parts.joined(separator: " + ")

        case .lightningReceive:
            if lightningReceive.ppm == 0 && lightningReceive.baseFeeSat == 0 {
                return "Free"
            }
            var parts: [String] = []
            if lightningReceive.baseFeeSat > 0 {
                parts.append("\(lightningReceive.baseFeeSat) sats base")
            }
            if lightningReceive.ppm > 0 {
                let percent = Double(lightningReceive.ppm) / 10_000
                parts.append("\(String(format: "%.2f", percent))%")
            }
            return parts.joined(separator: " + ")

        case .lightningSend:
            var parts: [String] = []
            if lightningSend.baseFeeSat > 0 {
                parts.append("\(lightningSend.baseFeeSat) sats base")
            }
            if !lightningSend.ppmExpiryTable.isEmpty {
                let ppmRanges = lightningSend.ppmExpiryTable.map { entry in
                    let percent = Double(entry.ppm) / 10_000
                    return "\(String(format: "%.2f", percent))% (≥\(entry.expiryBlocksThreshold) blocks)"
                }
                parts.append(ppmRanges.joined(separator: ", "))
            }
            if lightningSend.minFeeSat > 0 {
                parts.append("min \(lightningSend.minFeeSat) sats")
            }
            return parts.isEmpty ? "Free" : parts.joined(separator: " + ")
        }
    }
}

/// Enum representing different fee operations
public enum FeeOperation: Sendable {
    case board
    case offboard
    case refresh
    case lightningReceive
    case lightningSend
}
