//
//  BackgroundTaskCoordinator.swift
//  Arké
//
//  Created by Christoph on 7/27/26.
//

#if os(iOS)
import Foundation
import BackgroundTasks
import OSLog

/// Owns the app's BGTaskScheduler plumbing: identifier registration, wake
/// handling, and (re)scheduling. All background wake sources funnel through
/// here so services keep owning "what" while this coordinator owns "when"
/// (Background_Execution.md, Architecture).
///
/// Phase 1 scope: the `cash.arke.refresh` BGAppRefreshTask runs the relay
/// auth refresh (RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md) and always
/// reschedules itself — the wake/timing lines double as field data for how
/// often iOS grants us background time. `cash.arke.maintenance`
/// (BGProcessingTask) is declared in Info.plist but gets no handler until
/// exit progression moves here (Phase 4).
final class BackgroundTaskCoordinator: Sendable {

    // MARK: - Logging

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "BackgroundTask")

    // MARK: - Identifiers

    /// Short passes (relay auth, delegated refresh kickoff, lightning claim
    /// check). Must match Info.plist's BGTaskSchedulerPermittedIdentifiers.
    static let refreshTaskIdentifier = "cash.arke.refresh"

    /// Heavy passes (exit progression/claim, full sync) — declared in
    /// Info.plist now so Phase 4 needs no plist change; no handler yet.
    static let maintenanceTaskIdentifier = "cash.arke.maintenance"

    static let shared = BackgroundTaskCoordinator()

    /// The wallet manager background passes run against. Set once during app
    /// init (before any BGTask can fire); weak because the App owns the
    /// manager's lifecycle.
    @MainActor static weak var walletManager: WalletManager?

    private init() {}

    // MARK: - Registration

    /// Registers the launch handlers. Must be called before
    /// `application(_:didFinishLaunchingWithOptions:)` returns — the API
    /// silently ignores later registrations.
    func registerTasks() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            // The scheduler invokes this on a background queue; BGTask
            // bookkeeping happens there, wallet work (later phases) hops to
            // the main actor.
            guard let refreshTask = task as? BGAppRefreshTask else {
                Self.logger.error("❌ \(Self.refreshTaskIdentifier) launched with unexpected task type \(type(of: task))")
                task.setTaskCompleted(success: false)
                return
            }
            Self.shared.handleRefreshTask(refreshTask)
        }

        if registered {
            Self.logger.info("✅ Registered BGTask handler for \(Self.refreshTaskIdentifier)")
        } else {
            Self.logger.error("❌ Failed to register BGTask handler for \(Self.refreshTaskIdentifier) — identifier missing from Info.plist or registered after launch")
        }
    }

    // MARK: - Refresh Task Handling

    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        // Per-wake-source field data line (Background_Execution.md, Phase 1)
        Self.logger.notice("⏰ Woke via BGAppRefreshTask (\(Self.refreshTaskIdentifier, privacy: .public))")

        // Chain-preserving reschedule before any work — a crashed or expired
        // run must never end the wake cycle. Replaced with the accurate
        // deadline below once the pass finishes (submit = replace semantics).
        scheduleRefresh()

        let started = Date()
        let work = Task { @MainActor () -> Bool in
            guard let manager = Self.walletManager else {
                Self.logger.warning("⚠️ No WalletManager wired to coordinator — skipping pass")
                return false
            }
            return await manager.refreshRelayAuthInBackground()
        }

        // Cancel cleanly if iOS revokes the window mid-request; cancellation
        // propagates into URLSession, and the awaiting completion block below
        // still runs and reports + reschedules. Single owner of
        // setTaskCompleted: the completion block, never this handler.
        task.expirationHandler = {
            Self.logger.warning("⏳ BGAppRefreshTask expired — cancelling in-flight relay auth refresh")
            work.cancel()
        }

        Task {
            let success = await work.value

            // Re-submit with the real deadline now that registration state is
            // fresh (registerDevice's success path also submits — a harmless
            // double-replace with the same date)
            if let deadline = await MainActor.run(body: { Self.walletManager?.relayAuthNextRefreshDate }) {
                self.scheduleRefresh(earliestBeginDate: deadline)
            }

            // Pass-complete field data line (Background_Execution.md, Phase 1)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
            Self.logger.notice("✅ BGAppRefreshTask relay auth pass complete (success: \(success), \(elapsed, privacy: .public)s)")
            task.setTaskCompleted(success: success)
        }
    }

    // MARK: - Scheduling

    /// Submits (replacing any pending request — one per identifier) the next
    /// app-refresh wake. Pass nil to let iOS pick the time entirely from its
    /// own budget; later phases pass a computed deadline (auth expiry, next
    /// refresh blockheight).
    func scheduleRefresh(earliestBeginDate: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate

        do {
            try BGTaskScheduler.shared.submit(request)
            let when = earliestBeginDate.map { "\($0)" } ?? "at scheduler's discretion"
            Self.logger.info("📅 Scheduled \(Self.refreshTaskIdentifier) (earliest: \(when, privacy: .public))")
        } catch BGTaskScheduler.Error.unavailable {
            // Expected on simulator and for app extensions — not an error in
            // the field
            Self.logger.info("ℹ️ BGTaskScheduler unavailable (simulator?) — refresh not scheduled")
        } catch {
            Self.logger.error("❌ Failed to schedule \(Self.refreshTaskIdentifier): \(error)")
        }
    }

    /// Cancels any pending refresh request (e.g. on wallet deletion).
    func cancelRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
        Self.logger.info("🗑️ Cancelled pending \(Self.refreshTaskIdentifier) request")
    }
}
#endif
