//
//  RoundProgressionService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 2/5/26.
//

import Foundation
import SwiftUI
import Bark
import OSLog

/// Service responsible for automatically progressing pending rounds in the background
///
/// This service runs a timer that periodically checks for pending rounds and progresses them
/// through their state machine. Rounds are short-lived operations (seconds to minutes) that
/// handle ARK protocol transactions like sends and receives.
///
/// Round Flow:
/// 1. User initiates send/receive → SDK creates pending round
/// 2. Service auto-progresses: Pending → Completed (automatic, fast)
/// 3. Balances update once round completes
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every 15 seconds (much faster than exits)
/// - SDK-driven: No complex state tracking, just polls SDK
/// - Silent failures: Logs errors but doesn't interrupt user
/// - Debounced: Prevents overlapping checks with isChecking flag
@MainActor
@Observable
class RoundProgressionService {

    // MARK: - Logging

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "RoundProgression")

    // MARK: - Configuration

    /// How often to check for round progression (in seconds)
    /// Reduced from 15s to 60s - WalletNotificationService provides real-time updates
    /// This serves as a fallback safety net in case notifications lag
    private let checkInterval: TimeInterval = 60

    // MARK: - State

    /// Whether the service is currently running
    private(set) var isRunning: Bool = false

    /// Whether a check is currently in progress (prevents overlapping checks)
    private var isChecking: Bool = false

    /// Last time rounds were checked/progressed
    private(set) var lastCheckTime: Date?

    /// Last error encountered (for debugging)
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let wallet: BarkWalletProtocol
    private weak var walletManager: WalletManager?

    // MARK: - Timer

    private var timer: Timer?

    // MARK: - Initialization

    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet
    }

    /// Set the wallet manager reference (needed for cache invalidation)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }

    // MARK: - Lifecycle

    /// Start the round progression service
    func start() {
        guard !isRunning else {
            Self.logger.warning("⚠️ Service already running")
            return
        }

        Self.logger.info("▶️ Starting service (check interval: \(Int(self.checkInterval))s)")
        isRunning = true

        // Run initial check immediately
        Task {
            await checkAndProgressRounds()
        }

        // Schedule timer for periodic checks with tolerance for battery optimization
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndProgressRounds()
            }
        }
        timer?.tolerance = 5 // Allow 5 second variance for battery optimization
    }

    /// Stop the round progression service
    func stop() {
        guard isRunning else { return }

        Self.logger.info("⏹️ Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            Self.logger.warning("⚠️ Cannot trigger check - service not running")
            return
        }

        Self.logger.info("🔄 Manual check triggered")
        Task {
            await checkAndProgressRounds()
        }
    }

    // MARK: - Round Progression Logic

    /// Check for pending rounds and progress them if needed
    private func checkAndProgressRounds() async {
        // Prevent overlapping checks
        guard !isChecking else {
            Self.logger.debug("⏭️ Check already in progress, skipping")
            return
        }

        isChecking = true
        defer { isChecking = false }

        let startTime = Date()
        Self.logger.debug("🔍 Starting check")

        do {
            // Step 1: Check for pending rounds
            let pendingRounds = try await wallet.pendingRoundStates()

            if pendingRounds.isEmpty {
                Self.logger.debug("✅ No pending rounds - skipping progression")
                lastCheckTime = Date()
                lastError = nil
                return
            }

            Self.logger.info("📋 Found \(pendingRounds.count) pending round(s) - progressing...")

            // Step 2: Progress all pending rounds
            try await wallet.progressPendingRounds()
            Self.logger.info("✅ Progressed \(pendingRounds.count) round(s)")

            // Step 3: Sync pending board transactions
            try await wallet.syncPendingBoards()
            Self.logger.debug("✅ Synced pending boards")

            // Step 4: Refresh balances and transactions after round completion
            await walletManager?.refreshAfterVTXOChange()
            Self.logger.debug("✅ Refreshed balances and transactions")

            // Success
            lastCheckTime = Date()
            lastError = nil

            let duration = Date().timeIntervalSince(startTime)
            Self.logger.notice("✅ Check completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch {
            // Log error but don't stop the service
            let errorMessage = error.localizedDescription
            Self.logger.error("❌ Error during check: \(errorMessage, privacy: .public)")
            lastError = errorMessage
            lastCheckTime = Date()

            // Continue running despite errors - will retry on next interval
        }
    }

    // MARK: - Manual Operations

    /// Manually progress rounds (exposed for UI triggers like pull-to-refresh)
    func progressRoundsManually() async throws {
        Self.logger.info("🔄 Manual progression requested")

        let pendingRounds = try await wallet.pendingRoundStates()
        guard !pendingRounds.isEmpty else {
            Self.logger.info("ℹ️ No pending rounds to progress")
            return
        }

        try await wallet.progressPendingRounds()
        try await wallet.syncPendingBoards()
        await walletManager?.refreshAfterVTXOChange()

        Self.logger.notice("✅ Manually progressed \(pendingRounds.count, privacy: .public) round(s)")
    }
}
