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
                    confirmed: L10n.transactionMoved,
                    pending: L10n.transactionMoving,
                    failed: L10n.transactionFailedMove,
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: String(localized: "transaction_forced_move", defaultValue: "Forced Move"),
                    pending: String(localized: "transaction_forcing_move", defaultValue: "Forcing Move"),
                    failed: String(localized: "transaction_failed_forced_move", defaultValue: "Failed forced move"),
                    cancelled: String(localized: "transaction_cancelled_forced_move", defaultValue: "Cancelled Forced Move"),
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: L10n.transactionMoved,
                    pending: L10n.transactionMoving,
                    failed: L10n.transactionFailedMove,
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_refresh", defaultValue: "Refresh"),
                    pending: String(localized: "transaction_refreshing", defaultValue: "Refreshing"),
                    failed: String(localized: "transaction_failed_refresh", defaultValue: "Failed refresh"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: L10n.transactionSent,
                    pending: L10n.transactionSending,
                    failed: L10n.transactionFailedSend,
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: L10n.transactionReceived,
                    pending: L10n.transactionReceiving,
                    failed: L10n.transactionFailedReceive,
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    return statusAwareText(
                        confirmed: L10n.transactionMoved,
                        pending: L10n.transactionMoving,
                        failed: L10n.transactionFailedMove,
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: L10n.transactionSent,
                    pending: L10n.transactionSending,
                    failed: L10n.transactionFailedSend,
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
                        confirmed: L10n.transactionMoved,
                        pending: L10n.transactionMoving,
                        failed: L10n.transactionFailedMove,
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: L10n.transactionReceived,
                        pending: L10n.transactionReceiving,
                        failed: L10n.transactionFailedReceive,
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: L10n.transactionSent,
                        pending: L10n.transactionSending,
                        failed: L10n.transactionFailedSend,
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_generic", defaultValue: "Transaction")
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
                confirmed: L10n.transactionReceived,
                pending: L10n.transactionReceiving,
                failed: L10n.transactionFailedReceive,
                cancelled: String(localized: "transaction_cancelled_receive", defaultValue: "Cancelled receive"),
                includePrefix: includeStatusPrefix
            )
        case .sent:
            return statusAwareText(
                confirmed: L10n.transactionSent,
                pending: L10n.transactionSending,
                failed: L10n.transactionFailedSend,
                cancelled: String(localized: "transaction_cancelled_send", defaultValue: "Cancelled send"),
                includePrefix: includeStatusPrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: String(localized: "transaction_move", defaultValue: "Move"),
                pending: L10n.transactionMoving,
                failed: L10n.transactionFailedMove,
                cancelled: String(localized: "transaction_cancelled_move", defaultValue: "Cancelled move"),
                includePrefix: includeStatusPrefix
            )
        case .pending:
            return L10n.transactionPending
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
                    confirmed: String(localized: "transaction_moved_amount %@", defaultValue: "Moved \(amountText)"),
                    pending: String(localized: "transaction_moving_amount %@", defaultValue: "Moving \(amountText)"),
                    failed: L10n.transactionFailedMove,
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: String(localized: "transaction_force_moved_amount %@", defaultValue: "Force moved \(amountText)"),
                    pending: String(localized: "transaction_force_moving_amount %@", defaultValue: "Force moving \(amountText)"),
                    failed: String(localized: "transaction_failed_forced_move", defaultValue: "Failed forced move"),
                    cancelled: String(localized: "transaction_cancelled_force_move_amount %@", defaultValue: "Cancelled force move of \(amountText)"),
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                let amountText = BitcoinFormatter.shared.formatAmount(amount)
                return statusAwareText(
                    confirmed: String(localized: "transaction_moved_amount %@", defaultValue: "Moved \(amountText)"),
                    pending: String(localized: "transaction_moving_amount %@", defaultValue: "Moving \(amountText)"),
                    failed: L10n.transactionFailedMove,
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_refresh", defaultValue: "Refresh"),
                    pending: String(localized: "transaction_refreshing", defaultValue: "Refreshing"),
                    failed: String(localized: "transaction_failed_refresh", defaultValue: "Failed refresh"),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_to_contact %@", defaultValue: "To \(contact.cachedName)"),
                        pending: String(localized: "transaction_sending_to_contact %@", defaultValue: "Sending to \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_send_to_contact %@", defaultValue: "Failed send to \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: L10n.transactionSent,
                    pending: L10n.transactionSending,
                    failed: L10n.transactionFailedSend,
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_from_contact %@", defaultValue: "From \(contact.cachedName)"),
                        pending: String(localized: "transaction_receiving_from_contact %@", defaultValue: "Receiving from \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_receive_from_contact %@", defaultValue: "Failed receive from \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: L10n.transactionReceived,
                    pending: L10n.transactionReceiving,
                    failed: L10n.transactionFailedReceive,
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if(subsystemName == "bark.offboard") {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: String(localized: "transaction_moved_amount %@", defaultValue: "Moved \(amountText)"),
                        pending: String(localized: "transaction_moving_amount %@", defaultValue: "Moving \(amountText)"),
                        failed: String(localized: "transaction_failed_move_to_savings", defaultValue: "Failed move to savings"),
                        includePrefix: includeStatusPrefix
                    )
                }
                if let contact = associatedContacts.first {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_to_contact %@", defaultValue: "To \(contact.cachedName)"),
                        pending: String(localized: "transaction_sending_to_contact %@", defaultValue: "Sending to \(contact.cachedName)"),
                        failed: String(localized: "transaction_failed_send_to_contact %@", defaultValue: "Failed send to \(contact.cachedName)"),
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: L10n.transactionSent,
                    pending: L10n.transactionSending,
                    failed: L10n.transactionFailedSend,
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    let amountText = BitcoinFormatter.shared.formatAmount(amount)
                    return statusAwareText(
                        confirmed: String(localized: "transaction_moved_amount %@", defaultValue: "Moved \(amountText)"),
                        pending: String(localized: "transaction_moving_amount %@", defaultValue: "Moving \(amountText)"),
                        failed: L10n.transactionFailedMove,
                        includePrefix: includeStatusPrefix
                    )
                }
                
                if let contact = associatedContacts.first {
                    switch type {
                    case .received:
                        return statusAwareText(
                            confirmed: String(localized: "transaction_from_contact %@", defaultValue: "From \(contact.cachedName)"),
                            pending: String(localized: "transaction_receiving_from_contact %@", defaultValue: "Receiving from \(contact.cachedName)"),
                            failed: L10n.transactionFailedReceive,
                            includePrefix: includeStatusPrefix
                        )
                    case .sent:
                        return statusAwareText(
                            confirmed: String(localized: "transaction_to_contact %@", defaultValue: "To \(contact.cachedName)"),
                            pending: String(localized: "transaction_sending_to_contact %@", defaultValue: "Sending to \(contact.cachedName)"),
                            failed: L10n.transactionFailedSend,
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
                        confirmed: L10n.transactionReceived,
                        pending: L10n.transactionReceiving,
                        failed: L10n.transactionFailedReceive,
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: L10n.transactionSent,
                        pending: L10n.transactionSending,
                        failed: L10n.transactionFailedSend,
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_bitcoin", defaultValue: "Bitcoin Transaction")
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
                    confirmed: String(localized: "transaction_from_contact %@", defaultValue: "From \(contact.cachedName)"),
                    pending: String(localized: "transaction_receiving_from_contact %@", defaultValue: "Receiving from \(contact.cachedName)"),
                    failed: String(localized: "transaction_failed_receive_from_contact %@", defaultValue: "Failed receive from \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: String(localized: "transaction_to_contact %@", defaultValue: "To \(contact.cachedName)"),
                    pending: String(localized: "transaction_sending_to_contact %@", defaultValue: "Sending to \(contact.cachedName)"),
                    failed: String(localized: "transaction_failed_send_to_contact %@", defaultValue: "Failed send to \(contact.cachedName)"),
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: String(localized: "transaction_transfer", defaultValue: "Transfer"),
                    pending: String(localized: "transaction_transferring", defaultValue: "Transferring"),
                    failed: String(localized: "transaction_failed_transfer", defaultValue: "Failed transfer"),
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return L10n.transactionPending
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
                    confirmed: L10n.transactionDetailSavingsToPayments,
                    pending: L10n.transactionDetailSavingsToPayments,
                    failed: L10n.transactionDetailSavingsToPayments,
                    includePrefix: includeStatusPrefix
                )
            case .exit:
                return statusAwareText(
                    confirmed: L10n.transactionDetailPaymentsToSavings,
                    pending: L10n.transactionDetailPaymentsToSavings,
                    failed: L10n.transactionDetailPaymentsToSavings,
                    includePrefix: includeStatusPrefix
                )
            case .offboarding:
                return statusAwareText(
                    confirmed: L10n.transactionDetailPaymentsToSavings,
                    pending: L10n.transactionDetailPaymentsToSavings,
                    failed: L10n.transactionDetailPaymentsToSavings,
                    includePrefix: includeStatusPrefix
                )
            case .refresh:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_refreshed_payments", defaultValue: "Refreshed payments balance."),
                    pending: String(localized: "transaction_detail_refreshing_payments", defaultValue: "Refreshing payments balance."),
                    failed: String(localized: "transaction_detail_failed_refreshing_payments", defaultValue: "Failed refreshing payments balance."),
                    includePrefix: includeStatusPrefix
                )
            case .lightningSend:
                return statusAwareText(
                    confirmed: L10n.transactionDetailFromPayments,
                    pending: L10n.transactionDetailFromPayments,
                    failed: L10n.transactionDetailFromPayments,
                    includePrefix: includeStatusPrefix
                )
            case .lightningReceive:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_to_payments", defaultValue: "To payments."),
                    pending: String(localized: "transaction_detail_to_payments", defaultValue: "To payments."),
                    failed: String(localized: "transaction_detail_failed_receive_to_payments", defaultValue: "Failed receive to payments."),
                    includePrefix: includeStatusPrefix
                )
            case .onchainSend:
                if subsystemName == "bark.offboard" {
                    return statusAwareText(
                        confirmed: L10n.transactionDetailPaymentsToSavings,
                        pending: L10n.transactionDetailPaymentsToSavings,
                        failed: L10n.transactionDetailPaymentsToSavings,
                        includePrefix: includeStatusPrefix
                    )
                }
                return statusAwareText(
                    confirmed: L10n.transactionDetailFromSavings,
                    pending: L10n.transactionDetailFromSavings,
                    failed: L10n.transactionDetailFromSavings,
                    includePrefix: includeStatusPrefix
                )
            case .offchainTransfer:
                return statusAwareText(
                    confirmed: L10n.transactionDetailFromPayments,
                    pending: L10n.transactionDetailFromPayments,
                    failed: L10n.transactionDetailFromPayments,
                    includePrefix: includeStatusPrefix
                )
            case .onchainTransaction:
                // Check if this is a self-transfer first
                if isInternalTransfer {
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_within_savings", defaultValue: "Within savings."),
                        pending: String(localized: "transaction_detail_within_savings", defaultValue: "Within savings."),
                        failed: String(localized: "transaction_detail_failed_move_within_savings", defaultValue: "Failed move within savings."),
                        includePrefix: includeStatusPrefix
                    )
                }
                
                switch type {
                case .received:
                    return statusAwareText(
                        confirmed: String(localized: "transaction_detail_to_savings", defaultValue: "To savings."),
                        pending: String(localized: "transaction_detail_to_savings", defaultValue: "To savings."),
                        failed: String(localized: "transaction_detail_failed_receive", defaultValue: "Failed receive."),
                        includePrefix: includeStatusPrefix
                    )
                case .sent:
                    return statusAwareText(
                        confirmed: L10n.transactionDetailFromSavings,
                        pending: L10n.transactionDetailFromSavings,
                        failed: String(localized: "transaction_detail_failed_send", defaultValue: "Failed send."),
                        includePrefix: includeStatusPrefix
                    )
                default:
                    return String(localized: "transaction_detail_generic", defaultValue: "Transaction.")
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
                    confirmed: String(localized: "transaction_detail_received_amount_from %@ %@", defaultValue: "Received \(amountText) from \(contact.cachedName)."),
                    pending: String(localized: "transaction_detail_receiving_amount_from %@ %@", defaultValue: "Receiving \(amountText) from \(contact.cachedName)."),
                    failed: String(localized: "transaction_detail_failed_receive_from %@", defaultValue: "Failed receive from \(contact.cachedName)."),
                    cancelled: String(localized: "transaction_detail_cancelled_receive_from %@", defaultValue: "Cancelled receive from \(contact.cachedName)."),
                    includePrefix: includeStatusPrefix
                )
            case .sent:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_sent_amount_to %@ %@", defaultValue: "Sent \(amountText) to \(contact.cachedName)."),
                    pending: String(localized: "transaction_detail_sending_amount_to %@ %@", defaultValue: "Sending \(amountText) to \(contact.cachedName)."),
                    failed: String(localized: "transaction_detail_failed_send_to %@", defaultValue: "Failed send to \(contact.cachedName)."),
                    cancelled: String(localized: "transaction_detail_cancelled_send_to %@", defaultValue: "Cancelled send to \(contact.cachedName)."),
                    includePrefix: includeStatusPrefix
                )
            case .transfer:
                return statusAwareText(
                    confirmed: String(localized: "transaction_detail_transfer", defaultValue: "Transfer."),
                    pending: String(localized: "transaction_detail_transferring", defaultValue: "Transferring."),
                    failed: String(localized: "transaction_detail_failed_transfer", defaultValue: "Failed transfer."),
                    cancelled: String(localized: "transaction_detail_cancelled_transfer", defaultValue: "Cancelled transfer."),
                    includePrefix: includeStatusPrefix
                )
            case .pending:
                return L10n.transactionPending
            }
        }
        
        // Fallback to status-aware type display
        return statusAwareTypeDisplayName(includePrefix: includeStatusPrefix)
    }
    
    /// Helper method to return status-aware text
    private func statusAwareText(confirmed: String, pending: String, failed: String, cancelled: String = L10n.transactionCancelled, includePrefix: Bool) -> String {
        guard includePrefix else {
            return confirmed
        }

        // A cancelled movement is terminal in bark (its VTXOs were consumed by
        // something else, e.g. a refresh), so it wins over the exit-progress
        // check below, which would otherwise report a never-completing "pending".
        if transactionStatus == .cancelled {
            return cancelled
        }

        // Special case for unilateral exits: only complete when claimed.
        // isExitComplete reads the persisted movement status first (bark marks
        // the movement Successful exactly when the exit reaches Claimed), so
        // completed exits are titled correctly even while the in-memory exit
        // caches are empty or stale. See Exit_Completion_Issues.md.
        if hasUnilateralExit {
            return isExitComplete ? confirmed : pending
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
                confirmed: L10n.transactionSent,
                pending: L10n.transactionSending,
                failed: L10n.transactionFailedSend,
                cancelled: String(localized: "transaction_cancelled_send", defaultValue: "Cancelled send"),
                includePrefix: includePrefix
            )
        case .received:
            return statusAwareText(
                confirmed: L10n.transactionReceived,
                pending: L10n.transactionReceiving,
                failed: L10n.transactionFailedReceive,
                cancelled: String(localized: "transaction_cancelled_receive", defaultValue: "Cancelled receive"),
                includePrefix: includePrefix
            )
        case .transfer:
            return statusAwareText(
                confirmed: String(localized: "transaction_move", defaultValue: "Move"),
                pending: L10n.transactionMoving,
                failed: L10n.transactionFailedMove,
                cancelled: String(localized: "transaction_cancelled_move", defaultValue: "Cancelled move"),
                includePrefix: includePrefix
            )
        case .pending:
            return L10n.transactionPending
        }
    }
    
    /// Returns explanatory text for transaction categories that may not be intuitive to users
    var explainerText: String? {
        guard let category = category else { return nil }
        
        switch category {
        case .refresh:
            return String(localized: "transaction_explainer_refresh", defaultValue: "A refresh is a maintenance operation that extends the lifetime of your payments balance. No bitcoin was sent or received.")
            
        case .exit:
            return String(localized: "transaction_explainer_exit", defaultValue: "A recovery moves bitcoin from your payments balance to your savings balance without the involvement of the server that typically facilitates this.")
            
        //case .onchainTransaction:
        //    return "This is a native Bitcoin transaction managed by your onchain wallet. These transactions are settled directly on the Bitcoin blockchain."
            
        default:
            return nil
        }
    }
}
