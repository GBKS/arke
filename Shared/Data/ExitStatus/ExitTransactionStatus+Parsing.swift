//
//  ExitTransactionStatus+Parsing.swift
//  Arké
//
//  Extensions for parsing ExitTransactionStatus
//  Created by Christoph on 4/27/26.
//

import Foundation
import Bark
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitTransactionStatus")

public extension ExitTransactionStatus {
    
    /// Parse the current state into structured data
    var parsedState: ParsedExitState? {
        ExitStatusParser.parseState(state)
    }
    
    /// Parse history into structured data
    var parsedHistory: [ParsedExitState] {
        guard let history = history else { return [] }
        return ExitStatusParser.parseHistory(history)
    }
    
    /// Extract all transaction IDs from state and history
    var allTransactionIds: [String] {
        ExitStatusParser.extractAllTransactionIds(from: self)
    }
    
    /// Get all confirmed transaction IDs with their block references
    var confirmedTransactions: [(txid: String, block: ArkeBlockRef)] {
        var confirmed: [(txid: String, block: ArkeBlockRef)] = []
        
        // Check current state
        if case .claimed(let data) = parsedState {
            confirmed.append((txid: data.txid, block: data.block))
        }
        
        // Check processing transactions in current state
        if case .processing(let data) = parsedState {
            for tx in data.transactions {
                if case .confirmed(let txData) = tx.status {
                    confirmed.append((txid: tx.txid, block: txData.block))
                }
            }
        }
        
        // Also check history for full timeline
        for historyState in parsedHistory {
            if case .processing(let data) = historyState {
                for tx in data.transactions {
                    if case .confirmed(let txData) = tx.status {
                        let tuple = (txid: tx.txid, block: txData.block)
                        // Avoid duplicates
                        if !confirmed.contains(where: { $0.txid == tuple.txid }) {
                            confirmed.append(tuple)
                        }
                    }
                }
            }
        }
        
        return confirmed
    }
    
    /// Get the current block height from the state
    var currentTipHeight: UInt32? {
        switch parsedState {
        case .start(let data):
            return data.tipHeight
        case .processing(let data):
            return data.tipHeight
        case .awaitingDelta(let data):
            return data.tipHeight
        case .claimable(let data):
            return data.tipHeight
        case .claimInProgress(let data):
            return data.tipHeight
        case .claimed(let data):
            return data.tipHeight
        case .vtxoAlreadySpent(let data):
            return data.tipHeight
        case .unparsed, .none:
            return nil
        }
    }
    
    /// Get the claimable block height if available
    var claimableHeight: UInt32? {
        if case .awaitingDelta(let data) = parsedState {
            return data.claimableHeight
        }
        return nil
    }
    
    /// Get transaction chain for UI display
    /// Includes transactions from both current state and history
    var transactionChain: [ExitTransaction] {
        var transactions: [ExitTransaction] = []
        var seenTxids = Set<String>()
        
        logger.debug("🔗 Building transaction chain for VTXO: \(self.vtxoId)")
        logger.debug("   Current state type: \(String(describing: self.parsedState))")
        logger.debug("   History count: \(self.parsedHistory.count)")
        
        // First, get transactions from current state
        if case .processing(let data) = parsedState {
            logger.debug("   Found \(data.transactions.count) transactions in current state")
            for tx in data.transactions {
                if !seenTxids.contains(tx.txid) {
                    transactions.append(tx)
                    seenTxids.insert(tx.txid)
                    logger.debug("      - Added tx: \(tx.txid.prefix(16))... status: \(String(describing: tx.status))")
                }
            }
        } else {
            logger.debug("   Current state is not Processing, checking history...")
        }
        
        // Also check history for transactions (exits progress through states)
        for (index, historyState) in parsedHistory.enumerated() {
            if case .processing(let data) = historyState {
                logger.debug("   Found \(data.transactions.count) transactions in history[\(index)]")
                for tx in data.transactions {
                    if !seenTxids.contains(tx.txid) {
                        transactions.append(tx)
                        seenTxids.insert(tx.txid)
                        logger.debug("      - Added tx: \(tx.txid.prefix(16))... status: \(String(describing: tx.status))")
                    }
                }
            }
        }
        
        logger.info("🔗 Transaction chain built: \(transactions.count) total transactions")
        return transactions
    }
}
