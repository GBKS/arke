//
//  TagsGraph.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI
import Charts

struct TagsGraph: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var tagStatistics: [TagStatistic] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tag Transaction Amounts")
                .font(.title2)
                .fontWeight(.semibold)
            
            if tagStatistics.isEmpty {
                emptyStateView
            } else {
                chartView
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .task {
            await loadTagStatistics()
        }
        .refreshable {
            await loadTagStatistics()
        }
    }
    
    // MARK: - Chart View
    
    @ViewBuilder
    private var chartView: some View {
        Chart(tagStatistics, id: \.tagId) { statistic in
            BarMark(
                x: .value("Tag", statistic.tagName),
                y: .value("Total Amount", statistic.totalAmount)
            )
            .foregroundStyle(colorForTag(statistic.tagName, amount: statistic.totalAmount))
            .cornerRadius(4)
        }
        .frame(height: 300)
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel(orientation: .vertical)
                    .font(.caption)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(BitcoinFormatter.formatAmount(intValue))
                            .font(.caption)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .symbolRenderingMode(.hierarchical)
            
            Text("No Transaction Data")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Create some tags and assign them to transactions to see the chart")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func loadTagStatistics() async {
        do {
            tagStatistics = try await walletManager.getTagStatistics()
                .filter { $0.transactionCount > 0 } // Only show tags with transactions
                .sorted { abs($0.totalAmount) > abs($1.totalAmount) } // Sort by absolute amount descending
        } catch {
            print("❌ Failed to load tag statistics: \(error)")
            tagStatistics = []
        }
    }
    
    private func colorForTag(_ tagName: String, amount: Int) -> Color {
        // Find the matching tag to get its color
        if let tag = walletManager.activeTags.first(where: { $0.name == tagName }) {
            // Apply color intensity based on whether amount is positive or negative
            let baseColor = tag.color
            return amount >= 0 ? baseColor : baseColor.opacity(0.7)
        }
        
        // Fallback to a default color scheme based on tag name
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .pink, .teal, .indigo]
        let index = abs(tagName.hashValue) % colors.count
        let baseColor = colors[index]
        return amount >= 0 ? baseColor : baseColor.opacity(0.7)
    }
}

// MARK: - Preview

#Preview("Tags Graph with Data") {
    TagsGraph()
        .environment(WalletManager(useMock: true))
        .frame(width: 600, height: 400)
}

#Preview("Tags Graph Empty") {
    TagsGraph()
        .environment(WalletManager(useMock: false))
        .frame(width: 600, height: 400)
}