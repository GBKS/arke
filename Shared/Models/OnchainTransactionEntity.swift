//
//  OnchainTransactionEntity.swift
//  Arké
//
//  SwiftData persistence model for onchain Bitcoin transactions
//

import Foundation
import SwiftData

/// SwiftData model for persisting onchain Bitcoin transactions
@Model
class OnchainTransactionEntity {
    
    // MARK: - Properties
    
    /// Transaction ID (unique identifier)
    @Attribute(.unique) var txid: String
    
    /// Amount received in satoshis
    var received: UInt64
    
    /// Amount sent in satoshis
    var sent: UInt64
    
    /// Transaction fee in satoshis (optional)
    var fee: UInt64?
    
    /// Whether this is a self-transfer (funds moved between own addresses)
    /// Detected by checking if all outputs belong to the wallet
    var isSelfTransfer: Bool
    
    // MARK: - Confirmation Details
    
    /// Block height where transaction was confirmed
    var confirmationHeight: UInt32?
    
    /// Unix timestamp when transaction was confirmed
    var confirmationTimestamp: UInt64?
    
    /// Block hash where transaction was confirmed
    var confirmationBlockHash: String?
    
    /// Current blockchain height at time of last update
    var currentHeight: UInt32?
    
    // MARK: - Metadata
    
    /// Last time this transaction was updated
    var lastUpdated: Date
    
    // MARK: - Initialization
    
    init(
        txid: String,
        received: UInt64,
        sent: UInt64,
        fee: UInt64?,
        isSelfTransfer: Bool,
        confirmationHeight: UInt32?,
        confirmationTimestamp: UInt64?,
        confirmationBlockHash: String?,
        currentHeight: UInt32?,
        lastUpdated: Date
    ) {
        self.txid = txid
        self.received = received
        self.sent = sent
        self.fee = fee
        self.isSelfTransfer = isSelfTransfer
        self.confirmationHeight = confirmationHeight
        self.confirmationTimestamp = confirmationTimestamp
        self.confirmationBlockHash = confirmationBlockHash
        self.currentHeight = currentHeight
        self.lastUpdated = lastUpdated
    }
    
    /// Initialize from OnchainTransactionModel
    convenience init(from model: OnchainTransactionModel) {
        self.init(
            txid: model.txid,
            received: model.received,
            sent: model.sent,
            fee: model.fee,
            isSelfTransfer: model.isSelfTransfer,
            confirmationHeight: model.confirmationTime?.height,
            confirmationTimestamp: model.confirmationTime?.timestamp,
            confirmationBlockHash: model.confirmationTime?.blockHash,
            currentHeight: model.confirmationTime?.currentHeight,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Update Methods
    
    /// Update this entity from a new model (for upsert logic)
    func update(from model: OnchainTransactionModel) {
        self.received = model.received
        self.sent = model.sent
        self.fee = model.fee
        self.isSelfTransfer = model.isSelfTransfer
        self.confirmationHeight = model.confirmationTime?.height
        // Keep a previously resolved block timestamp when the fresh model
        // lacks one for the same block (the Esplora lookup can fail on a
        // given refresh); drop it only when the block actually changed.
        if let newConfirmation = model.confirmationTime {
            if let newTimestamp = newConfirmation.timestamp {
                self.confirmationTimestamp = newTimestamp
            } else if newConfirmation.blockHash != self.confirmationBlockHash {
                self.confirmationTimestamp = nil
            }
            self.confirmationBlockHash = newConfirmation.blockHash
        } else {
            self.confirmationTimestamp = nil
            self.confirmationBlockHash = nil
        }
        self.currentHeight = model.confirmationTime?.currentHeight
        self.lastUpdated = Date()
    }
    
    // MARK: - Conversion to Model
    
    /// Convert this entity back to OnchainTransactionModel
    var asModel: OnchainTransactionModel {
        let confirmationTime: ConfirmationTime?

        if let height = confirmationHeight {
            confirmationTime = ConfirmationTime(
                height: height,
                timestamp: confirmationTimestamp,
                blockHash: confirmationBlockHash,
                currentHeight: currentHeight
            )
        } else {
            confirmationTime = nil
        }
        
        return OnchainTransactionModel(
            txid: txid,
            received: received,
            sent: sent,
            fee: fee,
            confirmationTime: confirmationTime,
            isSelfTransfer: isSelfTransfer
        )
    }
}

// MARK: - Computed Properties (Mirror OnchainTransactionModel)

extension OnchainTransactionEntity {
    
    /// Net amount change (positive = received, negative = sent)
    var netAmount: Int64 {
        Int64(received) - Int64(sent)
    }
    
    /// Whether this is an incoming transaction
    var isIncoming: Bool {
        netAmount > 0
    }
    
    /// Whether transaction is confirmed (block time may still be resolving)
    var isConfirmed: Bool {
        confirmationHeight != nil
    }
    
    /// Number of confirmations (0 if unconfirmed)
    var confirmations: UInt32 {
        guard let height = confirmationHeight,
              let current = currentHeight else {
            return 0
        }
        
        if current >= height {
            return current - height + 1
        } else {
            return 1
        }
    }
    
    /// Display amount (absolute value of net amount)
    var displayAmount: UInt64 {
        UInt64(abs(netAmount))
    }
    
    /// Short transaction ID for display (first 8 chars)
    var shortTxid: String {
        String(txid.prefix(8))
    }
    
    /// Transaction timestamp (nil if unconfirmed)
    var timestamp: Date? {
        guard let confirmationTimestamp = confirmationTimestamp else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(confirmationTimestamp))
    }
}
