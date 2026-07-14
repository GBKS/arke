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
                    confirmed: String(localized: "transaction_moved"),
                    pending: String(localized: "transaction_moving"),
                    failed: String(localized: "transaction_failed_move"),
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: String(localized: "transaction_forced_move"),
                    pending: String(localized: "transaction_forcing_move"),
                    failed: String(localized: "transaction_failed_forced_move"),
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: String(localized: "transaction_moved"),
                    pending: String(localized: "transaction_moving"),
                    failed: String(localized: "transaction_failed_move"),
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_refresh"),
                    pending: String(localized: "transaction_refreshing"),
                    failed: String(localized: "transaction_failed_refresh"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: String(localized: "transaction_sent"),
                    pending: String(localized: "transaction_sending"),
                    failed: String(localized: "transaction_failed_send"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: String(localized: "transaction_received"),
                    pending: String(localized: "transaction_receiving"),
                    failed: String(localized: "transaction_failed_receive"),
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_moved"),
                        pending: String(localized: "transaction_moving"),
                        failed: String(localized: "transaction_failed_move"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: String(localized: "transaction_sent"),
                    pending: String(localized: "transaction_sending"),
                    failed: String(localized: "transaction_failed_send"),
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
                        confirmed: String(localized: "transaction_moved"),
                        pending: String(localized: "transaction_moving"),
                        failed: String(localized: "transaction_failed_move"),
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_received"),
                        pending: String(localized: "transaction_receiving"),
                        failed: String(localized: "transaction_failed_receive"),
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_sent"),
                        pending: String(localized: "transaction_sending"),
                        failed: String(localized: "transaction_failed_send"),
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_generic")
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
                confirmed: String(localized: "transaction_received"),
                pending: String(localized: "transaction_receiving"),
                failed: String(localized: "transaction_failed_receive"),
                cancelled: String(localized: "transaction_cancelled_receive"),
                includePrefix: includeStatusPrefix
            )
        case .sent:
            return statusAwareText(
                confirmed: String(localized: "transaction_sent"),
                pending: String(localized: "transaction_sending"),
                failed: String(localized: "transaction_failed_send"),
                cancelled: String(localized: "transaction_cancelled_send"),
                includePrefix: includeStatusPrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: String(localized: "transaction_move"),
                pending: String(localized: "transaction_moving"),
                failed: String(localized: "transaction_failed_move"),
                cancelled: String(localized: "transaction_cancelled_move"),
                includePrefix: includeStatusPrefix
            )
        case .pending:
            return String(localized: "transaction_pending")
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
                    confirmed: String(localized: "transaction_moved_amount \(amountText)"),
                    pending: String(localized: "transaction_moving_amount \(amountText)"),
                    failed: String(localized: "transaction_failed_move"),
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: String(localized: "transaction_force_moved_amount \(amountText)"),
                    pending: String(localized: "transaction_force_moving_amount \(amountText)"),
                    failed: String(localized: "transaction_failed_forced_move"),
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: String(localized: "transaction_moved_amount \(amountText)"),
                    pending: String(localized: "transaction_moving_amount \(amountText)"),
                    failed: String(localized: "transaction_failed_move"),
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_refresh"),
                    pending: String(localized: "transaction_refreshing"),
                    failed: String(localized: "transaction_failed_refresh"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_to_contact \(contact.cachedName)"),
                        pending: String(localized: "transaction_sending_to_contact \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_send_to_contact \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: String(localized: "transaction_sent"),
                    pending: String(localized: "transaction_sending"),
                    failed: String(localized: "transaction_failed_send"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_from_contact \(contact.cachedName)"),
                        pending: String(localized: "transaction_receiving_from_contact \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_receive_from_contact \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: String(localized: "transaction_received"),
                    pending: String(localized: "transaction_receiving"),
                    failed: String(localized: "transaction_failed_receive"),
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: String(localized: "transaction_moved_amount \(amountText)"),
                        pending: String(localized: "transaction_moving_amount \(amountText)"),
                        failed: String(localized: "transaction_failed_move_to_savings"),
                        includePrefix: includeStatusPrefix
                    )
                }
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_to_contact \(contact.cachedName)"),
                        pending: String(localized: "transaction_sending_to_contact \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_send_to_contact \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: String(localized: "transaction_sent"),
                    pending: String(localized: "transaction_sending"),
                    failed: String(localized: "transaction_failed_send"),
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: String(localized: "transaction_moved_amount \(amountText)"),
                        pending: String(localized: "transaction_moving_amount \(amountText)"),
                        failed: String(localized: "transaction_failed_move"),
                        includePrefix: includeStatusPrefix
                    )
                }
                
                if let contact = associatedContacts.first {
                    switch type {
                    case .received:
                        return statusAwareText(
                            confirmed: String(localized: "transaction_from_contact \(contact.cachedName)"),
                            pending: String(localized: "transaction_receiving_from_contact \(contact.cachedName)"),
                            failed: String(localized: "transaction_failed_receive"),
                            includePrefix: includeStatusPrefix
                        )
                    case .sent:
                        return statusAwareText(
                            confirmed: String(localized: "transaction_to_contact \(contact.cachedName)"),
                            pending: String(localized: "transaction_sending_to_contact \(contact.cachedName)"),
                            failed: String(localized: "transaction_failed_send"),
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
                        confirmed: String(localized: "transaction_received"),
                        pending: String(localized: "transaction_receiving"),
                        failed: String(localized: "transaction_failed_receive"),
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_sent"),
                        pending: String(localized: "transaction_sending"),
                        failed: String(localized: "transaction_failed_send"),
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_bitcoin")
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
                    confirmed: String(localized: "transaction_from_contact \(contact.cachedName)"),
                    pending: String(localized: "transaction_receiving_from_contact \(contact.cachedName)"),
                    failed: String(localized: "transaction_failed_receive_from_contact \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: String(localized: "transaction_to_contact \(contact.cachedName)"),
                    pending: String(localized: "transaction_sending_to_contact \(contact.cachedName)"),
                    failed: String(localized: "transaction_failed_send_to_contact \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: String(localized: "transaction_transfer"),
                    pending: String(localized: "transaction_transferring"),
                    failed: String(localized: "transaction_failed_transfer"),
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return String(localized: "transaction_pending")
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
                    confirmed: String(localized: "transaction_detail_savings_to_payments"),
                    pending: String(localized: "transaction_detail_savings_to_payments"),
                    failed: String(localized: "transaction_detail_savings_to_payments"),
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_payments_to_savings"),
                    pending: String(localized: "transaction_detail_payments_to_savings"),
                    failed: String(localized: "transaction_detail_payments_to_savings"),
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_payments_to_savings"),
                    pending: String(localized: "transaction_detail_payments_to_savings"),
                    failed: String(localized: "transaction_detail_payments_to_savings"),
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_refreshed_payments"),
                    pending: String(localized: "transaction_detail_refreshing_payments"),
                    failed: String(localized: "transaction_detail_failed_refreshing_payments"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_from_payments"),
                    pending: String(localized: "transaction_detail_from_payments"),
                    failed: String(localized: "transaction_detail_from_payments"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_to_payments"),
                    pending: String(localized: "transaction_detail_to_payments"),
                    failed: String(localized: "transaction_detail_failed_receive_to_payments"),
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if subsystemName == "bark.offboard" {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_payments_to_savings"),
                        pending: String(localized: "transaction_detail_payments_to_savings"),
                        failed: String(localized: "transaction_detail_payments_to_savings"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_from_savings"),
                    pending: String(localized: "transaction_detail_from_savings"),
                    failed: String(localized: "transaction_detail_from_savings"),
                    includePrefix: includeStatusPrefix
                )
            case .offchainTransfer:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_from_payments"),
                    pending: String(localized: "transaction_detail_from_payments"),
                    failed: String(localized: "transaction_detail_from_payments"),
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_within_savings"),
                        pending: String(localized: "transaction_detail_within_savings"),
                        failed: String(localized: "transaction_detail_failed_move_within_savings"),
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_to_savings"),
                        pending: String(localized: "transaction_detail_to_savings"),
                        failed: String(localized: "transaction_detail_failed_receive"),
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_from_savings"),
                        pending: String(localized: "transaction_detail_from_savings"),
                        failed: String(localized: "transaction_detail_failed_send"),
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_detail_generic")
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
                    confirmed: String(localized: "transaction_detail_received_amount_from \(amountText) \(contact.cachedName)"),
                    pending: String(localized: "transaction_detail_receiving_amount_from \(amountText) \(contact.cachedName)"),
                    failed: String(localized: "transaction_detail_failed_receive_from \(contact.cachedName)"),
                    cancelled: String(localized: "transaction_detail_cancelled_receive_from \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_sent_amount_to \(amountText) \(contact.cachedName)"),
                    pending: String(localized: "transaction_detail_sending_amount_to \(amountText) \(contact.cachedName)"),
                    failed: String(localized: "transaction_detail_failed_send_to \(contact.cachedName)"),
                    cancelled: String(localized: "transaction_detail_cancelled_send_to \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_transfer"),
                    pending: String(localized: "transaction_detail_transferring"),
                    failed: String(localized: "transaction_detail_failed_transfer"),
                    cancelled: String(localized: "transaction_detail_cancelled_transfer"),
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return String(localized: "transaction_pending")
            }
        }
        
        // Fallback to status-aware type display
        return statusAwareTypeDisplayName(includePrefix: includeStatusPrefix)
    }
    
    /// Helper method to return status-aware text
    private func statusAwareText(confirmed: String, pending: String, failed: String, cancelled: String = String(localized: "transaction_cancelled"), includePrefix: Bool) -> String {
        guard includePrefix else {
            return confirmed
        }

        // A cancelled movement is terminal in bark (its VTXOs were consumed by
        // something else, e.g. a refresh), so it wins over the exit-progress
        // check below, which would otherwise report a never-completing "pending".
        if transactionStatus == .cancelled {
            return cancelled
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
        case .cancelled:
            return cancelled
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
                confirmed: String(localized: "transaction_sent"),
                pending: String(localized: "transaction_sending"),
                failed: String(localized: "transaction_failed_send"),
                cancelled: String(localized: "transaction_cancelled_send"),
                includePrefix: includePrefix
            )
        case .received:
            return statusAwareText(
                confirmed: String(localized: "transaction_received"),
                pending: String(localized: "transaction_receiving"),
                failed: String(localized: "transaction_failed_receive"),
                cancelled: String(localized: "transaction_cancelled_receive"),
                includePrefix: includePrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: String(localized: "transaction_move"),
                pending: String(localized: "transaction_moving"),
                failed: String(localized: "transaction_failed_move"),
                cancelled: String(localized: "transaction_cancelled_move"),
                includePrefix: includePrefix
            )
        case .pending:
            return String(localized: "transaction_pending")
        }
    }
    
    /// Returns explanatory text for transaction categories that may not be intuitive to users
    var explainerText: String? {
        guard let category = category else { return nil }
        
        switch category {
        case .refresh:
            return String(localized: "transaction_explainer_refresh")
            
        case .exit:
            return String(localized: "transaction_explainer_exit")
            
        //case .onchainTransaction:
        //    return "This is a native Bitcoin transaction managed by your onchain wallet. These transactions are settled directly on the Bitcoin blockchain."
            
        default:
            return nil
        }
    }
}
