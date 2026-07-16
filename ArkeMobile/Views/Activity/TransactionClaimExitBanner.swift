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
/// The step math lives in the shared ExitProgress model, which also drives
/// the full timeline in ExitStatusDetailView_iOS.
struct TransactionClaimExitBanner: View {
    let exitStatus: ExitTransactionStatus
    let currentBlockHeight: UInt32?
    var blockedInfo: ExitBlockedInfo? = nil

    private var progress: ExitProgress {
        ExitProgress(status: exitStatus)
    }

    var body: some View {
        //if !exitStatus.isClaimed {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Text(progress.phase == .complete
                        ? "All \(progress.totalSteps) steps complete"
                        : "Step \(progress.currentStep) of \(progress.totalSteps)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ExitSegmentedProgressBar(progress: progress)

                // Blocked explanation: the exit can't continue right now because
                // fees can't be covered; progression retries automatically
                if let blockedInfo {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                        Text(ExitProgress.blockedExplanationKey(for: blockedInfo.reason))
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
            }
        //}
    }
}

/// Segmented progress bar shared by the exit banner and the exit status
/// detail header: one segment per step, filled up to the current step.
struct ExitSegmentedProgressBar: View {
    let progress: ExitProgress

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...progress.totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= progress.currentStep ? progress.tint : progress.tint.opacity(0.15))
                    .frame(height: 10)
            }
        }
    }
}

extension ExitProgress {
    /// Tint for the progress bar and step markers, by phase.
    var tint: Color {
        switch phase {
        case .complete:
            return .Arke.green
        case .waiting, .claiming:
            return .Arke.orange
        case .preparing, .confirming, .cancelled:
            return .Arke.purple
        }
    }

    static func blockedExplanationKey(for reason: ExitBlockedReason) -> LocalizedStringKey {
        switch reason {
        case .insufficientOnchainFunds:
            return "exit_blocked_funds_explanation"
        case .claimFeeExceedsOutput:
            return "exit_blocked_fees_explanation"
        case .other:
            return "exit_blocked_other_explanation"
        }
    }
}
