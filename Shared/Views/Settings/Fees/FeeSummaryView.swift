//
//  FeeSummaryView.swift
//  Arké
//
//  Created by Christoph on 1/11/26.
//

import SwiftUI
import ArkeUI

struct FeeSummaryView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var statistics: FeeStatistics = .empty
    
    var body: some View {
        statisticsView(statistics: statistics)
            .task(id: walletManager.transactions.count) {
                loadStatistics()
            }
            //.navigationTitle(L10n.activityFeeSummary)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .refreshable {
                loadStatistics()
            }
    }
    
    private func loadStatistics() {
        let viewModel = FeeSummaryViewModel(walletManager: walletManager)
        statistics = viewModel.calculateStatistics(
            from: walletManager.transactions,
            modelContext: walletManager.modelContext
        )
    }
    
    // MARK: - Statistics View
    
    @ViewBuilder
    private func statisticsView(statistics: FeeStatistics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Large serif title
                Text(L10n.activityFeeSummary)
                    .font(.system(.largeTitle, design: .serif))
                    .padding(.horizontal)
                
                // Overview Section
                overviewCards(statistics: statistics)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Overview Cards
    
    @ViewBuilder
    private func overviewCards(statistics: FeeStatistics) -> some View {
        VStack(spacing: 40) {
            // Card 1: Send Fee Summary
            sendFeeSummaryCard(statistics: statistics)
            
            // Card 2: Maintenance Fees (Internal Transfers)
            maintenanceFeesCard(statistics: statistics)
            
            // Card 3: Receive Fees
            // receiveFeesCard(statistics: statistics)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helper Methods
    
    private func formatAmountOrDash(_ amount: Int, hasData: Bool) -> String {
        guard hasData else { return "—" }
        return BitcoinFormatter.shared.formatAmount(amount)
    }
    
    // MARK: - Send Fee Summary Card
    
    private func sendFeeSummaryCard(statistics: FeeStatistics) -> some View {
        let sendStats = statistics.sendStatistics
        let hasData = statistics.hasTransactions
        let percentageString: String
        
        if !hasData {
            percentageString = "—"
        } else if let feePercentage = sendStats.feeAsPercentOfVolume {
            percentageString = String(format: "%.2f%%", feePercentage)
        } else {
            percentageString = "—"
        }
        
        let keyMetrics: [FeeDetailCardView.KeyMetric] = [
            .init(label: L10n.feeTransactions, value: "\(sendStats.count)"),
            .init(label: L10n.activityFeesPaid, value: formatAmountOrDash(sendStats.totalFees, hasData: hasData)),
            .init(label: String(localized: "fee_amount_sent", defaultValue: "Amount Sent"), value: formatAmountOrDash(sendStats.volume, hasData: hasData))
        ]
        
        let networkBreakdown = sendStats.networkBreakdown
        let networkSection = FeeDetailCardView.Section(
            title: String(localized: "fee_by_network", defaultValue: "Fees by Network"),
            items: [
                .init(
                    label: networkBreakdown.arkCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkArk, networkBreakdown.arkCount)
                        : L10n.networkArk,
                    value: formatAmountOrDash(networkBreakdown.arkFees, hasData: hasData)
                ),
                .init(
                    label: networkBreakdown.lightningCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkLightning, networkBreakdown.lightningCount)
                        : L10n.networkLightning,
                    value: formatAmountOrDash(networkBreakdown.lightningFees, hasData: hasData)
                ),
                .init(
                    label: networkBreakdown.bitcoinCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkBitcoin, networkBreakdown.bitcoinCount)
                        : L10n.networkBitcoin,
                    value: formatAmountOrDash(networkBreakdown.bitcoinFees, hasData: hasData)
                )
            ]
        )
        
        return FeeDetailCardView(
            title: String(localized: "fee_average_send", defaultValue: "Average Send Fee"),
            subtitle: nil,
            prominentMetric: percentageString,
            prominentMetricAccessibilityLabel: String(format: String(localized: "accessibility_average_fee_percentage", defaultValue: "Average fee as percentage of volume: %@"), percentageString),
            keyMetrics: keyMetrics,
            sections: [networkSection],
            iconSymbol: "arrow.up",
            iconBackgroundImage: "card"
        )
    }
    
    // MARK: - Maintenance Fees Card
    
    private func maintenanceFeesCard(statistics: FeeStatistics) -> some View {
        let internalStats = statistics.internalStatistics
        let categoryBreakdown = internalStats.categoryBreakdown
        let hasData = statistics.hasTransactions
        
        // Extract specific categories for maintenance
        let refreshStats = categoryBreakdown[.refresh]
        let boardingStats = categoryBreakdown[.boarding]
        
        // Combine traditional offboarding and collaborative offboarding (onchainSend with bark.offboard)
        // Both represent "Move to Savings" to the user
        let traditionalOffboarding = categoryBreakdown[.offboarding]
        let collaborativeOffboarding = categoryBreakdown[.onchainSend]
        let combinedOffboardingFees = (traditionalOffboarding?.fees ?? 0) + (collaborativeOffboarding?.fees ?? 0)
        let combinedOffboardingCount = (traditionalOffboarding?.count ?? 0) + (collaborativeOffboarding?.count ?? 0)
        
        let exitStats = categoryBreakdown[.exit]
        
        // Exit fees now include linked onchain transaction fees via totalFeesIncludingLinked()
        // No need to add onchainStats separately (would cause double-counting)
        let recoveryFees = exitStats?.fees ?? 0
        let recoveryCount = exitStats?.count ?? 0
        
        let keyMetrics: [FeeDetailCardView.KeyMetric] = [
            .init(
                label: refreshStats?.count ?? 0 > 0 
                    ? String(format: String(localized: "maintenance_refresh_with_count", defaultValue: "Refresh (%lld)"), refreshStats!.count)
                    : String(localized: "maintenance_refresh", defaultValue: "Refresh"),
                value: formatAmountOrDash(refreshStats?.fees ?? 0, hasData: hasData)
            ),
            .init(
                label: boardingStats?.count ?? 0 > 0 
                    ? String(format: String(localized: "maintenance_boarding_with_count", defaultValue: "Move to Payments (%lld)"), boardingStats!.count)
                    : String(localized: "maintenance_boarding", defaultValue: "Move to Payments"),
                value: formatAmountOrDash(boardingStats?.fees ?? 0, hasData: hasData)
            ),
            .init(
                label: combinedOffboardingCount > 0 
                    ? String(format: String(localized: "maintenance_offboarding_with_count", defaultValue: "Move to Savings (%lld)"), combinedOffboardingCount)
                    : String(localized: "maintenance_offboarding", defaultValue: "Move to Savings"),
                value: formatAmountOrDash(combinedOffboardingFees, hasData: hasData)
            ),
            .init(
                label: recoveryCount > 0 
                    ? String(format: String(localized: "maintenance_exit_with_count", defaultValue: "Force Move to Savings (%lld)"), recoveryCount)
                    : String(localized: "maintenance_exit", defaultValue: "Force Move to Savings"),
                value: formatAmountOrDash(recoveryFees, hasData: hasData)
            )
        ]
        
        return FeeDetailCardView(
            title: String(localized: "fee_maintenance", defaultValue: "Maintenance Fees"),
            subtitle: String(localized: "fee_maintenance_subtitle", defaultValue: "Your payments balance requires occasional refreshes and transfers."),
            prominentMetric: formatAmountOrDash(internalStats.totalFees, hasData: hasData),
            prominentMetricAccessibilityLabel: nil,
            keyMetrics: keyMetrics,
            sections: [],
            iconSymbol: "repeat",
            iconBackgroundImage: "card"
        )
    }
    
    // MARK: - Receive Fees Card
    
    private func receiveFeesCard(statistics: FeeStatistics) -> some View {
        let receiveStats = statistics.receiveStatistics
        let hasData = statistics.hasTransactions
        let percentageString: String
        
        if !hasData {
            percentageString = "—"
        } else if let feePercentage = receiveStats.feeAsPercentOfVolume {
            percentageString = String(format: "%.2f%%", feePercentage)
        } else {
            percentageString = "—"
        }
        
        let keyMetrics: [FeeDetailCardView.KeyMetric] = [
            .init(label: L10n.feeTransactions, value: "\(receiveStats.count)"),
            .init(label: L10n.activityFeesPaid, value: formatAmountOrDash(receiveStats.totalFees, hasData: hasData)),
            .init(label: String(localized: "fee_amount_received", defaultValue: "Amount Received"), value: formatAmountOrDash(receiveStats.volume, hasData: hasData))
        ]
        
        let networkBreakdown = receiveStats.networkBreakdown
        let networkSection = FeeDetailCardView.Section(
            title: String(localized: "fee_network_breakdown", defaultValue: "Network Breakdown"),
            items: [
                .init(
                    label: networkBreakdown.arkCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkArk, networkBreakdown.arkCount)
                        : L10n.networkArk,
                    value: formatAmountOrDash(networkBreakdown.arkFees, hasData: hasData)
                ),
                .init(
                    label: networkBreakdown.lightningCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkLightning, networkBreakdown.lightningCount)
                        : L10n.networkLightning,
                    value: formatAmountOrDash(networkBreakdown.lightningFees, hasData: hasData)
                ),
                .init(
                    label: networkBreakdown.bitcoinCount > 0 
                        ? String(format: L10n.feeNetworkWithCount, L10n.networkBitcoin, networkBreakdown.bitcoinCount)
                        : L10n.networkBitcoin,
                    value: formatAmountOrDash(networkBreakdown.bitcoinFees, hasData: hasData)
                )
            ]
        )
        
        return FeeDetailCardView(
            title: String(localized: "fee_average_receive", defaultValue: "Average Receive Fee"),
            subtitle: nil,
            prominentMetric: percentageString,
            prominentMetricAccessibilityLabel: String(format: String(localized: "accessibility_average_fee_percentage", defaultValue: "Average fee as percentage of volume: %@"), percentageString),
            keyMetrics: keyMetrics,
            sections: [networkSection]
        )
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "activity_empty_title", defaultValue: "No Transactions Yet"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(String(localized: "activity_fee_stats_empty", defaultValue: "Fee statistics will appear here once you start making transactions"))
        }
    }
    
    // MARK: - Loading View
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel(String(localized: "accessibility_loading_fee_stats", defaultValue: "Loading fee statistics"))
            Text(String(localized: "status_loading_fee_stats", defaultValue: "Loading fee statistics..."))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Error View
    
    @ViewBuilder
    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "error_load_statistics", defaultValue: "Unable to Load Statistics"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.buttonTryAgain) {
                loadStatistics()
            }
        }
    }
}
