//
//  FeeStatistics.swift
//  Arké
//
//  Created by Christoph on 1/11/26.
//

import Foundation
import ArkeUI

// MARK: - Main Statistics Container

/// Complete fee statistics for all transactions
struct FeeStatistics {
    let totalFeesAllTime: Int
    let totalTransactionCount: Int
    let totalVolume: Int
    let averageFeePercentage: Double
    
    let sendStatistics: TransactionTypeStats
    let receiveStatistics: TransactionTypeStats
    let internalStatistics: TransactionTypeStats
    
    let offchainFees: Int
    let onchainFees: Int
    
    let failedTransactionStats: FailedTransactionStats?
    
    let efficiencyMetrics: EfficiencyMetrics
    
    /// Check if there are any transactions
    var hasTransactions: Bool {
        totalTransactionCount > 0
    }
    
    /// Check if any fees have been paid
    var hasFeesBeenPaid: Bool {
        totalFeesAllTime > 0
    }
}

// MARK: - Transaction Type Statistics

/// Statistics for a specific transaction type (send, receive, or internal)
struct TransactionTypeStats {
    let count: Int
    let volume: Int
    let totalFees: Int
    let averageFeePerTransaction: Int
    let feeAsPercentOfVolume: Double?
    let categoryBreakdown: [MovementCategory: CategoryStats]
    let networkBreakdown: NetworkFeeBreakdown
    
    /// Check if there are any transactions of this type
    var hasTransactions: Bool {
        count > 0
    }
    
    /// Check if any fees were paid for this type
    var hasFees: Bool {
        totalFees > 0
    }
}

// MARK: - Network Fee Breakdown

/// Breakdown of fees by network type
struct NetworkFeeBreakdown {
    let arkFees: Int        // Offchain fees (Ark network)
    let lightningFees: Int  // Lightning-specific fees
    let bitcoinFees: Int    // Onchain fees (Bitcoin network)
    
    let arkCount: Int       // Number of Ark transactions
    let lightningCount: Int // Number of Lightning transactions
    let bitcoinCount: Int   // Number of Bitcoin transactions
    
    var total: Int {
        arkFees + lightningFees + bitcoinFees
    }
    
    static var empty: NetworkFeeBreakdown {
        NetworkFeeBreakdown(
            arkFees: 0,
            lightningFees: 0,
            bitcoinFees: 0,
            arkCount: 0,
            lightningCount: 0,
            bitcoinCount: 0
        )
    }
}

// MARK: - Category Statistics

/// Statistics for a specific movement category
struct CategoryStats {
    let count: Int
    let volume: Int
    let fees: Int
    let offchainFees: Int
    let onchainFees: Int
    
    /// Check if this category has any transactions
    var hasTransactions: Bool {
        count > 0
    }
    
    /// Check if this category has any fees
    var hasFees: Bool {
        fees > 0
    }
}

// MARK: - Failed Transaction Statistics

/// Statistics about failed transactions and their fee impact
struct FailedTransactionStats {
    let count: Int
    let feesLost: Int
    
    /// Check if there are any failed transactions
    var hasFailedTransactions: Bool {
        count > 0
    }
    
    /// Check if any fees were lost to failures
    var hasFeesLost: Bool {
        feesLost > 0
    }
}

// MARK: - Efficiency Metrics

/// Metrics about fee efficiency
struct EfficiencyMetrics {
    let maxSingleFee: Int
    let minSingleFee: Int  // Excluding zero-fee transactions
    let averageFee: Int
    let medianFee: Int
    
    /// Check if we have fee data
    var hasData: Bool {
        maxSingleFee > 0
    }
}

// MARK: - Transaction Classification

/// Classification of transactions for fee analysis
enum TransactionClassification {
    case send        // User sending to external party
    case receive     // User receiving from external party
    case `internal`  // Internal transfers (boarding, offboarding, etc.)
    
    var displayName: String {
        switch self {
        case .send: return "Sends"
        case .receive: return "Receives"
        case .internal: return "Internal Moves"
        }
    }
    
    var description: String {
        switch self {
        case .send:
            return "Outgoing payments to other parties"
        case .receive:
            return "Incoming payments from other parties"
        case .internal:
            return "Moves between your own balances"
        }
    }
}

// MARK: - Empty Statistics

extension FeeStatistics {
    /// Create empty statistics for when there are no transactions
    static var empty: FeeStatistics {
        FeeStatistics(
            totalFeesAllTime: 0,
            totalTransactionCount: 0,
            totalVolume: 0,
            averageFeePercentage: 0,
            sendStatistics: .empty,
            receiveStatistics: .empty,
            internalStatistics: .empty,
            offchainFees: 0,
            onchainFees: 0,
            failedTransactionStats: nil,
            efficiencyMetrics: .empty
        )
    }
}

extension TransactionTypeStats {
    static var empty: TransactionTypeStats {
        TransactionTypeStats(
            count: 0,
            volume: 0,
            totalFees: 0,
            averageFeePerTransaction: 0,
            feeAsPercentOfVolume: nil,
            categoryBreakdown: [:],
            networkBreakdown: .empty
        )
    }
}

extension EfficiencyMetrics {
    static var empty: EfficiencyMetrics {
        EfficiencyMetrics(
            maxSingleFee: 0,
            minSingleFee: 0,
            averageFee: 0,
            medianFee: 0
        )
    }
}
