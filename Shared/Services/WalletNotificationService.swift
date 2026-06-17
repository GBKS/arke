//
//  WalletNotificationService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 4/7/26.
//

import Foundation
import SwiftUI
import Bark
import OSLog

/// Service responsible for listening to real-time wallet notifications from the Bark SDK
///
/// This service provides instant transaction updates by listening to movement events from
/// the Bark wallet's notification stream. It complements the existing polling-based services
/// by providing real-time responsiveness while the app is in the foreground.
///
/// Architecture:
/// - Listens to `wallet.notifications()` stream in a continuous Task
/// - Converts Movement events to JSON and delegates to TransactionService
/// - Handles three notification types: movementCreated, movementUpdated, channelLagging
/// - Provides fallback to full refresh if notification stream lags
///
/// Lifecycle:
/// - Started when wallet initializes (foreground only)
/// - Stopped when wallet closes or app backgrounds
/// - Auto-reconnects on stream failure (max 5 consecutive errors)
@MainActor
@Observable
class WalletNotificationService {

    // MARK: - Logging

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "WalletNotifications")

    // MARK: - Configuration

    /// Delay before attempting to reconnect after stream failure
    private let reconnectDelay: TimeInterval = 5.0

    /// Maximum number of consecutive errors before stopping the service
    private let maxConsecutiveErrors: Int = 5
    
    /// Interval for health check logging (in seconds)
    private let healthCheckInterval: TimeInterval = 5.0
    
    /// Maximum time without notification before warning (in seconds)
    private let staleStreamThreshold: TimeInterval = 120.0  // 2 minutes

    // MARK: - State

    /// Whether the notification listener is currently running
    private(set) var isRunning: Bool = false

    /// Timestamp of the last notification received
    private(set) var lastNotificationTime: Date?

    /// Last error encountered (for debugging)
    private(set) var lastError: String?

    /// Counter for consecutive errors (resets on successful notification)
    private var consecutiveErrors: Int = 0
    
    /// Timestamp when the service started
    private var serviceStartTime: Date?
    
    /// Health check status for debugging
    private(set) var healthStatus: String = "Not started"

    // MARK: - Dependencies

    private let wallet: BarkWalletProtocol
    private weak var walletManager: WalletManager?
    private weak var transactionService: TransactionService?

    // MARK: - Subscription
    
    /// Callback signature for movement notifications
    typealias MovementCallback = @MainActor (Movement) -> Void
    
    /// Active subscribers (keyed by UUID for easy removal)
    private var movementSubscribers: [UUID: MovementCallback] = [:]

    // MARK: - Streaming

    /// Notification stream holder from Bark SDK
    private var notificationHolder: NotificationHolder?

    /// Background task running the notification listener loop
    private var notificationTask: Task<Void, Never>?
    
    /// Background task running the health check timer
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet
    }

    /// Set the wallet manager reference (needed for triggering refreshes)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }

    /// Set the transaction service reference (needed for processing movements)
    func setTransactionService(_ service: TransactionService) {
        self.transactionService = service
    }
    
    // MARK: - Public Subscription API
    
    /// Subscribe to movement creation events
    /// - Parameter callback: Called on the main actor when a new movement is created
    /// - Returns: Subscription ID (save this to unsubscribe later)
    @MainActor
    func onMovementCreated(_ callback: @escaping MovementCallback) -> UUID {
        let id = UUID()
        movementSubscribers[id] = callback
        logger.debug("Added movement subscriber (ID: \(id.uuidString.prefix(8))...), total subscribers: \(self.movementSubscribers.count)")
        return id
    }
    
    /// Unsubscribe from movement notifications
    /// - Parameter id: The subscription ID returned from onMovementCreated
    @MainActor
    func removeSubscriber(_ id: UUID) {
        movementSubscribers.removeValue(forKey: id)
        logger.debug("Removed movement subscriber (ID: \(id.uuidString.prefix(8))...), remaining subscribers: \(self.movementSubscribers.count)")
    }

    // MARK: - Lifecycle

    /// Start the notification listener
    func start() {
        guard !isRunning else {
            logger.warning("Service already running")
            return
        }

        logger.info("Starting notification listener")
        isRunning = true
        consecutiveErrors = 0
        lastError = nil
        serviceStartTime = Date()
        healthStatus = "Starting..."

        // Get notification holder from wallet
        notificationHolder = wallet.notifications()

        // Start listening task
        notificationTask = Task {
            await listenForNotifications()
        }
        
        // Start health check task
        healthCheckTask = Task {
            await runHealthCheck()
        }
    }

    /// Stop the notification listener
    func stop() {
        guard isRunning else { return }

        logger.info("Stopping notification listener")
        isRunning = false
        healthStatus = "Stopped"

        // Cancel the health check task
        healthCheckTask?.cancel()
        healthCheckTask = nil

        // Cancel the listening task
        notificationTask?.cancel()
        notificationTask = nil

        // Signal the holder to stop waiting (unblocks pending nextNotification call)
        notificationHolder?.cancelNextNotificationWait()
        notificationHolder = nil
    }

    // MARK: - Core Listening Loop

    /// Main loop that listens for notifications from the Bark SDK
    private func listenForNotifications() async {
        while isRunning {
            // Check for task cancellation
            if Task.isCancelled {
                logger.debug("Task cancelled")
                break
            }

            do {
                guard let holder = notificationHolder else {
                    logger.warning("No notification holder available")
                    break
                }

                // Block until next notification arrives (or cancellation)
                if let notification = try await holder.nextNotification() {
                    await handleNotification(notification)

                    // Reset error count on success
                    consecutiveErrors = 0
                    lastNotificationTime = Date()
                    lastError = nil
                } else {
                    // Stream ended gracefully (nil return)
                    logger.info("Notification stream ended")
                    break
                }

            } catch {
                consecutiveErrors += 1
                let errorMessage = error.localizedDescription
                lastError = errorMessage

                logger.error("Error (\(self.consecutiveErrors)/\(self.maxConsecutiveErrors)): \(errorMessage)")

                // Stop service if too many consecutive errors
                if consecutiveErrors >= maxConsecutiveErrors {
                    logger.error("Too many consecutive errors, stopping service")
                    break
                }

                // Wait before retrying
                logger.info("Waiting \(Int(self.reconnectDelay))s before reconnecting...")
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            }
        }

        logger.info("Listener loop exited")
        isRunning = false
    }

    // MARK: - Notification Handling

    /// Handle an incoming wallet notification
    private func handleNotification(_ notification: WalletNotification) async {
        
        
        switch notification {
        case .movementCreated(let movement):
            logger.info("Movement created: ID \(movement.id)")
            await handleMovementCreated(movement)

        case .movementUpdated(let movement):
            logger.info("Movement updated: ID \(movement.id)")
            await handleMovementUpdated(movement)

        case .channelLagging:
            logger.warning("Channel lagging - triggering full refresh")
            await handleChannelLagging()
            
        @unknown default:
            logger.warning("Unrecognized notification received: \(String(describing: notification))")
        }
    }

    /// Handle a new movement creation notification
    private func handleMovementCreated(_ movement: Movement) async {
        // Convert Movement to JSON string
        let jsonString = convertMovementToJson(movement)

        // Delegate to TransactionService for processing
        await transactionService?.processSingleMovement(json: jsonString)
        
        // Refresh balances to update UI (deduplication prevents redundant API calls)
        await walletManager?.refreshBalances()
        
        // Notify all subscribers of the new movement
        await MainActor.run {
            for callback in movementSubscribers.values {
                callback(movement)
            }
        }
    }

    /// Handle a movement update notification
    private func handleMovementUpdated(_ movement: Movement) async {
        // Same as created - upsert logic in TransactionService handles updates automatically
        let jsonString = convertMovementToJson(movement)
        await transactionService?.processSingleMovement(json: jsonString)
        
        // Refresh balances to update UI (deduplication prevents redundant API calls)
        await walletManager?.refreshBalances()
    }

    /// Handle channel lagging notification (fallback to full refresh)
    private func handleChannelLagging() async {
        // Trigger full refresh of transactions and balances as fallback
        await transactionService?.refreshTransactions()
        await walletManager?.refreshBalances()
    }

    // MARK: - Movement Conversion

    /// Convert a Movement struct from Bark SDK to JSON string
    /// Uses the same conversion approach as getMovements() in BarkWalletFFI
    private func convertMovementToJson(_ movement: Movement) -> String {
        // Build dictionary matching the format expected by TransactionService
        var dict: [String: Any] = [
            "id": movement.id,
            "status": movement.status,
            "subsystem_name": movement.subsystemName,
            "subsystem_kind": movement.subsystemKind,
            "metadata_json": movement.metadataJson,
            "intended_balance_sats": movement.intendedBalanceSats,
            "effective_balance_sats": movement.effectiveBalanceSats,
            "offchain_fee_sats": movement.offchainFeeSats,
            "sent_to_addresses": movement.sentToAddresses,
            "received_on_addresses": movement.receivedOnAddresses,
            "input_vtxo_ids": movement.inputVtxoIds,
            "output_vtxo_ids": movement.outputVtxoIds,
            "exited_vtxo_ids": movement.exitedVtxoIds,
            "created_at": movement.createdAt,
            "updated_at": movement.updatedAt
        ]

        // Only include completed_at if it's not nil
        if let completedAt = movement.completedAt {
            dict["completed_at"] = completedAt
        }

        // Convert to JSON data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])

            // Convert to string
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                logger.error("Failed to encode movement as UTF-8 string")
                return "{}"
            }

        } catch {
            logger.error("Failed to serialize movement to JSON: \(error.localizedDescription)")
            return "{}"
        }
    }
    
    // MARK: - Health Check
    
    /// Periodic health check to detect stale/dead streams
    private func runHealthCheck() async {
        logger.debug("Health check started (every \(Int(self.healthCheckInterval))s)")
        
        while isRunning {
            // Check for task cancellation
            if Task.isCancelled {
                logger.debug("Health check task cancelled")
                break
            }
            
            // Wait for next check interval
            try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
            
            guard isRunning else { break }
            
            // Perform health check
            await performHealthCheck()
        }
        
        logger.debug("Health check stopped")
    }
    
    /// Perform a single health check and log status
    private func performHealthCheck() async {
        let now = Date()
        
        // Check 1: Is the notification task still alive?
        let taskAlive = notificationTask?.isCancelled == false
        
        // Check 2: Do we have a notification holder?
        let hasHolder = notificationHolder != nil
        
        // Check 3: Time since last notification
        let timeSinceLastNotification: TimeInterval?
        if let lastTime = lastNotificationTime {
            timeSinceLastNotification = now.timeIntervalSince(lastTime)
        } else if let startTime = serviceStartTime {
            timeSinceLastNotification = now.timeIntervalSince(startTime)
        } else {
            timeSinceLastNotification = nil
        }
        
        // Determine health status
        var status = "✅ Healthy"
        var warnings: [String] = []
        
        if !taskAlive {
            status = "❌ DEAD - Listener task is not running"
            warnings.append("Task cancelled or stopped")
        }
        
        if !hasHolder {
            status = "⚠️ STALE - No notification holder"
            warnings.append("Notification holder is nil")
        }
        
        if let timeSince = timeSinceLastNotification, timeSince > staleStreamThreshold {
            if status == "✅ Healthy" {
                status = "⏳ IDLE - No activity"
            }
            let minutes = Int(timeSince / 60)
            let seconds = Int(timeSince.truncatingRemainder(dividingBy: 60))
            warnings.append("Idle for \(minutes)m \(seconds)s (may be normal)")
        }
        
        healthStatus = status
        
        // Build status log
        var logParts: [String] = ["[Health Check]", status]
        
        if !taskAlive {
            logParts.append("| Task: DEAD")
        } else {
            logParts.append("| Task: ALIVE")
        }
        
        if hasHolder {
            logParts.append("| Holder: OK")
        } else {
            logParts.append("| Holder: NIL")
        }
        
        if let timeSince = timeSinceLastNotification {
            let minutes = Int(timeSince / 60)
            let seconds = Int(timeSince.truncatingRemainder(dividingBy: 60))
            logParts.append("| Last notif: \(minutes)m \(seconds)s ago")
        } else {
            logParts.append("| Last notif: Never")
        }
        
        if consecutiveErrors > 0 {
            logParts.append("| Errors: \(consecutiveErrors)/\(maxConsecutiveErrors)")
        }
        
        if let error = lastError {
            logParts.append("| Last error: \(error)")
        }
        
        // Add warnings
        if !warnings.isEmpty {
            logParts.append("| ⚠️ \(warnings.joined(separator: ", "))")
        }
        
        logger.debug("\(logParts.joined(separator: " "))")
        
        // If stream appears dead/stale, we could potentially restart it here
        // For now, just log the issue for debugging
        if status.contains("DEAD") || status.contains("STALE") {
            logger.warning("Stream may need restart - consider stopping and restarting service")
        }
    }
}
