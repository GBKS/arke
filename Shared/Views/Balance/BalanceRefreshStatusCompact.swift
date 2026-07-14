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
            
            Text("progress_loading")
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
            Image(systemName: "arrow.clockwise")
                .font(.body)
                .foregroundStyle(data.urgencyIconColor)
                .frame(width: 28, height: 28)
                .background(data.urgencyForegroundColor)
                .cornerRadius(6)
            
            // Status text on the left
            if data.hasActiveRefresh {
                Text("balance_refreshing")
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
            } else if data.statusMessage.isEmpty {
                Text("balance_no_refresh_needed")
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
            } else {
                Text(data.statusMessage)
                    .font(.body)
                    .foregroundStyle(data.urgencyForegroundColor)
            }
            
            Spacer()
            
            // Time on the right
            if data.hasActiveRefresh {
                if let nextRound = timeUntilNextRound {
                    HStack(spacing: 4) {
                        Text("balance_next_round")
                            .font(.body)
                            .foregroundStyle(data.urgencyForegroundColor)
                        Text(nextRound)
                            .font(.body)
                            .foregroundStyle(data.urgencyForegroundColor)
                    }
                }
            } else if !data.statusMessage.isEmpty {
                if data.isExpired, let ago = data.expiredAgoString {
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
