//
//  ActiveExitView.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI
import Bark
import ArkeUI

struct ActiveExitView_iOS: View {
    let exit: ExitVtxo
    let currentBlockHeight: Int
    let claimableHeight: Int
    
    @State private var isDetailsExpanded = false
    
    var body: some View {
        VStack(spacing: 24) {
            #if os(iOS)
            GeometryReader { geometry in
                LoopingVideoPlayer_iOS.aspectFill(videoName: "tai-chi", videoExtension: "mp4")
                    .frame(width: geometry.size.width, height: 250)
                    .cornerRadius(25)
                    .clipped()
            }
            .frame(height: 250)
            #elseif os(macOS)
            GeometryReader { geometry in
                LoopingVideoPlayer.aspectFill(videoName: "tai-chi", videoExtension: "mp4")
                    .frame(width: geometry.size.width, height: 250)
                    .cornerRadius(25)
                    .clipped()
            }
            .frame(height: 250)
            #endif
            
            Text("status_recovery_progress")
                .font(.system(.title, design: .serif))
            
            // Amount
            VStack(spacing: 8) {
                Text("balance_amount_recovering")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text(exit.formattedAmount)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            // Progress section
            if !exit.isClaimable && claimableHeight > 0 {
                VStack(spacing: 16) {
                    // Progress bar
                    /*
                    ExitProgressBar_iOS(
                        currentBlockHeight: currentBlockHeight,
                        claimableHeight: claimableHeight
                    )
                     */
                    
                    // Countdown
                    ExitCountdownView_iOS(
                        blocksRemaining: exit.blocksRemaining(
                            currentHeight: currentBlockHeight,
                            claimableHeight: claimableHeight
                        )
                    )
                    
                    // Info
                    /*
                    Text("Your bitcoin are locked during recovery. You will be able to claim them on completion.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    */
                }
            } else if !exit.isClaimable {
                // Awaiting confirmation - show time since start
                VStack(spacing: 12) {
                    if let _ = extractTipHeight(from: exit.state),
                       let confirmedBlock = extractConfirmedBlock(from: exit.state) {
                        let blocksSinceStart = currentBlockHeight - confirmedBlock
                        let minutesElapsed = blocksSinceStart * 10
                        
                        if minutesElapsed > 0 {
                            Text(timeElapsedDescription(minutes: minutesElapsed))
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Text(String(localized: "status_starting_recovery"))
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(String(localized: "status_starting_recovery"))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(String(localized: "message_24_hours"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            // Details section (collapsible)
            VStack(spacing: 0) {
                Button(action: {
                    withAnimation {
                        isDetailsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("data_technical_details")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                if isDetailsExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        // Status badge
                        HStack {
                            Image(systemName: exit.stateIcon)
                                .foregroundColor(Color(exit.stateColor))
                            Text(exit.stateDisplayName)
                                .font(.headline)
                                .foregroundColor(Color(exit.stateColor))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(exit.stateColor).opacity(0.15))
                        .cornerRadius(20)
                        
                        Divider()
                            
                        // VTXO ID
                        VStack(alignment: .leading, spacing: 8) {
                            Text("label_vtxo_id")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(exit.shortVtxoId)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider()
                        
                        // Current state
                        VStack(alignment: .leading, spacing: 8) {
                            Text("data_current_state")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(exit.state)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 30)
            
            // Spacer()
        }
    }
}

// MARK: - Helper Functions

/// Extract tip_height from state string like "AwaitingDelta(ExitAwaitingDeltaState { tip_height: 287164, ... })"
private func extractTipHeight(from state: String) -> Int? {
    let pattern = #"tip_height:\s*(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: state, range: NSRange(state.startIndex..., in: state)),
          let range = Range(match.range(at: 1), in: state) else {
        return nil
    }
    return Int(state[range])
}

/// Extract confirmed_block height from state string like "confirmed_block: 287161:000000..."
private func extractConfirmedBlock(from state: String) -> Int? {
    let pattern = #"confirmed_block:\s*(\d+):"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: state, range: NSRange(state.startIndex..., in: state)),
          let range = Range(match.range(at: 1), in: state) else {
        return nil
    }
    return Int(state[range])
}

/// Format elapsed time into a user-friendly description
private func timeElapsedDescription(minutes: Int) -> String {
    if minutes < 60 {
        return "Started \(minutes) minute\(minutes == 1 ? "" : "s") ago."
    } else {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours < 24 {
            if remainingMinutes > 0 {
                return "Started \(hours) hour\(hours == 1 ? "" : "s") and \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s") ago."
            } else {
                return "Started \(hours) hour\(hours == 1 ? "" : "s") ago."
            }
        } else {
            let days = hours / 24
            let remainingHours = hours % 24
            
            if remainingHours > 0 {
                return "Started \(days) day\(days == 1 ? "" : "s") and \(remainingHours) hour\(remainingHours == 1 ? "" : "s") ago."
            } else {
                return "Started \(days) day\(days == 1 ? "" : "s") ago."
            }
        }
    }
}

// MARK: - Supporting Views

struct ExitProgressBar_iOS: View {
    let currentBlockHeight: Int
    let claimableHeight: Int
    
    private var progress: Double {
        let totalBlocks = 144 // Approximate challenge period
        let blocksElapsed = max(0, totalBlocks - (claimableHeight - currentBlockHeight))
        return min(1.0, max(0, Double(blocksElapsed) / Double(totalBlocks)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("balance_recovery_process")
                .font(.subheadline)
                .fontWeight(.medium)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.Arke.orange)
                        .frame(width: geometry.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

struct ExitCountdownView_iOS: View {
    let blocksRemaining: Int
    
    @State private var showTimeBased = true
    
    private var hoursRemaining: Int {
        (blocksRemaining * 10) / 60 // 10 minutes per block
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTimeBased.toggle()
            }
        }) {
            VStack(spacing: 4) {
                if showTimeBased {
                    // Time-based display
                    if hoursRemaining > 0 {
                        Text("About \(hoursRemaining) hour\(hoursRemaining == 1 ? "" : "s") to go.")
                            .font(.title3)
                            .fontWeight(.semibold)
                    } else {
                        Text(String(localized: "status_less_than_hour"))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                } else {
                    // Block-based display
                    Text(String(localized: "status_blocks_remaining", defaultValue: "\(blocksRemaining) blocks to go."))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}
