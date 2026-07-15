//
//  TransactionClaimExitBanner.swift
//  Arké
//
//  Created by Assistant on 2/6/26.
//

import SwiftUI
import ArkeUI
import Bark

/// Banner displayed when a unilateral exit transaction is in progress.
/// Shows automatic exit progression through transaction-based steps.
struct TransactionClaimExitBanner: View {
    let exitStatus: ExitTransactionStatus
    let currentBlockHeight: UInt32?
    var blockedInfo: ExitBlockedInfo? = nil

    @State private var showClaimConfirmation = false

    var body: some View {
        if !exitStatus.isClaimed {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and "Moving to Savings"
                HStack(spacing: 8) {
                    /*
                    Image(systemName: currentStepIcon)
                        .font(.title3)
                        .foregroundColor(.white)
                    */

                    Text("Step \(currentStep) of \(totalSteps)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                // Segmented progress bar
                HStack(spacing: 3) {
                    ForEach(1...totalSteps, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(step <= currentStep ? progressTint : progressTint.opacity(0.15))
                            .frame(height: 10)
                    }
                }

                // Blocked explanation: the exit can't continue right now because
                // fees can't be covered; progression retries automatically
                if let blockedInfo {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(blockedExplanationKey(for: blockedInfo.reason))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                /*
                // Status row - step count and detailed status
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step \(currentStep) of \(totalSteps)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                        
                        if let statusText = detailedStatusText {
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                }
                */
            }
            //.padding(16)
            //.background(backgroundColor)
            //.cornerRadius(16)
        }
    }
    
    // MARK: - Computed Properties

    private func blockedExplanationKey(for reason: ExitBlockedReason) -> LocalizedStringKey {
        switch reason {
        case .insufficientOnchainFunds:
            return "exit_blocked_funds_explanation"
        case .claimFeeExceedsOutput:
            return "exit_blocked_fees_explanation"
        case .other:
            return "exit_blocked_other_explanation"
        }
    }

    /// Determine the current step based on transaction progress
    /// Steps: 1=Prepare, 2..k+1=Process transactions, k+2=Wait unlock, k+3=Claim, k+4=Complete
    private var currentStep: Int {
        guard let parsedState = exitStatus.parsedState else {
            return 1 // Default to step 1 if we can't parse
        }
        
        switch parsedState {
        case .start:
            return 1 // Prepare exit
            
        case .processing(let data):
            // Step 2 + number of confirmed transactions
            let confirmedCount = data.transactions.filter { tx in
                if case .confirmed = tx.status {
                    return true
                }
                return false
            }.count
            return 2 + confirmedCount
            
        case .awaitingDelta:
            // All exit transactions confirmed, waiting for timelock
            return transactionCount + 2
            
        case .claimable:
            // Ready to claim but not yet started
            return transactionCount + 2
            
        case .claimInProgress:
            // Processing claim transaction
            return transactionCount + 3
            
        case .claimed:
            // Complete
            return transactionCount + 4

        case .vtxoAlreadySpent:
            // Terminal: exit cancelled because the VTXO was spent elsewhere.
            return 1

        case .unparsed:
            return 1
        }
    }
    
    /// Total number of steps = transactions + 4 (prepare + wait + claim + complete)
    private var totalSteps: Int {
        return transactionCount + 4
    }
    
    /// Number of exit transactions that need to be processed
    private var transactionCount: Int {
        // Get transaction count from the parsed state
        if case .processing(let data) = exitStatus.parsedState {
            return max(1, data.transactions.count)
        }
        // For other states, check transaction chain
        let chainCount = exitStatus.transactionChain.count
        return max(1, chainCount)
    }
    
    private var currentStepIcon: String {
        if exitStatus.isClaimed {
            return "checkmark.circle.fill"
        }
        return "arrow.down.circle"
    }
    
    private var detailedStatusText: String? {
        guard let parsedState = exitStatus.parsedState else {
            return "Processing exit"
        }
        
        switch parsedState {
        case .start:
            return "Preparing exit transactions"
            
        case .processing(let data):
            let confirmedCount = data.transactions.filter { tx in
                if case .confirmed = tx.status {
                    return true
                }
                return false
            }.count
            
            if confirmedCount == 0 {
                return "Broadcasting transaction \(confirmedCount + 1) of \(transactionCount)"
            } else if confirmedCount < transactionCount {
                return "Processing transaction \(confirmedCount + 1) of \(transactionCount)"
            } else {
                return "All transactions confirmed"
            }
            
        case .awaitingDelta(let data):
            if let currentHeight = currentBlockHeight {
                let remaining = Int(data.claimableHeight) - Int(currentHeight)
                if remaining > 0 {
                    return "Waiting for unlock (\(remaining) blocks)"
                }
            }
            return "Waiting for unlock delay"
            
        case .claimable:
            return "Claiming automatically"
            
        case .claimInProgress:
            return "Processing claim transaction"
            
        case .claimed:
            return "Exit complete"

        case .vtxoAlreadySpent:
            return "Exit cancelled — funds already spent"

        case .unparsed:
            return "Processing exit"
        }
    }
    
    private var progressTint: Color {
        if exitStatus.isClaimed {
            return .Arke.green
        } else if currentStep >= transactionCount + 2 {
            return .Arke.orange
        } else {
            return .Arke.purple
        }
    }
    
    private var backgroundColor: Color {
        if exitStatus.isClaimed {
            return .Arke.green
        } else if currentStep >= transactionCount + 2 {
            return .Arke.orange
        } else {
            return .Arke.blue
        }
    }
}
