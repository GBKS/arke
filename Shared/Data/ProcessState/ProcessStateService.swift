//
//  ProcessStateService.swift
//  Ark wallet prototype
//
//  Created by Christoph on 1/6/26.
//

import Foundation
import SwiftData
import ArkeUI

/// Service for tracking ongoing processes and wallet health states
@MainActor
@Observable
final class ProcessStateService {
    
    // MARK: - Dependencies
    private var modelContext: ModelContext?
    
    // MARK: - State Properties
    
    /// VTXO health status
    private(set) var vtxoHealth: VTXOHealth = VTXOHealth()
    
    /// Connection status
    private(set) var connectionStatus: ConnectionStatus = ConnectionStatus()
    
    /// Backup status (loaded from persistence)
    private(set) var backupStatus: BackupStatus?
    
    /// Current block height (cached from last update)
    private(set) var currentBlockHeight: Int = 0
    
    /// Error state
    private(set) var error: String?
    
    // MARK: - Initialization
    
    init() {
        // Service initializes empty, will be populated via setModelContext and refresh calls
    }
    
    // MARK: - ModelContext Management
    
    /// Set the ModelContext for SwiftData operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadPersistedData()
    }
    
    /// Load persisted data from SwiftData
    private func loadPersistedData() {
        guard let context = modelContext else { return }
        
        // Load or create backup status (singleton)
        do {
            let backupDescriptor = FetchDescriptor<BackupStatus>()
            let backupStatuses = try context.fetch(backupDescriptor)
            
            if let existing = backupStatuses.first {
                self.backupStatus = existing
            } else {
                // Create initial backup status
                let newBackupStatus = BackupStatus()
                context.insert(newBackupStatus)
                self.backupStatus = newBackupStatus
                try context.save()
            }
        } catch {
            self.error = "Failed to load backup status: \(error.localizedDescription)"
            print("❌ ProcessStateService: Failed to load backup status: \(error)")
        }
    }
    
    // MARK: - Refresh Methods
    
    /// Refresh all state (called after wallet refresh)
    func refreshAll(
        vtxos: [VTXOModel],
        blockHeight: Int,
        isConnected: Bool,
        connectionError: String? = nil
    ) {
        self.currentBlockHeight = blockHeight
        
        refreshVTXOHealth(vtxos: vtxos, blockHeight: blockHeight)
        updateConnectionStatus(connected: isConnected, error: connectionError)
    }
    
    /// Refresh VTXO health status
    func refreshVTXOHealth(vtxos: [VTXOModel], blockHeight: Int, thresholdBlocks: Int = 144) {
        self.currentBlockHeight = blockHeight
        self.vtxoHealth = VTXOHealth.calculate(
            from: vtxos,
            currentBlockHeight: blockHeight,
            expiryThresholdBlocks: thresholdBlocks
        )
    }
    
    /// Update connection status
    func updateConnectionStatus(connected: Bool, quality: ConnectionQuality? = nil, error: String? = nil) {
        if connected {
            if let quality = quality {
                connectionStatus.markConnected(quality: quality)
            } else {
                // Determine quality from last sync
                connectionStatus.markConnected(quality: .excellent)
            }
        } else {
            connectionStatus.markDisconnected(error: error)
        }
    }

    /// Update read-only mode status
    func updateReadOnlyMode(isReadOnly: Bool, reason: ReadOnlyReason? = nil) {
        connectionStatus.isReadOnlyMode = isReadOnly
        connectionStatus.readOnlyReason = isReadOnly ? reason : nil
    }
    
    
    // MARK: - Backup Status Management
    
    /// Check if backup reminder should be shown
    var shouldShowBackupReminder: Bool {
        backupStatus?.shouldShowReminder() ?? false
    }
    
    /// Confirm that wallet has been backed up
    func confirmBackup() throws {
        guard let context = modelContext else {
            throw ProcessStateError.noModelContext
        }
        
        guard let status = backupStatus else {
            throw ProcessStateError.backupStatusNotFound
        }
        
        status.confirmBackup()
        try context.save()
        
        print("✅ ProcessStateService: Backup confirmed")
    }
    
    /// Increment transaction count (call after each transaction)
    func incrementBackupTransactionCount() {
        guard let context = modelContext else { return }
        
        backupStatus?.incrementTransactionCount()
        
        do {
            try context.save()
        } catch {
            print("⚠️ ProcessStateService: Failed to update transaction count: \(error)")
        }
    }
    
    /// Snooze backup reminder
    func snoozeBackupReminder() throws {
        guard let context = modelContext else {
            throw ProcessStateError.noModelContext
        }
        
        guard let status = backupStatus else {
            throw ProcessStateError.backupStatusNotFound
        }
        
        status.snoozeReminder()
        try context.save()
        
        print("💤 ProcessStateService: Backup reminder snoozed")
    }
    
    /// Dismiss backup reminder
    func dismissBackupReminder() throws {
        guard let context = modelContext else {
            throw ProcessStateError.noModelContext
        }
        
        guard let status = backupStatus else {
            throw ProcessStateError.backupStatusNotFound
        }
        
        status.dismissReminder()
        status.markReminderShown()
        try context.save()
        
        print("✋ ProcessStateService: Backup reminder dismissed")
    }
    
    // MARK: - Computed Properties
    
    /// Check if any state needs user attention
    var needsAttention: Bool {
        return vtxoHealth.needsAttention || 
               shouldShowBackupReminder ||
               connectionStatus.showWarning
    }
}

// MARK: - Errors

enum ProcessStateError: LocalizedError {
    case noModelContext
    case backupStatusNotFound
    
    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "Database context not available"
        case .backupStatusNotFound:
            return "Backup status not found"
        }
    }
}
