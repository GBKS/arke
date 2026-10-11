//
//  BalanceRefreshStatusCompact.swift
//  Arke
//
//  Created by Christoph on 4/24/26.
//

import SwiftUI
import ArkeUI

struct BalanceRefreshStatusCompact: View {
    let data: BalanceRefreshData
    let currentTime: Date
    
    private var timeUntilNextRound: String? {
        guard let nextRoundTimestamp = data.nextRoundStartTime else {
            return nil
        }
        
        let currentTimeValue = UInt64(currentTime.timeIntervalSince1970)
        
        guard nextRoundTimestamp > currentTimeValue else {
            return nil  // Round has passed
        }
        
        let secondsUntilRound = Int(nextRoundTimestamp - currentTimeValue)
        return formatTimeInterval(secondsUntilRound)
    }
    
    private func formatTimeInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "< 1m" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(seconds)) ?? "< 1m"
    }
    
    var body: some View {
        Group {
            if data.isLoading {
                loadingView
            } else {
                contentView
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onRefresh = data.onRefresh {
                Task {
                    await onRefresh()
                }
            }
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.15))
                .cornerRadius(6)
            
            Text(String(localized: "progress_loading", defaultValue: "Loading..."))
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            
            Spacer()
            
            ProgressView()
                .controlSize(.small)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 20)
        #if os(iOS)
        .background(Color(.white).opacity(0.15))
        #else
        .background(Color(white: 0.949))
        #endif
    }
    
    @ViewBuilder
    private var contentView: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: data.systemImage)
                .font(.body)
                .foregroundStyle(data.urgencyIconColor)
                .frame(width: 28, height: 28)
                .background(data.urgencyForegroundColor)
                .cornerRadius(6)
            
            // Status text on the left
            if data.hasActiveRefresh {
                Text(String(localized: "balance_refreshing", defaultValue: "Refreshing"))
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
            } else if data.statusMessage.isEmpty {
                Text(String(localized: "balance_no_refresh_needed", defaultValue: "No refresh needed"))
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
            } else {
                Text(data.statusMessage)
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            
            // Time on the right
            if data.hasActiveRefresh {
                if let nextRound = timeUntilNextRound {
                    HStack(spacing: 4) {
                        Text(String(localized: "balance_next_round", defaultValue: "Next round"))
                            .font(.body)
                            .foregroundStyle(data.urgencyForegroundColor)
                        Text(nextRound)
                            .font(.body)
                            .foregroundStyle(data.urgencyForegroundColor)
                    }
                }
            } else if !data.statusMessage.isEmpty {
                // Refused: label + amount, the same pair shape as "Next round"
                // above, so the number cannot be read as a fee or a balance
                // (Refresh_Deduplication.md §10). The status text on the left
                // may wrap; this pair keeps its width.
                if data.isRefused, let heldBack = data.heldBackAmount {
                    HStack(spacing: 4) {
                        Text(String(localized: "label_held_back", defaultValue: "Held back"))
                            .font(.body)
                            .foregroundStyle(data.urgencyForegroundColor)
                        Text(BitcoinFormatter.shared.formatAmount(heldBack))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(data.urgencyForegroundColor)
                    }
                    .layoutPriority(1)
                    .accessibilityElement(children: .combine)
                } else if data.isExpired, let ago = data.expiredAgoString {
                    Text("\(ago) ago")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(data.urgencyForegroundColor)
                } else if let expiry = data.timeUntilExpiry {
                    Text(expiry)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(data.urgencyForegroundColor)
                }
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 20)
        #if os(iOS)
        .background(data.urgencyBackgroundColor)
        #else
        .background(Color(white: 0.949))
        #endif
    }
}

// MARK: - Previews

#Preview("Compact — refused") {
    VStack(spacing: 0) {
        BalanceRefreshStatusCompact(
            data: BalanceRefreshData(
                urgencyForegroundColor: .white,
                urgencyBackgroundColor: .black.opacity(0.15),
                urgencyIconColor: .Arke.orange,
                statusMessage: "Can't refresh from this device",
                heldBackAmount: 19_995,
                isRefused: true,
                systemImage: "exclamationmark.triangle.fill"
            ),
            currentTime: Date()
        )
        BalanceRefreshStatusCompact(
            data: BalanceRefreshData(
                urgencyForegroundColor: .white,
                urgencyBackgroundColor: .Arke.orange,
                urgencyIconColor: .Arke.orange,
                statusMessage: "Refresh now",
                showActionButton: true,
                totalAmountToRefresh: 5_000
            ),
            currentTime: Date()
        )
    }
    .background(Color.black)
}
