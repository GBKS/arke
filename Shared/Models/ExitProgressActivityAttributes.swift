//
//  ExitProgressActivityAttributes.swift
//  Arké
//
//  Live Activity attributes for exit progression
//  Created by Claude on 5/12/26.
//

import ActivityKit
import Foundation

/// Activity attributes for exit progression Live Activity
/// nonisolated: plain data type; ActivityKit uses the conformance from
/// concurrent contexts, so it must not inherit the default MainActor isolation.
nonisolated struct ExitProgressActivityAttributes: ActivityAttributes {
    
    /// Dynamic state that updates during the exit process
    public struct ContentState: Codable, Hashable {
        // Current exit state - using transaction-based progress
        var currentStep: Int  // Current step number (1-based)
        var totalSteps: Int   // Total steps = transactionCount + 4
        var stepDescription: String
        
        // Transaction progress
        var transactionsConfirmed: Int
        var totalTransactions: Int
        
        // Exit state for determining current step
        var exitState: ExitState
        
        // Timing information
        var lastUpdated: Date
        var needsCheckIn: Bool  // Indicates staleness, user should check in
        
        // Block information (optional, for advanced users)
        var currentBlockHeight: UInt32?
        var targetBlockHeight: UInt32?
        var blocksRemaining: Int?
        
        // Status indicators
        var isWaitingForBlocks: Bool
        var isClaimable: Bool
        var isClaimed: Bool
        var hasError: Bool
        var errorMessage: String?
    }
    
    // Static data (doesn't change during the activity)
    var exitId: String  // Primary VTXO ID or exit batch identifier
    var exitCount: Int  // Number of VTXOs being exited (for multiple exits)
    var startTime: Date
}

/// Exit states - matches the parsed states from ExitStatusParser
nonisolated enum ExitState: String, Codable, Hashable {
    case start
    case processing
    case awaitingDelta
    case claimable
    case claimInProgress
    case claimed
    case unparsed
}
