//
//  FeeSummaryViewModel.swift
//  Arké
//
//  Created by Christoph on 1/11/26.
//

import Foundation
import SwiftUI
import SwiftData
import ArkeUI

@MainActor
@Observable
final class FeeSummaryViewModel {
    private let walletManager: WalletManager
    
    var statistics: FeeStatistics?
    var isLoading = false
    var errorMessage: String?
    
    init(walletManager: WalletManager) {
        self.walletManager = walletManager
    }
    
    // MARK: - Public Methods
    
    func loadStatistics() async {
        isLoading = true
        errorMessage = nil
        
        let transactions = walletManager.transactions
        let modelContext = walletManager.modelContext
        
        statistics = calculateStatistics(from: transactions, modelContext: modelContext)
        
        isLoading = false
    }
    
    // MARK: - Calculation
    
    func calculateStatistics(from transactions: [TransactionModel], modelContext: ModelContext?) -> FeeStatistics {
        guard !transactions.isEmpty else {
            return .empty
        }
        
        // Filter out child transactions (ones linked to parent movements)
        // Their fees will be included via parent's totalFeesIncludingLinked()
        let filteredTransactions = transactions.filter { $0.parentTxid == nil }
        
        guard !filteredTransactions.isEmpty else {
            return .empty
        }
        
        // Classify all transactions
        var sendTransactions: [TransactionModel] = []
        var receiveTransactions: [TransactionModel] = []
        var internalTransactions: [TransactionModel] = []
        
        print("=== Fee Statistics Debug ===")
        print("Total transactions (before filter): \(transactions.count)")
        print("Total transactions (after filtering children): \(filteredTransactions.count)")
        
        for tx in filteredTransactions {
            let classification = classifyTransaction(tx)
            
            // Debug log for each transaction
            print("""
            TX ID: \(tx.txid)
            Amount: \(tx.amount)
            TotalFees: \(tx.totalFees)
            Category: \(tx.category?.rawValue ?? "nil")
            SubsystemKind: \(tx.subsystemKind ?? "nil")
            OffchainFee: \(tx.fees ?? 0)
            OnchainFee: \(tx.onchainFeeSat ?? 0)
            ExitedVtxoIds: \(tx.exitedVtxoIds.isEmpty ? "none" : "\(tx.exitedVtxoIds.count) vtxos")
            Classification: \(classification)
            ---
            """)
            
            switch classification {
            case .send:
                sendTransactions.append(tx)
            case .receive:
                receiveTransactions.append(tx)
            case .internal:
                internalTransactions.append(tx)
            }
        }
        
        /*
        // Calculate statistics for each type
        print("\n=== Transaction Classification Summary ===")
        print("Send transactions: \(sendTransactions.count)")
        print("Receive transactions: \(receiveTransactions.count)")
        print("Internal transactions: \(internalTransactions.count)")
         */
        
        let sendStats = calculateTypeStats(for: sendTransactions, includeInVolume: true, modelContext: modelContext)
        let receiveStats = calculateTypeStats(for: receiveTransactions, includeInVolume: true, modelContext: modelContext)
        let internalStats = calculateTypeStats(for: internalTransactions, includeInVolume: true, modelContext: modelContext)
        
        /*
        print("\n=== Internal Stats Breakdown ===")
        print("Internal total fees: \(internalStats.totalFees)")
        print("Category breakdown:")
        for (category, stats) in internalStats.categoryBreakdown {
            print("  \(category.rawValue): count=\(stats.count), fees=\(stats.fees)")
        }
        */
        
        // let refreshFees = internalStats.categoryBreakdown[.refresh]?.fees ?? 0
        // let boardingFees = internalStats.categoryBreakdown[.boarding]?.fees ?? 0
        // let offboardingFees = internalStats.categoryBreakdown[.offboarding]?.fees ?? 0
        // let exitFees = internalStats.categoryBreakdown[.exit]?.fees ?? 0
        // let sumOfDisplayedCategories = refreshFees + boardingFees + offboardingFees + exitFees
        
        /*
        print("Sum of displayed categories: \(sumOfDisplayedCategories)")
        print("Difference: \(internalStats.totalFees - sumOfDisplayedCategories)")
        print("===========================\n")
        */
        
        // Calculate totals
        let totalFees = sendStats.totalFees + receiveStats.totalFees + internalStats.totalFees
        let totalCount = transactions.count
        let totalVolume = sendStats.volume + internalStats.volume
        
        // Calculate global offchain/onchain breakdown
        var totalOffchainFees = 0
        var totalOnchainFees = 0
        
        for tx in transactions {
            totalOffchainFees += tx.fees ?? 0
            totalOnchainFees += tx.onchainFeeSat ?? 0
        }
        
        // Calculate average fee percentage
        let averageFeePercentage: Double = totalVolume > 0 
            ? (Double(totalFees) / Double(totalVolume)) * 100.0 
            : 0.0
        
        // Calculate failed transaction stats
        let failedStats = calculateFailedStats(from: transactions)
        
        // Calculate efficiency metrics
        let efficiencyMetrics = calculateEfficiencyMetrics(from: transactions)
        
        return FeeStatistics(
            totalFeesAllTime: totalFees,
            totalTransactionCount: totalCount,
            totalVolume: totalVolume,
            averageFeePercentage: averageFeePercentage,
            sendStatistics: sendStats,
            receiveStatistics: receiveStats,
            internalStatistics: internalStats,
            offchainFees: totalOffchainFees,
            onchainFees: totalOnchainFees,
            failedTransactionStats: failedStats,
            efficiencyMetrics: efficiencyMetrics
        )
    }
    
    // MARK: - Transaction Classification
    
    private func classifyTransaction(_ tx: TransactionModel) -> TransactionClassification {
        // Internal transfers: boarding, offboarding, refresh, exit
        if tx.isInternalTransfer {
            return .internal
        }
        
        // Receives
        if tx.type == .received {
            return .receive
        }
        
        // Everything else is a send
        return .send
    }
    
    // MARK: - Type Statistics
    
    private func calculateTypeStats(for transactions: [TransactionModel], includeInVolume: Bool, modelContext: ModelContext?) -> TransactionTypeStats {
        guard !transactions.isEmpty else {
            return .empty
        }
        
        let count = transactions.count
        var totalVolume = 0
        var totalFees = 0
        
        // Group by category
        var categoryGroups: [MovementCategory: [TransactionModel]] = [:]
        
        // Network fee breakdown
        var arkFees = 0
        var lightningFees = 0
        var bitcoinFees = 0
        
        var arkCount = 0
        var lightningCount = 0
        var bitcoinCount = 0
        
        for tx in transactions {
            if includeInVolume {
                totalVolume += tx.amount
            }
            
            // Use totalFeesIncludingLinked for transactions that might have linked children (exits)
            let txFees = tx.totalFeesIncludingLinked(modelContext: modelContext)
            totalFees += txFees
            
            // Calculate network-specific fees including linked transactions
            // For exits with linked onchain transactions, this will include the child's onchain fees
            let offchainFee = tx.fees ?? 0
            var onchainFee = tx.onchainFeeSat ?? 0
            
            // For exits, add linked onchain transaction fees to the onchain
            // fee total (userPaidOnchainFeeSat excludes third-party bumps)
            if tx.subsystemName == "bark.exit", let childTxids = tx.childTxids, !childTxids.isEmpty, let modelContext = modelContext {
                for childTxid in childTxids {
                    let descriptor = FetchDescriptor<PersistentTransaction>(
                        predicate: #Predicate { $0.txid == childTxid }
                    )
                    if let childTx = try? modelContext.fetch(descriptor).first,
                       let childFee = childTx.userPaidOnchainFeeSat {
                        onchainFee += childFee
                    }
                }
            }
            
            // Categorize fees by network based on transaction category
            if let category = tx.category {
                switch category {
                case .lightningSend, .lightningReceive:
                    lightningFees += offchainFee
                    bitcoinFees += onchainFee  // Any onchain component goes to Bitcoin
                    lightningCount += 1
                case .onchainSend, .boarding, .offboarding, .exit, .onchainTransaction:
                    bitcoinFees += (offchainFee + onchainFee)  // Primarily Bitcoin network
                    bitcoinCount += 1
                case .offchainTransfer, .refresh:
                    arkFees += offchainFee  // Ark network
                    bitcoinFees += onchainFee  // Any onchain component
                    arkCount += 1
                case .unknown:
                    // Default to Ark for offchain, Bitcoin for onchain
                    arkFees += offchainFee
                    bitcoinFees += onchainFee
                    arkCount += 1  // Count unknown as Ark by default
                }
            } else {
                // No category - default to Ark for offchain, Bitcoin for onchain
                arkFees += offchainFee
                bitcoinFees += onchainFee
                arkCount += 1
            }
            
            // Group by category if available
            if let category = tx.category {
                categoryGroups[category, default: []].append(tx)
            }
        }
        
        // Calculate category breakdown
        var categoryBreakdown: [MovementCategory: CategoryStats] = [:]
        for (category, txs) in categoryGroups {
            let stats = calculateCategoryStats(for: txs, includeInVolume: includeInVolume, modelContext: modelContext)
            categoryBreakdown[category] = stats
        }
        
        // Calculate average fee per transaction
        let averageFee = count > 0 ? totalFees / count : 0
        
        // Calculate fee as percentage of volume
        let feePercentage: Double? = (totalVolume > 0 && includeInVolume) 
            ? (Double(totalFees) / Double(totalVolume)) * 100.0 
            : nil
        
        let networkBreakdown = NetworkFeeBreakdown(
            arkFees: arkFees,
            lightningFees: lightningFees,
            bitcoinFees: bitcoinFees,
            arkCount: arkCount,
            lightningCount: lightningCount,
            bitcoinCount: bitcoinCount
        )
        
        return TransactionTypeStats(
            count: count,
            volume: totalVolume,
            totalFees: totalFees,
            averageFeePerTransaction: averageFee,
            feeAsPercentOfVolume: feePercentage,
            categoryBreakdown: categoryBreakdown,
            networkBreakdown: networkBreakdown
        )
    }
    
    // MARK: - Category Statistics
    
    private func calculateCategoryStats(for transactions: [TransactionModel], includeInVolume: Bool, modelContext: ModelContext?) -> CategoryStats {
        var volume = 0
        var totalFees = 0
        var offchainFees = 0
        var onchainFees = 0
        
        for tx in transactions {
            if includeInVolume {
                volume += tx.amount
            }
            
            // Use totalFeesIncludingLinked for exits that may have linked onchain transactions
            let txTotalFees = tx.totalFeesIncludingLinked(modelContext: modelContext)
            totalFees += txTotalFees
            
            // Offchain fees are always direct
            offchainFees += tx.fees ?? 0
            
            // Onchain fees include linked child transaction fees for exits
            // (userPaidOnchainFeeSat excludes third-party bumps)
            var txOnchainFees = tx.onchainFeeSat ?? 0
            if tx.subsystemName == "bark.exit", let childTxids = tx.childTxids, !childTxids.isEmpty, let modelContext = modelContext {
                for childTxid in childTxids {
                    let descriptor = FetchDescriptor<PersistentTransaction>(
                        predicate: #Predicate { $0.txid == childTxid }
                    )
                    if let childTx = try? modelContext.fetch(descriptor).first,
                       let childFee = childTx.userPaidOnchainFeeSat {
                        txOnchainFees += childFee
                    }
                }
            }
            onchainFees += txOnchainFees
        }
        
        return CategoryStats(
            count: transactions.count,
            volume: volume,
            fees: totalFees,
            offchainFees: offchainFees,
            onchainFees: onchainFees
        )
    }
    
    // MARK: - Failed Transaction Statistics
    
    private func calculateFailedStats(from transactions: [TransactionModel]) -> FailedTransactionStats? {
        let failedTransactions = transactions.filter { tx in
            // Check if status is failed
            tx.status == .failed
        }
        
        guard !failedTransactions.isEmpty else {
            return nil
        }
        
        var feesLost = 0
        for tx in failedTransactions {
            feesLost += tx.totalFees
        }
        
        // Only return if there are actually fees lost
        guard feesLost > 0 else {
            return nil
        }
        
        return FailedTransactionStats(
            count: failedTransactions.count,
            feesLost: feesLost
        )
    }
    
    // MARK: - Efficiency Metrics
    
    private func calculateEfficiencyMetrics(from transactions: [TransactionModel]) -> EfficiencyMetrics {
        // Get all non-zero fees
        let fees = transactions.map { $0.totalFees }.filter { $0 > 0 }
        
        guard !fees.isEmpty else {
            return .empty
        }
        
        let maxFee = fees.max() ?? 0
        let minFee = fees.min() ?? 0
        let averageFee = fees.reduce(0, +) / fees.count
        
        // Calculate median
        let sortedFees = fees.sorted()
        let medianFee: Int
        if sortedFees.count % 2 == 0 {
            let mid = sortedFees.count / 2
            medianFee = (sortedFees[mid - 1] + sortedFees[mid]) / 2
        } else {
            medianFee = sortedFees[sortedFees.count / 2]
        }
        
        return EfficiencyMetrics(
            maxSingleFee: maxFee,
            minSingleFee: minFee,
            averageFee: averageFee,
            medianFee: medianFee
        )
    }
}
