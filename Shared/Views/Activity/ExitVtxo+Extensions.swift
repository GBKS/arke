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

// MARK: - Helper Functions

/// Extract the enum case name from a state description
/// The Bark SDK uses enums with associated values (e.g., "Claimable(ExitClaimableState {...})")
/// This function extracts just the case name (e.g., "Claimable")
private func extractStateCaseName<T>(_ state: T) -> String {
    let stateString = String(describing: state)
    
    // Extract the enum case name (before any parentheses)
    if let parenIndex = stateString.firstIndex(of: "(") {
        return String(stateString[..<parenIndex])
    } else {
        return stateString
    }
}

// MARK: - ExitVtxo UI Helpers

extension ExitVtxo {
    
    // MARK: - Formatting
    
    /// Formatted amount for display
    var formattedAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(amountSats))
    }
    
    /// Short VTXO ID for display (first 8 + last 4 characters)
    var shortVtxoId: String {
        if vtxoId.count > 12 {
            return String(vtxoId.prefix(8)) + String(localized: "symbol_ellipsis") + String(vtxoId.suffix(4))
        }
        return vtxoId
    }
    
    // MARK: - State Display
    
    /// User-friendly display name for the current state
    var stateDisplayName: String {
        // Map Bark SDK state enum to user-friendly names
        let caseName = extractStateCaseName(state)
        
        switch caseName.lowercased() {
        case "start":
            return String(localized: "status_starting")
        case "processing":
            return String(localized: "data_processing")
        case "awaitingdelta":
            return String(localized: "data_processing")
        case "claimable":
            return String(localized: "status_ready_to_withdraw")
        case "claiminprogress":
            return String(localized: "status_withdrawing")
        case "claimed":
            return String(localized: "status_complete")
        default:
            // Return the case name if we don't have a mapping
            return caseName
        }
    }
    
    /// Check if this exit is complete (claimed)
    var isClaimed: Bool {
        let caseName = extractStateCaseName(state)
        return caseName.lowercased() == "claimed"
    }
    
    /// Check if this exit is active (not yet claimed)
    var isActive: Bool {
        return !isClaimed
    }
    
    /// Check if claim is in progress (transaction broadcast but not confirmed)
    var isClaimInProgress: Bool {
        let caseName = extractStateCaseName(state)
        return caseName.lowercased() == "claiminprogress"
    }
    
    /// Icon name (SF Symbol) for the current state
    var stateIcon: String {
        if isClaimable {
            return "repeat"
        }
        
        let caseName = extractStateCaseName(state)
        
        switch caseName.lowercased() {
        case "start", "processing":
            return "repeat"
        case "awaitingdelta":
            return "repeat"
        case "claiminprogress":
            return "repeat"
        case "claimed":
            return "checkmark.circle.fill"
        default:
            return "repeat"
        }
    }
    
    /// Color for the current state
    var stateColor: Color {
        if isClaimable {
            return .Arke.green
        }
        
        let caseName = extractStateCaseName(state)
        
        switch caseName.lowercased() {
        case "claimed":
            return .gray
        case "awaitingdelta":
            return .Arke.blue
        default:
            return .Arke.blue
        }
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
            return String(localized: "status_ready")
        }
        
        let timeInterval = estimatedTimeRemaining(currentHeight: currentHeight, claimableHeight: claimableHeight)
        
        if timeInterval <= 0 {
            return String(localized: "status_ready")
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
        let caseName = extractStateCaseName(state)
        
        switch caseName.lowercased() {
        case "start":
            return String(localized: "status_starting")
        case "processing":
            return String(localized: "data_processing")
        case "awaitingdelta":
            return String(localized: "data_processing")
        case "claimable":
            return String(localized: "status_ready_to_withdraw")
        case "claiminprogress":
            return String(localized: "status_withdrawing")
        case "claimed":
            return String(localized: "status_complete")
        default:
            return caseName
        }
    }
    
    /// Check if this exit is in a claimable state
    var isClaimable: Bool {
        let caseName = extractStateCaseName(state)
        return caseName.lowercased() == "claimable"
    }

    /// Check if this exit is complete (claimed)
    var isClaimed: Bool {
        let caseName = extractStateCaseName(state)
        return caseName.lowercased() == "claimed"
    }
    
    /// Check if this exit is active (not yet claimed)
    var isActive: Bool {
        return !isClaimed
    }
    
    /// Formatted history as a single string
    var formattedHistory: String? {
        guard let history = history, !history.isEmpty else {
            return nil
        }
        return history.joined(separator: " → ")
    }
}
