//
//  TransactionListItem.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI
import Bark
import SwiftData

struct TransactionListItem: View {
    let transaction: TransactionModel
    @Binding var selectedTransaction: TransactionModel?
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    
    private var transactionDisplayText: String {
        // Access dataVersion to create observation dependency
        _ = walletManager.dataVersion
        
        return transaction.displayText(includeStatusPrefix: true)
    }
    
    private var dateAndTagsText: String {
        // Access dataVersion to create observation dependency
        _ = walletManager.dataVersion
        
        var components: [String] = [transaction.formattedDate]
        
        // Add tag names
        let tagNames = transaction.associatedTags.map { $0.name }
        components.append(contentsOf: tagNames)
        
        return components.joined(separator: " · ")
    }
    
    /// Blocked state for this transaction's exit (fees can't be covered right now)
    private var exitBlockedReason: ExitBlockedReason? {
        // Access dataVersion to create observation dependency
        _ = walletManager.dataVersion

        return transaction.exitBlockedInfo?.reason
    }

    private func exitBlockedBadgeKey(for reason: ExitBlockedReason) -> LocalizedStringKey {
        switch reason {
        case .insufficientOnchainFunds:
            return "status_exit_paused_funds"
        case .claimFeeExceedsOutput:
            return "status_exit_paused_fees"
        case .other:
            return "status_exit_paused"
        }
    }

    /// Check if this is an exit transaction in its final stage (claimable or
    /// claim in progress). Auto-claim handles both without user action.
    private var isExitFinalizing: Bool {
        // Access dataVersion to create observation dependency
        _ = walletManager.dataVersion

        // Only check for exit transactions
        guard transaction.hasUnilateralExit else {
            return false
        }

        // Check current exit status
        if let exitStatus = transaction.currentExitStatus {
            // Don't show if already claimed
            if exitStatus.isClaimed {
                return false
            }
            return exitStatus.isClaimable || exitStatus.isClaimInProgress
        }

        // Fallback: check if any of the exited VTXOs are in a finalizing state
        let exitedIds = Set(transaction.exitedVtxoIds)
        return walletManager.activeUnilateralExits.contains { exit in
            exitedIds.contains(exit.vtxoId) && (exit.isClaimable || exit.isClaimInProgress)
        }
    }
    
    /// Returns the appropriate amount text color based on transaction status
    private var amountTextColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed.
        // isExitComplete reads the persisted movement status first, so
        // completed exits render correctly at launch before the in-memory
        // exit caches are populated.
        if transaction.hasUnilateralExit {
            if transaction.isExitComplete {
                if transaction.isInternalTransfer {
                    // Internal transfers show fees as negative (like sends)
                    return .primary
                }
                return transaction.transactionType.amountColor
            }
            // Exit is still in progress (not yet claimed)
            return .Arke.blue
        }
        
        switch transaction.transactionStatus {
        case .confirmed:
            // For confirmed transactions, use semantic colors
            if transaction.isInternalTransfer {
                // Internal transfers show fees as negative (like sends)
                return .primary
            }
            return transaction.transactionType.amountColor
            
        case .pending:
            return .primary // Testing if blue is needed
            //return .Arke.blue

        case .failed:
            return .Arke.red

        case .cancelled:
            return .gray
        }
    }
    
    var body: some View {
        // Access dataVersion at the beginning to ensure entire body observes changes
        let _ = walletManager.dataVersion
        
        // Set the wallet manager reference for exit status lookups
        let _ = { TransactionModel.walletManager = walletManager }()
        
        HStack(spacing: 12) {
            TransactionIconView(transaction: transaction, size: 44)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transactionDisplayText)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(dateAndTagsText)
                    .font(.body)
                    .foregroundColor(.arkeSecondary)
                
                // Exit progress indicators: blocked wins over finalizing, since
                // a blocked exit is technically still claimable but the claim
                // keeps failing. No call-to-action here - auto-claim is the
                // only claim path, so the badge is purely informational.
                if let blockedReason = exitBlockedReason {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(exitBlockedBadgeKey(for: blockedReason))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.Arke.orange)
                    .cornerRadius(6)
                    .padding(.top, 4)
                } else if isExitFinalizing {
                    Text("status_exit_finalizing")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Arke.blue)
                        .cornerRadius(6)
                        .padding(.top, 4)
                }
                
                /*
                if transaction.hasFees, let formattedFee = transaction.formattedFee {
                    Text("Fee: \(formattedFee)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                */
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                /*
                if transaction.transactionStatus != .confirmed {
                    TransactionStatusBadge(status: transaction.transactionStatus)
                }
                */
                
                // For exits, include fees from linked onchain transactions.
                // Hide the amount for refresh transactions with a zero net amount.
                if !(transaction.category == .refresh && transaction.netAmountIncludingLinked(modelContext: modelContext) == 0) {
                    Text(transaction.formattedNetAmountIncludingLinked(modelContext: modelContext))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(amountTextColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(selectedTransaction?.txid == transaction.txid ? Color.Arke.gold.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .cornerRadius(15)
        .onTapGesture {
            selectedTransaction = transaction
        }
    }
}
