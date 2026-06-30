//
//  TransactionModel+DisplayHelpers.swift
//  Arké
//
//  Created by Assistant on 1/8/26.
//

import Foundation
import ArkeUI

extension TransactionModel {
    
    /// Returns a concise user-friendly display text for transaction lists
    /// - Parameter includeStatusPrefix: Whether to include status-aware prefixes (e.g., "Sending to" vs "To")
    /// - Returns: A formatted display string
    func shortDisplayText(includeStatusPrefix: Bool = true) -> String {
        // Prioritize notes if they exist
        if let notes = notes, !notes.isEmpty {
            return notes
        }
        
        // Check if this is a categorized operation
        if let category = category {
            switch category {
            case .boarding:
                return statusAwareText(
                    confirmed: "Moved",
                    pending: "Moving",
                    failed: "Failed move",
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: "Forced Move",
                    pending: "Forcing Move",
                    failed: "Failed Forced Move",
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: "Moved",
                    pending: "Moving",
                    failed: "Failed move",
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: "Refresh",
                    pending: "Refreshing",
                    failed: "Failed refresh",
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: "Sent",
                    pending: "Sending",
                    failed: "Failed send",
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: "Received",
                    pending: "Receiving",
                    failed: "Failed receive",
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    return statusAwareText(
                        confirmed: "Moved",
                        pending: "Moving",
                        failed: "Failed move",
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: "Sent",
                    pending: "Sending",
                    failed: "Failed send",
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                /*
                return statusAwareText(
                    confirmed: "Bitcoin",
                    pending: "Bitcoin",
                    failed: "Failed Bitcoin tx",
                    includePrefix: includeStatusPrefix
                )
                */
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    return statusAwareText(
                        confirmed: "Moved",
                        pending: "Moving",
                        failed: "Failed move",
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: "Received",
                        pending: "Receiving",
                        failed: "Failed receive",
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: "Sent",
                        pending: "Sending",
                        failed: "Failed send",
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return "Transaction"
                }
            case .offchainTransfer:
                // Fall through to contact logic below
                break
            case .unknown:
                break
            }
        }
        
        /*
        // Contact-based display for regular send/receive
        switch transactionType {
        case .received:
            return statusAwareText(
                confirmed: "Received",
                pending: "Receiving",
                failed: "Failed receive",
                includePrefix: includeStatusPrefix
            )
        case .sent:
            return statusAwareText(
                confirmed: "Sent",
                pending: "Sending",
                failed: "Failed send",
                includePrefix: includeStatusPrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: "Move",
                pending: "Moving",
                failed: "Failed move",
                includePrefix: includeStatusPrefix
            )
        case .pending:
            return "Pending..."
        }
        */
        
        // Fallback to status-aware type display
        return statusAwareTypeDisplayName(includePrefix: includeStatusPrefix)
    }
    
    /// Returns a concise user-friendly display text for transaction lists
    /// - Parameter includeStatusPrefix: Whether to include status-aware prefixes (e.g., "Sending to" vs "To")
    /// - Returns: A formatted display string
    func displayText(includeStatusPrefix: Bool = true) -> String {
        // Prioritize notes if they exist
        if let notes = notes, !notes.isEmpty {
            return notes
        }
        
        // Check if this is a categorized operation
        if let category = category {
            switch category {
            case .boarding:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: "Moved \(amountText)",
                    pending: "Moving \(amountText)",
                    failed: "Failed move",
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: "Force moved \(amountText)",
                    pending: "Force moving \(amountText)",
                    failed: "Failed forced move",
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: "Moved \(amountText)",
                    pending: "Moving \(amountText)",
                    failed: "Failed move",
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: "Refresh",
                    pending: "Refreshing",
                    failed: "Failed refresh",
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: "To \(contact.cachedName)",
                        pending: "Sending to \(contact.cachedName)",
                        failed: "Failed send to \(contact.cachedName)",
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: "Sent",
                    pending: "Sending",
                    failed: "Failed send",
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: "From \(contact.cachedName)",
                        pending: "Receiving from \(contact.cachedName)",
                        failed: "Failed receive from \(contact.cachedName)",
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: "Received",
                    pending: "Receiving",
                    failed: "Failed receive",
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: "Moved \(amountText)",
                        pending: "Moving \(amountText)",
                        failed: "Failed move to savings",
                        includePrefix: includeStatusPrefix
                    )
                }
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: "To \(contact.cachedName)",
                        pending: "Sending to \(contact.cachedName)",
                        failed: "Failed send to \(contact.cachedName)",
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: "Sent",
                    pending: "Sending",
                    failed: "Failed send",
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: "Moved \(amountText)",
                        pending: "Moving \(amountText)",
                        failed: "Failed move",
                        includePrefix: includeStatusPrefix
                    )
                }
                
                if let contact = associatedContacts.first {
                    switch type {
                    case .received:
                        return statusAwareText(
                            confirmed: "From \(contact.cachedName)",
                            pending: "Receiving from \(contact.cachedName)",
                            failed: "Failed receive",
                            includePrefix: includeStatusPrefix
                        )
                    case .sent:
                        return statusAwareText(
                            confirmed: "To \(contact.cachedName)",
                            pending: "Sending to \(contact.cachedName)",
                            failed: "Failed send",
                            includePrefix: includeStatusPrefix
                        )
                    default:
                        break
                    }
                }
                // No contact - show generic bitcoin transaction
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: "Received",
                        pending: "Receiving",
                        failed: "Failed receive",
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: "Sent",
                        pending: "Sending",
                        failed: "Failed send",
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return "Bitcoin Transaction"
                }
            case .offchainTransfer:
                // Fall through to contact logic below
                break
            case .unknown:
                break
            }
        }
        
        // Contact-based display for regular send/receive
        if let contact = associatedContacts.first {
            switch transactionType {
            case .received:
                return statusAwareText(
                    confirmed: "From \(contact.cachedName)",
                    pending: "Receiving from \(contact.cachedName)",
                    failed: "Failed receive from \(contact.cachedName)",
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: "To \(contact.cachedName)",
                    pending: "Sending to \(contact.cachedName)",
                    failed: "Failed send to \(contact.cachedName)",
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: "Transfer",
                    pending: "Transferring",
                    failed: "Failed transfer",
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return "Pending..."
            }
        }
        
        // Fallback to status-aware type display
        return statusAwareTypeDisplayName(includePrefix: includeStatusPrefix)
    }
    
    /// Returns a more detailed display text for transaction detail views
    /// Includes balance information where applicable
    /// - Parameter includeStatusPrefix: Whether to include status-aware prefixes (e.g., "Sending to" vs "To")
    /// - Returns: A detailed formatted display string
    func detailedDisplayText(includeStatusPrefix: Bool = true) -> String {
        // Prioritize notes if they exist
        if let notes = notes, !notes.isEmpty {
            return notes
        }
        
        // Check if this is a categorized operation
        if let category = category {
            switch category {
            case .boarding:
                return statusAwareText(
                    confirmed: "From savings to payments.",
                    pending: "From savings to payments.",
                    failed: "From savings to payments.",
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: "From payments to savings.",
                    pending: "From payments to savings.",
                    failed: "From payments to savings.",
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: "From payments to savings.",
                    pending: "From payments to savings.",
                    failed: "From payments to savings.",
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: "Refreshed payments balance.",
                    pending: "Refreshing payments balance.",
                    failed: "Failed refreshing payments balance.",
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: "From payments.",
                    pending: "From payments.",
                    failed: "From payments.",
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: "To payments.",
                    pending: "To payments.",
                    failed: "Failed receive to payments.",
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if subsystemName == "bark.offboard" {
                    return statusAwareText(
                        confirmed: "From payments to savings.",
                        pending: "From payments to savings.",
                        failed: "From payments to savings.",
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: "From savings.",
                    pending: "From savings.",
                    failed: "From savings.",
                    includePrefix: includeStatusPrefix
                )
            case .offchainTransfer:
                return statusAwareText(
                    confirmed: "From payments.",
                    pending: "From payments.",
                    failed: "From payments.",
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    return statusAwareText(
                        confirmed: "Within savings.",
                        pending: "Within savings.",
                        failed: "Failed move within savings.",
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: "To savings.",
                        pending: "To savings.",
                        failed: "Failed receive.",
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: "From savings.",
                        pending: "From savings.",
                        failed: "Failed send.",
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return "Transaction."
                }
            case .unknown:
                break
            }
        }
        
        // Contact-based display for regular send/receive
        if let contact = associatedContacts.first {
            let amountText = BitcoinFormatter.shared.formatAmount(amount)
            
            switch transactionType {
            case .received:
                return statusAwareText(
                    confirmed: "Received \(amountText) from \(contact.cachedName).",
                    pending: "Receiving \(amountText) from \(contact.cachedName).",
                    failed: "Failed receive from \(contact.cachedName).",
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: "Sent \(amountText) to \(contact.cachedName).",
                    pending: "Sending \(amountText) to \(contact.cachedName).",
                    failed: "Failed send to \(contact.cachedName).",
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: "Transfer.",
                    pending: "Transferring.",
                    failed: "Failed transfer.",
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return "Pending..."
            }
        }
        
        // Fallback to status-aware type display
        return statusAwareTypeDisplayName(includePrefix: includeStatusPrefix)
    }
    
    /// Helper method to return status-aware text
    private func statusAwareText(confirmed: String, pending: String, failed: String, includePrefix: Bool) -> String {
        guard includePrefix else {
            return confirmed
        }
        
        // Special case for unilateral exits: check live exit status
        // Only consider exit complete when it's been claimed
        if hasUnilateralExit {
            // Try to get current exit status from wallet manager
            if let exitStatus = currentExitStatus {
                if exitStatus.isClaimed {
                    return confirmed
                } else {
                    // Exit is still pending (not yet claimed)
                    return pending
                }
            }
            // Fallback to subsystemKind if wallet manager unavailable
            else {
                if subsystemKind == "claimed" {
                    return confirmed
                } else {
                    return pending
                }
            }
        }
        
        switch transactionStatus {
        case .confirmed:
            return confirmed
        case .pending:
            return pending
        case .failed:
            return failed
        }
    }
    
    /// Helper method to return status-aware transaction type display name
    private func statusAwareTypeDisplayName(includePrefix: Bool) -> String {
        guard includePrefix else {
            return transactionType.displayName
        }
        
        switch transactionType {
        case .sent:
            return statusAwareText(
                confirmed: "Sent",
                pending: "Sending",
                failed: "Failed send",
                includePrefix: includePrefix
            )
        case .received:
            return statusAwareText(
                confirmed: "Received",
                pending: "Receiving",
                failed: "Failed receive",
                includePrefix: includePrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: "Move",
                pending: "Moving",
                failed: "Failed move",
                includePrefix: includePrefix
            )
        case .pending:
            return "Pending..."
        }
    }
    
    /// Returns explanatory text for transaction categories that may not be intuitive to users
    var explainerText: String? {
        guard let category = category else { return nil }
        
        switch category {
        case .refresh:
            return "A refresh is a maintenance operation that extends the lifetime of your payments balance. No bitcoin was sent or received."
            
        case .exit:
            return "A recovery moves bitcoin from your payments balance to your savings balance without the involvement of the server that typically facilitates this."
            
        //case .onchainTransaction:
        //    return "This is a native Bitcoin transaction managed by your onchain wallet. These transactions are settled directly on the Bitcoin blockchain."
            
        default:
            return nil
        }
    }
}
