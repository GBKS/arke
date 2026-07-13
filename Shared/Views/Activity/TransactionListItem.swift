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
    
    /// Check if this is an exit transaction with claimable VTXOs
    private var hasClaimableExit: Bool {
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
            // Show badge if claimable
            return exitStatus.isClaimable
        }
        
        // Fallback: check if any of the exited VTXOs are in a claimable state
        let exitedIds = Set(transaction.exitedVtxoIds)
        let hasClaimable = walletManager.activeUnilateralExits.contains { exit in
            exitedIds.contains(exit.vtxoId) && exit.isClaimable
        }
        
        return hasClaimable
    }
    
    // MARK: - Icon and Color Helpers
    
    /// Returns the appropriate icon name based on transaction category or type
    private var transactionIconName: String {
        // For internal transfers, use category-specific icons
        if transaction.isInternalTransfer, let category = transaction.category {
            // Special case: onchain_send with bark.offboard subsystem should use offboarding icon
            // TODO: This needs a more elegant solution
            if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                return MovementCategory.offboarding.icon
            }
            
            return category.icon
        }
        
        // For other transactions, use type-based icons
        return transaction.transactionType.iconName
    }
    
    /// Returns the appropriate icon color based on transaction status
    private var transactionIconColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed
        if transaction.hasUnilateralExit {
            // Check current exit status
            if let exitStatus = transaction.currentExitStatus {
                if exitStatus.isClaimed {
                    // Exit is complete
                    if transaction.isInternalTransfer {
                        return .gray
                    }
                    return transaction.transactionType.iconColor
                } else {
                    // Exit is still pending (not yet claimed)
                    return .Arke.blue
                }
            }
            // Fallback to subsystemKind if wallet manager unavailable
            else if transaction.subsystemKind == "claimed" {
                if transaction.isInternalTransfer {
                    return .gray
                }
                return transaction.transactionType.iconColor
            } else {
                return .Arke.blue
            }
        }
        
        switch transaction.transactionStatus {
        case .confirmed:
            // For confirmed transactions, use semantic colors
            if transaction.isInternalTransfer {
                return .gray
            }
            return transaction.transactionType.iconColor
            
        case .pending:
            return .Arke.blue

        case .failed:
            return .Arke.red

        case .cancelled:
            return .gray
        }
    }

    /// Returns the appropriate amount text color based on transaction status
    private var amountTextColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed
        if transaction.hasUnilateralExit {
            // Check current exit status
            if let exitStatus = transaction.currentExitStatus {
                if exitStatus.isClaimed {
                    // Exit is complete
                    if transaction.isInternalTransfer {
                        // Internal transfers show fees as negative (like sends)
                        return .primary
                    }
                    return transaction.transactionType.amountColor
                } else {
                    // Exit is still pending (not yet claimed)
                    return .Arke.blue
                }
            }
            // Fallback to subsystemKind if wallet manager unavailable
            else if transaction.subsystemKind == "claimed" {
                if transaction.isInternalTransfer {
                    return .primary
                }
                return transaction.transactionType.amountColor
            } else {
                return .Arke.blue
            }
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
            // Transaction Icon with optional tag badge
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let contact = transaction.associatedContacts.first {
                        // Show contact avatar
                        ContactAvatarView(avatarData: contact.avatarData, size: 44)
                    } else if transaction.isInternalTransfer {
                        // TEST: Using images instead of icons for internal transfers
                        // For internal transfers, always show the category icon (not tag emoji)
                        /*
                        Image(systemName: transactionIconName)
                            .font(.title3)
                            .foregroundColor(transactionIconColor)
                            .frame(width: 32, height: 32)
                            .background(transactionIconColor.opacity(0.1))
                            .cornerRadius(8)
                        */
                        
                        // Determine which image to show based on category
                        let imageName: String = {
                            if let category = transaction.category {
                                // Special case: onchain_send with bark.offboard subsystem should use offboarding logic
                                if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                                    return "safe"
                                }
                                
                                switch category {
                                case .boarding, .refresh:
                                    return "wallet"
                                case .offboarding:
                                    return "safe"
                                case .onchainTransaction:
                                    // Onchain self-transfers use safe image
                                    if transaction.subsystemKind == "self_transfer" {
                                        return "safe"
                                    }
                                    return "wallet"
                                default:
                                    return "wallet" // fallback
                                }
                            }
                            
                            // Check for exit subsystem
                            if transaction.subsystemName == "bark.exit" {
                                return "safe"
                            }
                            
                            return "wallet" // fallback
                        }()
                        
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .cornerRadius(8)
                    } else if let firstTag = transaction.associatedTags.first {
                        Text(firstTag.emoji)
                            .font(.system(size: 11))
                            .frame(width: 44, height: 44)
                            .background(firstTag.color.opacity(0.2))
                            .foregroundColor(firstTag.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // Show default transaction icon (category-aware for internal transfers)
                        Image(systemName: transactionIconName)
                            .font(.title3)
                            .foregroundColor(transactionIconColor)
                            .frame(width: 44, height: 44)
                            .background(transactionIconColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                // Tag emoji badge
                if let firstTag = transaction.associatedTags.first,
                   transaction.associatedContacts.first != nil {
                    Text(firstTag.emoji)
                        .font(.system(size: 9))
                        .frame(width: 16, height: 16)
                        .background(Color.white)
                        .clipShape(Circle())
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 44, height: 44)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transactionDisplayText)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(dateAndTagsText)
                    .font(.body)
                    .foregroundColor(.arkeSecondary)
                
                // Claimable exit indicator
                if hasClaimableExit {
                    HStack(spacing: 4) {
                        Text("status_ready_approve")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
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
