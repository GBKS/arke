//
//  OnchainTransactionModel.swift
//  Arké
//
//  Model for onchain Bitcoin transactions from BDK wallet
//

import Foundation

/// Represents an onchain Bitcoin transaction with full details
nonisolated struct OnchainTransactionModel: Identifiable, Codable, Hashable {
    let txid: String
    let received: UInt64
    let sent: UInt64
    let fee: UInt64?
    let confirmationTime: ConfirmationTime?
    let isSelfTransfer: Bool
    
    var id: String { txid }
    
    /// Net amount change (positive = received, negative = sent)
    var netAmount: Int64 {
        Int64(received) - Int64(sent)
    }
    
    /// Whether this is an incoming transaction
    var isIncoming: Bool {
        netAmount > 0
    }
    
    /// Short transaction ID for display (first 8 chars)
    var shortTxid: String {
        String(txid.prefix(8))
    }
    
    /// Number of confirmations (0 if unconfirmed)
    var confirmations: UInt32 {
        confirmationTime?.confirmations ?? 0
    }
    
    /// Whether transaction is confirmed
    var isConfirmed: Bool {
        confirmationTime != nil
    }
    
    /// Display amount (absolute value of net amount)
    var displayAmount: UInt64 {
        UInt64(abs(netAmount))
    }
    
    /// Transaction timestamp (nil if unconfirmed, or if the block time
    /// hasn't been resolved yet)
    var timestamp: Date? {
        guard let timestamp = confirmationTime?.timestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

/// Confirmation details for a transaction
nonisolated struct ConfirmationTime: Codable, Hashable {
    let height: UInt32
    /// Unix block time. Bark's `BlockRef` carries no timestamp, so this is
    /// resolved separately (Esplora block lookup) and can lag a refresh.
    let timestamp: UInt64?
    let blockHash: String?
    let currentHeight: UInt32?
    
    /// Calculate confirmations based on current block height
    /// Returns 1 if currentHeight is not available (minimum for confirmed transactions)
    var confirmations: UInt32 {
        guard let currentHeight = currentHeight else {
            return 1 // Confirmed but current height unknown
        }
        
        // Calculate: currentHeight - txHeight + 1
        // +1 because a transaction in block 100 has 1 confirmation at height 100
        if currentHeight >= height {
            return currentHeight - height + 1
        } else {
            return 1 // Shouldn't happen, but handle gracefully
        }
    }
}

// MARK: - Conversion from BDK Types
// TODO: Implement when BDK 2.x integration is complete

// MARK: - Mock Data for Previews

extension OnchainTransactionModel {
    static func mockIncoming() -> OnchainTransactionModel {
        OnchainTransactionModel(
            txid: "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456",
            received: 50_000,
            sent: 0,
            fee: nil,
            confirmationTime: ConfirmationTime(
                height: 800_000,
                timestamp: UInt64(Date().timeIntervalSince1970),
                blockHash: "00000000000000000001234567890abcdef1234567890abcdef1234567890ab",
                currentHeight: 800_005
            ),
            isSelfTransfer: false
        )
    }
    
    static func mockOutgoing() -> OnchainTransactionModel {
        OnchainTransactionModel(
            txid: "b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef1234567",
            received: 0,
            sent: 30_000,
            fee: 500,
            confirmationTime: ConfirmationTime(
                height: 799_950,
                timestamp: UInt64(Date().timeIntervalSince1970 - 3600),
                blockHash: "00000000000000000009876543210fedcba0987654321fedcba098765432100",
                currentHeight: 800_005
            ),
            isSelfTransfer: false
        )
    }
    
    static func mockPending() -> OnchainTransactionModel {
        OnchainTransactionModel(
            txid: "c3d4e5f6789012345678901234567890abcdef1234567890abcdef12345678",
            received: 100_000,
            sent: 0,
            fee: nil,
            confirmationTime: nil,
            isSelfTransfer: false
        )
    }
    
    static func mockTransactions() -> [OnchainTransactionModel] {
        [
            mockIncoming(),
            mockOutgoing(),
            mockPending()
        ]
    }
}
