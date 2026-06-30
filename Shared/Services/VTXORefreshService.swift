//
//  VTXORefreshService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 4/17/26.
//

import Foundation
import ArkeUI
import SwiftUI
import Bark
import OSLog
import UserNotifications

/// Service responsible for automatically refreshing VTXOs when refreshes are free
/// 
/// This service monitors VTXOs and automatically triggers refreshes when refresh is 
/// completely free (0 sats) according to the server's fee schedule.
///
/// The service can refresh VTXOs at any stage of their lifecycle, including expired VTXOs,
/// as long as they haven't been spent, exited, or locked. This makes it especially valuable
/// for recovering VTXOs when users open the wallet after extended periods of inactivity.
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every hour (much less frequent than round progression)
/// - Fee-driven: Only refreshes when completely free according to fee schedule
/// - Transparent: Logs all automatic refreshes for user visibility
@MainActor
@Observable
class VTXORefreshService {
    
    /// Logger for VTXO refresh service operations
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "VTXORefresh")
    
    // MARK: - Configuration
    
    /// How often to check for VTXOs needing free refresh (in seconds)
    /// Set to 1 hour - VTXOs have long lifespans so frequent checks aren't needed
    private let checkInterval: TimeInterval = 3600 // 1 hour
    
    /// Maximum percentage of VTXO lifespan remaining to trigger auto-refresh
    /// Only auto-refresh VTXOs in their last 10% of life (e.g., last ~3 days for mainnet, last ~2.3 hours for signet)
    ///
    /// NOTE: This threshold exists to prevent continuous refresh loops when the server's fee schedule
    /// has a free refresh window that's longer than the VTXO lifespan (e.g., signet with 1-day VTXOs
    /// but a mainnet fee schedule that makes refreshes free in the last 2 days). This can be removed
    /// if server fee schedules are properly configured for each network's VTXO expiry delta.
    private let maxLifespanPercentForAutoRefresh: Double = 0.10 // 10%
    
    // MARK: - State
    
    /// Whether the service is currently running
    private(set) var isRunning: Bool = false
    
    /// Whether a check is currently in progress (prevents overlapping checks)
    private var isChecking: Bool = false
    
    /// Last time VTXOs were checked for auto-refresh
    private(set) var lastCheckTime: Date?
    
    /// Last time a VTXO was auto-refreshed
    private(set) var lastRefreshTime: Date?
    
    /// Count of VTXOs auto-refreshed in current session
    private(set) var autoRefreshCount: Int = 0
    
    /// Last error encountered (for debugging)
    private(set) var lastError: String?
    
    /// Scheduled notification date (for debugging/display)
    private(set) var scheduledNotificationDate: Date?
    
    /// Notification identifier for VTXO refresh reminders
    private let notificationIdentifier = "com.arke.vtxo.refresh.reminder"
    
    // MARK: - Dependencies
    
    private let wallet: BarkWalletProtocol
    private weak var walletManager: WalletManager?
    
    // MARK: - Timer
    
    private var timer: Timer?
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet
    }
    
    /// Set the wallet manager reference (needed for data access)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }
    
    // MARK: - Lifecycle
    
    /// Start the VTXO auto-refresh service
    func start() {
        guard !isRunning else {
            Self.logger.warning("Service already running")
            return
        }
        
        Self.logger.info("Starting service (check interval: \(Int(self.checkInterval))s)")
        isRunning = true
        
        // Run initial check immediately
        Task {
            await checkAndRefreshVTXOs()
            // Schedule notification based on current VTXO state
            await scheduleNextRefreshNotification()
        }
        
        // Schedule timer for periodic checks with tolerance for battery optimization
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndRefreshVTXOs()
            }
        }
        timer?.tolerance = 60 // Allow 1 minute variance for battery optimization
    }
    
    /// Stop the VTXO auto-refresh service
    func stop() {
        guard isRunning else { return }
        
        Self.logger.info("Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            Self.logger.warning("Cannot trigger check - service not running")
            return
        }
        
        Self.logger.info("Manual check triggered")
        Task {
            await checkAndRefreshVTXOs()
        }
    }
    
    // MARK: - Auto-Refresh Logic
    
    /// Check for VTXOs in the free refresh window and refresh them automatically
    private func checkAndRefreshVTXOs() async {
        // Prevent overlapping checks
        guard !isChecking else {
            Self.logger.debug("Check already in progress, skipping")
            return
        }
        
        isChecking = true
        defer { isChecking = false }
        
        let startTime = Date()
        Self.logger.debug("Starting check at \(startTime)")
        
        do {
            // Step 1: Get current data
            guard let arkInfo = walletManager?.arkInfo,
                  let feeSchedule = arkInfo.feeSchedule,
                  let currentBlockHeight = walletManager?.estimatedBlockHeight else {
                let missingArkInfo = walletManager?.arkInfo == nil
                let missingFeeSchedule = walletManager?.arkInfo?.feeSchedule == nil
                let missingBlockHeight = walletManager?.estimatedBlockHeight == nil
                Self.logger.warning("Missing required data - arkInfo: \(missingArkInfo), feeSchedule: \(missingFeeSchedule), blockHeight: \(missingBlockHeight), skipping")
                lastCheckTime = Date()
                return
            }
            
            // Step 2: Get all VTXOs that could potentially be refreshed
            let vtxos = try await wallet.spendableVtxos()
            
            if vtxos.isEmpty {
                Self.logger.debug("No spendable VTXOs - skipping")
                lastCheckTime = Date()
                return
            }
            
            // Step 3: Find VTXOs eligible for free refresh
            let eligibleVTXOs = findVTXOsForAutoRefresh(
                vtxos: vtxos,
                currentBlockHeight: currentBlockHeight,
                vtxoLifespan: arkInfo.vtxoExpiryDelta,
                feeSchedule: feeSchedule,
                network: arkInfo.network
            )
            
            if eligibleVTXOs.isEmpty {
                Self.logger.debug("No VTXOs eligible for auto-refresh")
                lastCheckTime = Date()
                lastError = nil
                return
            }
            
            Self.logger.info("Found \(eligibleVTXOs.count) VTXO(s) eligible for free refresh")
            for (index, vtxo) in eligibleVTXOs.enumerated() {
                let blocksUntilExpiry = Int(vtxo.expiryHeight) - currentBlockHeight
                let percentRemaining = Double(blocksUntilExpiry) / Double(arkInfo.vtxoExpiryDelta) * 100
                Self.logger.debug("[\(index + 1)] Amount: \(vtxo.amountSats) sats, Expiry: \(blocksUntilExpiry) blocks (\(String(format: "%.1f", percentRemaining))%)")
            }
            
            // Step 3.5: Validate total amount meets minimum threshold
            let totalAmount = eligibleVTXOs.reduce(0) { $0 + $1.amountSats }
            let minimumAmount: UInt64 = 330
            if totalAmount < minimumAmount {
                Self.logger.debug("Total VTXO amount (\(totalAmount) sats) is below minimum (\(minimumAmount) sats) - skipping refresh")
                lastCheckTime = Date()
                lastError = nil
                return
            }
            
            // Step 4: Trigger the delegated refresh with VTXO IDs
            // Using delegated refresh so the app doesn't need to stay online until the round starts
            let vtxoIds = eligibleVTXOs.map { $0.id }
            Self.logger.info("Scheduling automatic delegated refresh for \(vtxoIds.count) VTXO(s)...")
            let roundState = try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
            
            if let roundState = roundState {
                Self.logger.info("Delegated refresh scheduled, Round ID: \(roundState.id)")
            } else {
                Self.logger.info("No refresh scheduled (VTXOs may not need refresh yet)")
            }
            
            // Step 5: Refresh balances and transactions
            await walletManager?.refreshAfterVTXOChange()
            Self.logger.debug("Refreshed balances and transactions")
            
            // Step 6: Schedule notification for next refresh
            await scheduleNextRefreshNotification()
            
            // Success
            lastCheckTime = Date()
            lastRefreshTime = Date()
            autoRefreshCount += 1
            lastError = nil
            
            let duration = Date().timeIntervalSince(startTime)
            Self.logger.info("Auto-refresh completed in \(String(format: "%.2f", duration))s (total session count: \(self.autoRefreshCount))")
            
        } catch {
            // Log error but don't stop the service
            let errorMessage = error.localizedDescription
            Self.logger.error("Error during check: \(errorMessage)")
            lastError = errorMessage
            lastCheckTime = Date()
            
            // Continue running despite errors - will retry on next interval
        }
    }
    
    /// Find VTXOs that should be auto-refreshed
    /// 
    /// Returns VTXOs where:
    /// 1. Refresh is completely free according to the fee schedule, AND
    /// 2. VTXO is in its last 10% of lifespan (signet only - prevents refresh loops)
    /// 
    /// The percentage constraint prevents continuous refresh loops when server fee schedules
    /// have free refresh windows longer than the VTXO lifespan (e.g., signet with 1-day VTXOs
    /// but mainnet fee schedule with 2-day free window).
    /// 
    /// - Parameters:
    ///   - vtxos: All spendable VTXOs (already filtered by SDK to exclude spent/exited/locked)
    ///   - currentBlockHeight: Current blockchain height
    ///   - vtxoLifespan: Total VTXO lifespan in blocks (for fee calculation)
    ///   - feeSchedule: Server fee schedule
    ///   - network: Network name (mainnet, signet, etc.)
    /// - Returns: VTXOs where refresh is free and VTXO is near expiry
    private func findVTXOsForAutoRefresh(
        vtxos: [Vtxo],
        currentBlockHeight: Int,
        vtxoLifespan: Int,
        feeSchedule: FeeSchedule,
        network: String
    ) -> [Vtxo] {
        return vtxos.filter { vtxo in
            let blocksUntilExpiry = Int(vtxo.expiryHeight) - currentBlockHeight
            
            // Constraint 1: Refresh must be completely free (0 sats)
            guard feeSchedule.isFreeRefresh(blocksUntilExpiry: blocksUntilExpiry) else {
                return false
            }
            
            // Constraint 2: For signet only, VTXO must be in its last 10% of lifespan
            // This prevents refresh loops when the fee schedule's free window is longer than VTXO lifespan
            if network.lowercased() == "signet" {
                let percentOfLifeRemaining = Double(blocksUntilExpiry) / Double(vtxoLifespan)
                return percentOfLifeRemaining <= maxLifespanPercentForAutoRefresh
            }
            
            // For mainnet: If it's free, refresh it
            return true
        }
    }
    
    /// Calculate when the next VTXO will enter the free refresh window
    /// 
    /// This finds the block height when the first VTXO will become eligible for free refresh
    /// based on the fee schedule's ppm expiry table. For signet, applies the 10% lifespan
    /// constraint to prevent refresh loops caused by misconfigured fee schedules.
    /// 
    /// The fee schedule works with thresholds:
    /// - Table sorted ascending: [(0, ppm: 0), (288, ppm: 2000), ...]
    /// - When blocksUntilExpiry >= 288 → uses threshold 288 (NOT FREE)
    /// - When blocksUntilExpiry < 288 → uses threshold 0 (FREE if ppm: 0)
    /// - So free window is when blocksUntilExpiry < nextHigherThreshold
    /// 
    /// - Parameters:
    ///   - vtxos: All spendable VTXOs
    ///   - currentBlockHeight: Current blockchain height
    ///   - vtxoLifespan: Total VTXO lifespan in blocks
    ///   - feeSchedule: Server fee schedule
    ///   - network: Network name (mainnet, signet, etc.)
    /// - Returns: Block height when free refresh window opens, or nil if no free window exists
    private func calculateNextFreeRefreshHeight(
        vtxos: [Vtxo],
        currentBlockHeight: Int,
        vtxoLifespan: Int,
        feeSchedule: FeeSchedule,
        network: String
    ) -> Int? {
        // Find the threshold where ppm is 0
        let sortedTable = feeSchedule.refresh.ppmExpiryTable
            .sorted { $0.expiryBlocksThreshold < $1.expiryBlocksThreshold }
        
        guard let freeEntryIndex = sortedTable.firstIndex(where: { $0.ppm == 0 }) else {
            Self.logger.debug("No free refresh window in fee schedule")
            return nil
        }
        
        let freeEntry = sortedTable[freeEntryIndex]
        
        // Find the next higher threshold (when it stops being free)
        // Free window is: freeEntry.threshold <= blocksUntilExpiry < nextThreshold
        let nextThreshold: Int
        if freeEntryIndex + 1 < sortedTable.count {
            nextThreshold = sortedTable[freeEntryIndex + 1].expiryBlocksThreshold
        } else {
            // No higher threshold, free window extends indefinitely upward
            // This shouldn't happen in practice, but handle it
            Self.logger.debug("Free refresh window has no upper bound")
            return nil
        }
        
        Self.logger.debug("Free refresh window: \(freeEntry.expiryBlocksThreshold) to \(nextThreshold - 1) blocks before expiry")
        
        // Find the earliest VTXO that will enter the free refresh window
        let nextHeights = vtxos.compactMap { vtxo -> Int? in
            let expiryHeight = Int(vtxo.expiryHeight)
            
            // VTXO enters free window when: blocksUntilExpiry < nextThreshold
            // Which happens when: (expiryHeight - currentHeight) < nextThreshold
            // Rearranging: currentHeight > expiryHeight - nextThreshold
            // So free window starts when currentHeight reaches: expiryHeight - (nextThreshold - 1)
            // (at that point, blocksUntilExpiry = nextThreshold - 1, which is < nextThreshold)
            let freeWindowStartHeight = expiryHeight - (nextThreshold - 1)
            
            // For signet: also apply the 10% lifespan constraint to prevent refresh loops
            // For mainnet: use the free window start directly
            if network.lowercased() == "signet" {
                let tenPercentBeforeExpiry = expiryHeight - Int(Double(vtxoLifespan) * maxLifespanPercentForAutoRefresh)
                // Use whichever comes later (more conservative)
                return max(freeWindowStartHeight, tenPercentBeforeExpiry)
            } else {
                return freeWindowStartHeight
            }
        }
        
        // Return the earliest height among all VTXOs (when the first one enters the window)
        guard let earliestHeight = nextHeights.min() else {
            Self.logger.debug("No VTXOs found for free refresh calculation")
            return nil
        }
        
        // Only return if it's in the future
        guard earliestHeight > currentBlockHeight else {
            Self.logger.debug("Free refresh window already open (height \(earliestHeight) <= current \(currentBlockHeight))")
            return nil
        }
        
        return earliestHeight
    }
    
    // MARK: - Manual Refresh (for UI triggers)
    
    /// Manually refresh VTXOs (exposed for UI triggers)
    /// This bypasses the auto-refresh logic and always refreshes all VTXOs that need it
    /// Uses delegated refresh so the app doesn't need to stay online until the round starts
    func refreshManually() async throws {
        Self.logger.info("Manual refresh requested")
        
        // Get VTXOs that need refresh
        let vtxos = try await wallet.getVtxosToRefresh()
        
        if !vtxos.isEmpty {
            let vtxoIds = vtxos.map { $0.id }
            let roundState = try await wallet.refreshVtxosDelegated(vtxoIds: vtxoIds)
            
            if let roundState = roundState {
                Self.logger.info("Manual delegated refresh scheduled for \(vtxoIds.count) VTXO(s), Round ID: \(roundState.id)")
            } else {
                Self.logger.info("No refresh scheduled for \(vtxoIds.count) VTXO(s)")
            }
            
            await walletManager?.refreshAfterVTXOChange()
        } else {
            Self.logger.debug("No VTXOs need refreshing")
        }
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule a local notification to remind user to refresh VTXOs
    /// Called after any operation that changes the VTXO set (send/receive/refresh)
    func scheduleNextRefreshNotification() async {
        do {
            // Cancel any existing scheduled notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            scheduledNotificationDate = nil
            
            // Get required data
            guard let currentHeight = walletManager?.estimatedBlockHeight,
                  let arkInfo = walletManager?.arkInfo,
                  let feeSchedule = arkInfo.feeSchedule else {
                Self.logger.debug("Cannot schedule notification - missing data")
                return
            }
            
            // Get all spendable VTXOs to find the next one needing refresh
            let vtxos = try await wallet.spendableVtxos()
            guard !vtxos.isEmpty else {
                Self.logger.debug("No spendable VTXOs - not scheduling notification")
                return
            }
            
            // Find the VTXO that will enter the free refresh window first
            guard let nextFreeRefreshHeight = calculateNextFreeRefreshHeight(
                vtxos: vtxos,
                currentBlockHeight: currentHeight,
                vtxoLifespan: arkInfo.vtxoExpiryDelta,
                feeSchedule: feeSchedule,
                network: arkInfo.network
            ) else {
                Self.logger.debug("No free refresh window found - not scheduling notification")
                return
            }
            
            // Calculate blocks until free refresh window
            let blocksUntilRefresh = nextFreeRefreshHeight - currentHeight
            
            Self.logger.debug("Blocks until free refresh: \(blocksUntilRefresh), current: \(currentHeight), target: \(nextFreeRefreshHeight)")
            
            // Don't schedule if already in the window or very soon (< 10 blocks ~1.5 hours on mainnet, ~25 min on signet)
            guard blocksUntilRefresh > 10 else {
                Self.logger.debug("Free refresh window starts very soon (\(blocksUntilRefresh) blocks), not scheduling notification")
                return
            }
            
            // Convert to time based on network
            // Mainnet/Bitcoin: ~10 min/block, Signet: ~2.5 min/block
            let secondsPerBlock: Int = (arkInfo.network.lowercased() == "mainnet" || arkInfo.network.lowercased() == "bitcoin") ? 600 : 150
            let secondsUntilRefresh = blocksUntilRefresh * secondsPerBlock
            
            Self.logger.debug("Network: '\(arkInfo.network)', secondsPerBlock: \(secondsPerBlock), secondsUntilRefresh: \(secondsUntilRefresh)")
            
            // Notify when the free refresh window opens
            let notificationDate = Date().addingTimeInterval(TimeInterval(secondsUntilRefresh))
            
            Self.logger.info("Scheduling refresh notification for \(notificationDate) (\(secondsUntilRefresh)s from now, block \(nextFreeRefreshHeight))")
            
            // Request notification authorization
            let center = UNUserNotificationCenter.current()
            let authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            guard authorized else {
                Self.logger.warning("Notification authorization denied")
                return
            }
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification_vtxo_refresh_title", defaultValue: "Time to Refresh")
            content.body = String(localized: "notification_vtxo_refresh_body", defaultValue: "Your wallet needs maintenance to keep your funds fresh. Open the app to refresh.")
            content.sound = .default
            content.categoryIdentifier = "VTXO_REFRESH"
            
            // Schedule notification
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secondsUntilRefresh), repeats: false)
            let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
            
            try await center.add(request)
            scheduledNotificationDate = notificationDate
            
            Self.logger.info("Successfully scheduled notification for \(notificationDate)")
            
        } catch {
            Self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
        }
    }
    
    /// Cancel any pending refresh notifications
    func cancelScheduledNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        scheduledNotificationDate = nil
        Self.logger.debug("Cancelled scheduled notification")
    }
    
    // MARK: - Debug Info
    
    /// Get human-readable status for debugging/display
    var statusDescription: String {
        var parts: [String] = []
        
        parts.append("Running: \(isRunning)")
        
        if let lastCheck = lastCheckTime {
            let elapsed = Date().timeIntervalSince(lastCheck)
            parts.append("Last check: \(String(format: "%.0f", elapsed))s ago")
        } else {
            parts.append("Last check: Never")
        }
        
        if let lastRefresh = lastRefreshTime {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            parts.append("Last refresh: \(String(format: "%.0f", elapsed))s ago")
        }
        
        parts.append("Session refreshes: \(autoRefreshCount)")
        
        if let error = lastError {
            parts.append("Last error: \(error)")
        }
        
        return parts.joined(separator: " | ")
    }
}
