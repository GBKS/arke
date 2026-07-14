//
//  ServerCard.swift
//  Arké
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct ServerCard: View {
    let comparison: ServerComparison
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isExpanded = false
    
    private var isEnabled: Bool {
        comparison.server.enabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - tappable to select
            Button(action: onSelect) {
                ServerCardHeader(
                    comparison: comparison,
                    isEnabled: isEnabled,
                    isExpanded: isExpanded,
                    onToggleExpand: { isExpanded.toggle() }
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            
            // Expandable content
            if isExpanded && isEnabled {
                ServerCardExpandedContent(comparison: comparison)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.Arke.gold : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
        .buttonStyle(.plain)
    }
}

// MARK: - ServerCardHeader

private struct ServerCardHeader: View {
    let comparison: ServerComparison
    let isEnabled: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            // Server logo
            Image(comparison.server.logoImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isEnabled ? 1.0 : 0.75)
            
            ServerCardTitleSection(
                serverName: comparison.server.name,
                websiteURL: comparison.server.websiteURL,
                isEnabled: isEnabled
            )
            
            Spacer()
            
            ServerCardCostSection(
                comparison: comparison,
                isEnabled: isEnabled
            )
            
            // Expand/collapse indicator
            Button(action: onToggleExpand) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
}

// MARK: - ServerCardTitleSection

private struct ServerCardTitleSection: View {
    let serverName: String
    let websiteURL: URL
    let isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(serverName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                
                if !isEnabled {
                    Text("onboarding_server_unavailable")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.1))
                        )
                }
            }
            
            Link(destination: websiteURL) {
                Text(websiteURL.absoluteString)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .underline()
            }
            .disabled(!isEnabled)
        }
    }
}

// MARK: - ServerCardCostSection

private struct ServerCardCostSection: View {
    let comparison: ServerComparison
    let isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text("~\(BitcoinFormatter.shared.formatAmount(comparison.estimate.totalMonthly))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.Arke.gold)
                    .contentTransition(.numericText())
                
                Text("onboarding_cost_per_month")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((comparison.estimate.effectiveRate(for: comparison.profile.monthlyVolume) / 100).formatted(.percent.precision(.fractionLength(2))))
                    .font(.body)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                
                Text("onboarding_cost_per_transaction")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .opacity(isEnabled ? 1.0 : 0.75)
        .animation(.smooth(duration: 0.4), value: comparison.estimate.totalMonthly)
        .animation(.smooth(duration: 0.4), value: comparison.estimate.effectiveRate(for: comparison.profile.monthlyVolume))
    }
}

// MARK: - ServerCardExpandedContent

private struct ServerCardExpandedContent: View {
    let comparison: ServerComparison
    
    var body: some View {
        Group {
            Divider()
                .background(.white.opacity(0.2))
                .transition(.opacity)
            
            // Fee breakdown
            ServerCardFeeBreakdown(comparison: comparison)
            
            // Server specs
            Divider()
                .background(.white.opacity(0.2))
                .transition(.opacity)
            
            ServerCardSpecs(server: comparison.server)
        }
    }
}

// MARK: - ServerCardFeeBreakdown

private struct ServerCardFeeBreakdown: View {
    let comparison: ServerComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ServerFeeRow(
                label: "Direct payments",
                count: comparison.profile.onArkPayments,
                amount: comparison.estimate.onArkFees
            )
            
            ServerFeeRow(
                label: "Lightning payments",
                count: comparison.profile.lightningPayments,
                amount: comparison.estimate.lightningFees
            )
            
            ServerFeeRow(
                label: "Refreshes",
                count: comparison.profile.refreshesPerMonth,
                amount: comparison.estimate.refreshFees
            )
        }
        .transition(.opacity)
    }
}

// MARK: - ServerCardSpecs

private struct ServerCardSpecs: View {
    let server: ServerFeeConfig
    
    private var annualRateString: String? {
        switch server.refreshFeeModel {
        case .percentage(let annualRate):
            return "\(String(format: "%.1f", annualRate * 100))%"
        case .tiered(let annualRate, _):
            return "\(String(format: "%.1f", annualRate * 100))%"
        case .absolute:
            return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rate = annualRateString {
                ServerSpec(
                    label: "Annual rate",
                    value: rate
                )
            }
            
            ServerSpec(
                label: "Refresh needed every",
                value: "\(server.expiryDays) days"
            )
            
            ServerSpec(
                label: "Lightning payment",
                value: "\(server.lightningBaseFee) sat + \(server.lightningPPM) ppm"
            )
            
            if let freeWindow = server.freeRefreshWindowDays {
                ServerSpec(
                    label: "Free refresh window",
                    value: "\(freeWindow) days before expiry"
                )
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
