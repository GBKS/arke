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
    
    /// Get transaction chain for UI display.
    /// Includes transactions from both current state and history. Each txid
    /// keeps its position from when it first appeared (chain order), but its
    /// LATEST status: history is oldest-first and a transaction shows up
    /// repeatedly as it progresses (VerifyInputs → ... → Confirmed), so once
    /// an exit moves past Processing only the newest occurrence is accurate.
    var transactionChain: [ExitTransaction] {
        var order: [String] = []
        var latestByTxid: [String: ExitTransaction] = [:]

        func absorb(_ transactions: [ExitTransaction]) {
            for tx in transactions {
                if latestByTxid[tx.txid] == nil {
                    order.append(tx.txid)
                }
                latestByTxid[tx.txid] = tx
            }
        }

        // Oldest first; the current state (if Processing) is freshest and wins
        for historyState in parsedHistory {
            if case .processing(let data) = historyState {
                absorb(data.transactions)
            }
        }
        if case .processing(let data) = parsedState {
            absorb(data.transactions)
        }

        let transactions = order.compactMap { latestByTxid[$0] }
        logger.debug("🔗 Transaction chain for \(self.vtxoId.prefix(16))...: \(transactions.count) transactions")
        return transactions
    }
}
