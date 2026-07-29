//
//  ExitProgressionNotifications.swift
//  Arké
//
//  Notification scheduling for exit progression check-ins
//  Created by Claude on 5/12/26.
//

#if os(iOS)
import Foundation
import UserNotifications
import OSLog

/// Manages local notification scheduling for exit progression check-ins
class ExitProgressionNotifications {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitNotifications")

    /// Shared instance for notification management
    static let shared = ExitProgressionNotifications()

    private init() {}
    
    // MARK: - Notification Scheduling
    
    /// Schedule a sequence of check-in reminders at 90-minute intervals
    func scheduleCheckInSequence() async {
        Self.logger.info("📅 [Notifications] Scheduling check-in sequence...")

        // Clear any existing notifications
        await cancelAllCheckInReminders()

        // One global app setting covers push and local reminders alike
        guard UserDefaults.standard.bool(forKey: UserDefaults.notificationsEnabledKey) else {
            Self.logger.notice("⚠️ [Notifications] Disabled in app settings - skipping schedule")
            return
        }

        // Check notification authorization first
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            Self.logger.notice("⚠️ [Notifications] Not authorized - skipping schedule")
            return
        }
        
        // Schedule reminders at 90-minute intervals
        let intervals: [TimeInterval] = [
            90 * 60,      // 1.5 hours
            90 * 60,      // 3.0 hours (cumulative)
            90 * 60,      // 4.5 hours (cumulative)
            90 * 60,      // 6.0 hours (cumulative)
            90 * 60       // 7.5 hours (cumulative)
        ]
        
        var cumulativeTime: TimeInterval = 0
        for (index, interval) in intervals.enumerated() {
            cumulativeTime += interval
            let notificationDate = Date().addingTimeInterval(cumulativeTime)
            
            await scheduleCheckInNotification(
                at: notificationDate,
                checkNumber: index + 1
            )
        }
        
        Self.logger.notice("✅ [Notifications] Scheduled \(intervals.count) check-in reminders")
    }
    
    /// Schedule a single check-in notification
    private func scheduleCheckInNotification(at date: Date, checkNumber: Int) async {
        let id = "exit-check-\(UUID().uuidString)"
        
        let content = UNMutableNotificationContent()
        content.title = "Forced Move Check-In"
        content.body = "Tap to keep your forced move to Savings going."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        
        // Category for potential future interactive notifications
        content.categoryIdentifier = "EXIT_PROGRESS"
        
        // Deep link data for handling the tap
        content.userInfo = [
            "action": "check_exit_progress",
            "checkNumber": checkNumber,
            "scheduledFor": date.timeIntervalSince1970
        ]
        
        // Calculate time interval from now
        let timeInterval = date.timeIntervalSinceNow
        
        // Don't schedule if time is in the past (shouldn't happen, but safety check)
        guard timeInterval > 0 else {
            Self.logger.warning("⚠️ [Notifications] Skipping notification #\(checkNumber) - time is in the past")
            return
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            
            // Format date for logging
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let timeString = formatter.string(from: date)
            
            Self.logger.info("📅 [Notifications] Scheduled check-in #\(checkNumber) for \(timeString, privacy: .public) (\(Int(timeInterval/60)) min from now)")
        } catch {
            Self.logger.error("❌ [Notifications] Failed to schedule notification: \(String(describing: error), privacy: .public)")
        }
    }
    
    // MARK: - Notification Cleanup
    
    /// Cancel all pending check-in reminders
    func cancelAllCheckInReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        
        // Find all exit progress notifications by category
        let exitNotificationIds = pending
            .filter { $0.content.categoryIdentifier == "EXIT_PROGRESS" }
            .map { $0.identifier }
        
        guard !exitNotificationIds.isEmpty else {
            Self.logger.notice("ℹ️ [Notifications] No notifications to cancel")
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: exitNotificationIds)
        Self.logger.notice("🗑️ [Notifications] Cancelled \(exitNotificationIds.count) pending notifications")
    }

    /// Schedule the check-in sequence only if no reminders are already pending.
    /// Covers enable paths that bypass the exit-start flow, like returning from
    /// system Settings after granting permission mid-exit.
    func ensureCheckInSequenceScheduled() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.content.categoryIdentifier == "EXIT_PROGRESS" }) else {
            return
        }
        await scheduleCheckInSequence()
    }
    
    // MARK: - Permission Checking
    
    /// Check if notification permission is granted
    func isAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }
    
    /// Request notification permission if not already granted
    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true

        case .notDetermined:
            // Request permission
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    Self.logger.notice("✅ [Notifications] Permission granted")
                } else {
                    Self.logger.notice("⚠️ [Notifications] Permission denied by user")
                }
                return granted
            } catch {
                Self.logger.error("❌ [Notifications] Permission request failed: \(String(describing: error), privacy: .public)")
                return false
            }

        case .denied:
            Self.logger.notice("⚠️ [Notifications] Permission denied")
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Debug Helpers
    
    /// List all pending notifications (for debugging)
    func listPendingNotifications() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        
        let exitNotifications = requests.filter { request in
            if let action = request.content.userInfo["action"] as? String {
                return action == "check_exit_progress"
            }
            return false
        }
        
        Self.logger.debug("📋 [Notifications] \(exitNotifications.count) pending exit notifications:")
        for request in exitNotifications {
            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                let fireDate = Date().addingTimeInterval(trigger.timeInterval)
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .short
                Self.logger.debug("   • \(request.identifier): \(formatter.string(from: fireDate))")
            }
        }
    }
}

#endif
