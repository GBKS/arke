//
//  WalletManager+ProcessState.swift
//  Arké
//
//  Process state management
//  Backup reminders, VTXO health monitoring, connection status, and attention tracking
//

import Foundation
import ArkeUI

extension WalletManager {
    
    // MARK: - Process State Service Access
    
    /// Access to ProcessStateService for advanced operations
    var processStateServiceInstance: ProcessStateService? {
        processStateService
    }
    
    // MARK: - Backup Management
    
    /// Confirm that wallet has been backed up
    /// Clears the backup reminder permanently
    func confirmBackup() throws {
        guard let processStateService = processStateService else {
            throw BarkErrorArke.commandFailed("Process state service not initialized")
        }
        try processStateService.confirmBackup()
    }
    
    /// Snooze the backup reminder
    func snoozeBackupReminder() throws {
        guard let processStateService = processStateService else {
            throw BarkErrorArke.commandFailed("Process state service not initialized")
        }
        try processStateService.snoozeBackupReminder()
    }
    
    /// Dismiss the backup reminder
    func dismissBackupReminder() throws {
        guard let processStateService = processStateService else {
            throw BarkErrorArke.commandFailed("Process state service not initialized")
        }
        try processStateService.dismissBackupReminder()
    }
    
    // MARK: - Process State Properties
    
    /// Get current VTXO health status
    /// Includes expired and expiring VTXO counts
    var vtxoHealth: VTXOHealth {
        processStateService?.vtxoHealth ?? VTXOHealth()
    }
    
    /// Get current connection status to ASP server
    var connectionStatus: ConnectionStatus {
        processStateService?.connectionStatus ?? ConnectionStatus()
    }

    /// Whether the Ark server is believed reachable, for payment routing decisions.
    /// Optimistic until the first sync produces a result: the default status is
    /// "disconnected" only because nothing has been attempted yet, and treating
    /// that as offline would wrongly rule out Lightning destinations at startup.
    var isArkServerReachable: Bool {
        guard let status = processStateService?.connectionStatus else { return true }
        guard status.lastSuccessfulSync != nil || status.lastError != nil else { return true }
        return status.isConnected
    }
    
    /// Get current backup reminder status
    var backupStatus: BackupStatus? {
        processStateService?.backupStatus
    }
    
    /// Check if backup reminder should be shown to user
    var shouldShowBackupReminder: Bool {
        processStateService?.shouldShowBackupReminder ?? false
    }
    
    // MARK: - Attention Tracking
    
    /// Get total count of items requiring user attention
    /// Includes expired VTXOs, claimable exits, and backup reminders
    var attentionItemCount: Int {
        var count = 0
        
        if vtxoHealth.hasExpiredVTXOs {
            count += vtxoHealth.expiredCount
        }
        
        if hasExitsRequiringAction {
            count += exitsRequiringAction.count
        }
        
        if shouldShowBackupReminder {
            count += 1
        }
        
        return count
    }
    
    /// Check if any wallet state needs user attention
    var needsAttention: Bool {
        return vtxoHealth.needsAttention ||
               hasExitsRequiringAction ||
               shouldShowBackupReminder ||
               connectionStatus.showWarning
    }
    
    /// Get human-readable summary of all attention items
    /// Returns nil if no attention items exist
    var attentionSummary: String? {
        var messages: [String] = []
        
        if let vtxoMessage = vtxoHealth.statusMessage {
            messages.append(vtxoMessage)
        }
        
        if hasExitsRequiringAction {
            let count = exitsRequiringAction.count
            messages.append("\(count) exit\(count == 1 ? "" : "s") ready to claim")
        }
        
        if hasActiveUnilateralExits && !hasExitsRequiringAction {
            let count = activeUnilateralExits.count
            messages.append("\(count) active exit\(count == 1 ? "" : "s") in progress")
        }
        
        if shouldShowBackupReminder {
            messages.append("Backup your wallet")
        }
        
        if connectionStatus.showWarning {
            messages.append(connectionStatus.statusMessage)
        }
        
        return messages.isEmpty ? nil : messages.joined(separator: " • ")
    }
}
