//
//  ExitVtxo+Extensions.swift
//  Ark wallet prototype
//
//  Created by Christoph on 1/9/26.
//

import Foundation
import SwiftUI
import Bark
import ArkeUI

// MARK: - ExitState Display

extension Bark.ExitState {

    /// User-friendly display name, shared by ExitVtxo and
    /// ExitTransactionStatus (bark reports the same state through both)
    var displayName: String {
        switch self {
        case .start:
            return String(localized: "status_starting", defaultValue: "Starting")
        case .processing:
            return L10n.dataProcessing
        case .awaitingDelta:
            return L10n.dataProcessing
        case .claimable:
            return String(localized: "status_ready_to_withdraw", defaultValue: "Ready to withdraw")
        case .claimInProgress:
            return String(localized: "status_withdrawing", defaultValue: "Withdrawing")
        case .claimed:
            return String(localized: "status_complete", defaultValue: "Complete")
        case .vtxoAlreadySpent, .canceled:
            return L10n.transactionCancelled
        }
    }
}

// MARK: - ExitVtxo UI Helpers

extension ExitVtxo: @retroactive Identifiable {
    public var id: String { vtxoId }
}

extension ExitVtxo {
    
    // MARK: - Formatting
    
    /// Formatted amount for display
    var formattedAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(amountSats))
    }
    
    /// Short VTXO ID for display (first 8 + last 4 characters)
    var shortVtxoId: String {
        if vtxoId.count > 12 {
            return String(vtxoId.prefix(8)) + L10n.symbolEllipsis + String(vtxoId.suffix(4))
        }
        return vtxoId
    }
    
    // MARK: - State Display

    /// User-friendly display name for the current state
    var stateDisplayName: String {
        state.displayName
    }

    /// Check if this exit is complete (claimed)
    var isClaimed: Bool {
        if case .claimed = state { return true }
        return false
    }

    /// Check if this exit is active (not yet claimed)
    /// Note: cancelled exits (VtxoAlreadySpent) count as active here; use
    /// `isInFlight` when you need "still has work to do"
    var isActive: Bool {
        return !isClaimed
    }

    /// Check if this exit was cancelled because the VTXO was spent elsewhere
    /// (e.g. a refresh won the race before the exit chain broadcast)
    var isCancelled: Bool {
        if case .vtxoAlreadySpent = state { return true }
        return false
    }

    /// Check if this exit still has work to do: neither claimed nor cancelled.
    /// Terminal exits stay in bark's exit list forever, so `isActive` alone
    /// misclassifies cancelled ones.
    var isInFlight: Bool {
        return !isClaimed && !isCancelled
    }

    /// Check if claim is in progress (transaction broadcast but not confirmed)
    var isClaimInProgress: Bool {
        if case .claimInProgress = state { return true }
        return false
    }

    // MARK: - Block Height Calculations
    
    /// Calculate blocks remaining until claimable
    /// - Parameters:
    ///   - currentHeight: Current blockchain height
    ///   - claimableHeight: Height when this exit becomes claimable
    /// - Returns: Number of blocks remaining (0 if already claimable)
    func blocksRemaining(currentHeight: Int, claimableHeight: Int) -> Int {
        if isClaimable {
            return 0
        }
        let remaining = claimableHeight - currentHeight
        return max(0, remaining)
    }
    
    /// Check if the exit has matured based on current block height
    /// - Parameters:
    ///   - currentHeight: Current blockchain height
    ///   - claimableHeight: Height when this exit becomes claimable
    /// - Returns: True if matured (at or past claimable height)
    func hasMatured(currentHeight: Int, claimableHeight: Int) -> Bool {
        return currentHeight >= claimableHeight || isClaimable
    }
    
    /// Estimated time remaining until claimable (assumes ~10 min per block)
    /// - Parameters:
    ///   - currentHeight: Current blockchain height
    ///   - claimableHeight: Height when this exit becomes claimable
    /// - Returns: Time interval in seconds
    func estimatedTimeRemaining(currentHeight: Int, claimableHeight: Int) -> TimeInterval {
        let blocks = blocksRemaining(currentHeight: currentHeight, claimableHeight: claimableHeight)
        return TimeInterval(blocks * 10 * 60) // blocks * 10 minutes * 60 seconds
    }
    
    /// Formatted time remaining string
    /// - Parameters:
    ///   - currentHeight: Current blockchain height
    ///   - claimableHeight: Height when this exit becomes claimable
    /// - Returns: Human-readable time string (e.g., "~2 hours", "~3 days")
    func formattedTimeRemaining(currentHeight: Int, claimableHeight: Int) -> String {
        if isClaimable {
            return String(localized: "status_ready", defaultValue: "Ready")
        }
        
        let timeInterval = estimatedTimeRemaining(currentHeight: currentHeight, claimableHeight: claimableHeight)
        
        if timeInterval <= 0 {
            return String(localized: "status_ready", defaultValue: "Ready")
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            return String(localized: "format_approx_days \(days)")
        } else if hours > 0 {
            return String(localized: "format_approx_hours \(hours)")
        } else {
            return String(localized: "format_approx_minutes \(minutes)")
        }
    }
}

// MARK: - ExitTransactionStatus Helpers

extension ExitTransactionStatus {

    /// User-friendly display name for the current state
    var stateDisplayName: String {
        state.displayName
    }

    /// Check if this exit is in a claimable state
    var isClaimable: Bool {
        if case .claimable = state { return true }
        return false
    }

    /// Check if this exit is complete (claimed)
    var isClaimed: Bool {
        if case .claimed = state { return true }
        return false
    }

    /// Check if claim is in progress (transaction broadcast but not confirmed)
    var isClaimInProgress: Bool {
        if case .claimInProgress = state { return true }
        return false
    }

    /// Check if this exit is active (not yet claimed)
    var isActive: Bool {
        return !isClaimed
    }
}
