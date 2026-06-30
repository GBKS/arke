//
//  ExitProgressLockScreenView.swift
//  Arké
//
//  Lock screen UI for exit progression Live Activity
//  Created by Claude on 5/12/26.
//

import ActivityKit
import WidgetKit
import SwiftUI
import ArkeUI

/// Lock screen view for exit progression Live Activity
struct ExitProgressLockScreenView: View {
    let context: ActivityViewContext<ExitProgressActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with app icon and "Moving to Savings"
            HStack {
                Image("arke-icon")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
                
                Text("Moving to Savings")
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Show warning if check-in needed
                if context.state.needsCheckIn {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.body)
                }
            }
            
            // Segmented progress bar
            HStack(spacing: 3) {
                ForEach(1...context.state.totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= context.state.currentStep ? progressTint : progressTint.opacity(0.15))
                        .frame(height: 8)
                }
            }
            
            // Status row - step count on left, detailed status on right
            HStack {
                Text("Updated \(context.state.lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Step \(context.state.currentStep) of \(context.state.totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            if context.state.needsCheckIn {
                HStack {
                    Text("Tap notification to update")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            /*
            // Time since last update
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("Updated \(context.state.lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if context.state.needsCheckIn {
                    Text("Tap notification to update")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            */
        }
        .padding()
        .activityBackgroundTint(Color(white: 0.1))
    }
    
    // MARK: - Helper Properties
    
    private var progressTint: Color {
        if context.state.needsCheckIn {
            return .orange
        } else if context.state.hasError {
            return .red
        } else if context.state.isClaimed {
            return .Arke.green
        } else if context.state.currentStep >= context.state.totalTransactions + 2 {
            // Waiting for unlock or claiming
            return .Arke.orange
        } else {
            // Processing transactions
            return .Arke.purple
        }
    }
}
