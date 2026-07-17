//
//  Arke_WidgetsLiveActivity.swift
//  ArkeWidgets
//
//  Exit progression Live Activity
//  Created by Christoph on 5/12/26.
//

import ActivityKit
import WidgetKit
import SwiftUI
import ArkeUI

struct ExitProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExitProgressActivityAttributes.self) { context in
            // Lock screen / banner UI
            ExitProgressLockScreenView(context: context)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded region - when user long-presses the island
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        // Logo and title inline, centered
                        HStack(spacing: 8) {
                            if context.state.needsCheckIn {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                    .symbolEffect(.bounce, value: context.state.needsCheckIn)
                            } else {
                                Image("arke-icon")
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .cornerRadius(4)
                            }
                            
                            Text("Moving to Savings")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        
                        if context.state.needsCheckIn {
                            Text("Check app to continue")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    // Segmented progress bar matching lock screen design
                    HStack(spacing: 4) {
                        ForEach(1...context.state.totalSteps, id: \.self) { step in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(step <= context.state.currentStep ? progressTint(context.state) : Color.clear)
                                .frame(height: 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(progressTint(context.state), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                
            } compactLeading: {
                // Compact state - when island is small
                if context.state.needsCheckIn {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                } else {
                    Image("arke-icon")
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                }
                
            } compactTrailing: {
                Text("\(context.state.currentStep)/\(context.state.totalSteps)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                
            } minimal: {
                // Minimal state - when island is smallest (multiple activities)
                if context.state.needsCheckIn {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                } else {
                    Image("arke-icon")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .cornerRadius(3)
                }
            }
            .keylineTint(progressTint(context.state))
        }
    }
    
    // MARK: - Helper Functions
    
    private func progressTint(_ state: ExitProgressActivityAttributes.ContentState) -> Color {
        if state.needsCheckIn { return .orange }
        if state.hasError { return .red }
        switch state.exitState {
        case .claimed:
            return .Arke.green
        case .awaitingDelta, .claimable, .claimInProgress:
            return .Arke.orange
        default:
            return .Arke.purple
        }
    }
}

// MARK: - Preview Support

extension ExitProgressActivityAttributes {
    fileprivate static var preview: ExitProgressActivityAttributes {
        ExitProgressActivityAttributes(
            exitId: "preview-exit-id",
            exitCount: 1,
            startTime: Date()
        )
    }
}

extension ExitProgressActivityAttributes.ContentState {
    fileprivate static var starting: ExitProgressActivityAttributes.ContentState {
        ExitProgressActivityAttributes.ContentState(
            currentStep: 1,
            totalSteps: 7, // 3 transactions + 4 steps
            stepDescription: "Starting move to savings",
            transactionsConfirmed: 0,
            totalTransactions: 3,
            exitState: .start,
            lastUpdated: Date(),
            needsCheckIn: false,
            isWaitingForBlocks: false,
            isClaimable: false,
            isClaimed: false,
            hasError: false
        )
    }
    
    fileprivate static var confirming: ExitProgressActivityAttributes.ContentState {
        ExitProgressActivityAttributes.ContentState(
            currentStep: 4, // Step 2 + 2 confirmed transactions
            totalSteps: 7,
            stepDescription: "Confirming transactions",
            transactionsConfirmed: 2,
            totalTransactions: 3,
            exitState: .processing,
            lastUpdated: Date().addingTimeInterval(-300), // 5 min ago
            needsCheckIn: false,
            isWaitingForBlocks: false,
            isClaimable: false,
            isClaimed: false,
            hasError: false
        )
    }
    
    fileprivate static var needsCheckIn: ExitProgressActivityAttributes.ContentState {
        ExitProgressActivityAttributes.ContentState(
            currentStep: 5, // All 3 txs confirmed, waiting for unlock
            totalSteps: 7,
            stepDescription: "Waiting for blocks",
            transactionsConfirmed: 3,
            totalTransactions: 3,
            exitState: .awaitingDelta,
            lastUpdated: Date().addingTimeInterval(-5400), // 90 min ago
            needsCheckIn: true,
            currentBlockHeight: 850000,
            targetBlockHeight: 850012,
            blocksRemaining: 12,
            isWaitingForBlocks: true,
            isClaimable: false,
            isClaimed: false,
            hasError: false
        )
    }
    
    fileprivate static var complete: ExitProgressActivityAttributes.ContentState {
        ExitProgressActivityAttributes.ContentState(
            currentStep: 7, // Complete
            totalSteps: 7,
            stepDescription: "Move complete!",
            transactionsConfirmed: 3,
            totalTransactions: 3,
            exitState: .claimed,
            lastUpdated: Date(),
            needsCheckIn: false,
            isWaitingForBlocks: false,
            isClaimable: false,
            isClaimed: true,
            hasError: false
        )
    }
}

#Preview("Notification", as: .content, using: ExitProgressActivityAttributes.preview) {
    ExitProgressLiveActivity()
} contentStates: {
    ExitProgressActivityAttributes.ContentState.starting
    ExitProgressActivityAttributes.ContentState.confirming
    ExitProgressActivityAttributes.ContentState.needsCheckIn
    ExitProgressActivityAttributes.ContentState.complete
}
