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
/// Phase 1 scope: the `cash.arke.refresh` BGAppRefreshTask with a log-only
/// handler that reschedules itself — the field data instrument for how often
/// iOS grants us background time. Relay auth work plugs into the handler
/// next; `cash.arke.maintenance` (BGProcessingTask) is declared in Info.plist
/// but gets no handler until exit progression moves here (Phase 4).
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

        // Reschedule before doing anything else — a missed or expired run
        // must never end the wake chain.
        scheduleRefresh()

        task.expirationHandler = {
            Self.logger.warning("⏳ BGAppRefreshTask expired before completion")
            task.setTaskCompleted(success: false)
        }

        // Phase 1 step 3 skeleton: no wallet work yet. The relay auth refresh
        // plugs in here next (RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md).
        Self.logger.notice("✅ BGAppRefreshTask pass complete (skeleton — no work performed)")
        task.setTaskCompleted(success: true)
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
