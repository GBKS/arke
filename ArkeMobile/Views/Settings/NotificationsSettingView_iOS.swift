//
//  NotificationsSettingView_iOS.swift
//  Ark wallet prototype
//
//  Settings sub-page explaining why notifications matter for wallet
//  security, with the toggle that enables them.
//

import SwiftUI
import UserNotifications
import ArkeUI

struct NotificationsSettingView_iOS: View {
    @Environment(WalletManager.self) private var manager

    @AppStorage(UserDefaults.notificationsEnabledKey)
    private var notificationsEnabled: Bool = false

    @State private var showNotificationError: Bool = false
    @State private var notificationErrorMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                headerView

                VStack(alignment: .leading, spacing: 20) {
                    Text("settings_notifications")
                        .font(.system(.title, design: .serif))
                    

                    Toggle(isOn: $notificationsEnabled) {
                        Text(String(localized: "settings_notifications_toggle", defaultValue: "Enable notifications"))
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    }
                    .onChange(of: notificationsEnabled) { oldValue, newValue in
                        if newValue {
                            Task {
                                await registerForNotifications()
                            }
                        } else {
                            Task {
                                await unregisterFromNotifications()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "settings_notifications_explainer_intro", defaultValue: "There are several time-sensitive activities:"))
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            bulletRow(String(localized: "settings_notifications_explainer_item_receive", defaultValue: "Receiving payments"))
                            bulletRow(String(localized: "settings_notifications_explainer_item_refresh", defaultValue: "Refreshing your payments balance"))
                            bulletRow(String(localized: "settings_notifications_explainer_item_exit", defaultValue: "Force moving funds to savings"))
                        }
                        
                        Text(String(localized: "settings_notifications_explainer_outro", defaultValue: "Arké can only remind you of these when notifications are enabled."))
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .alert("notification_error_title", isPresented: $showNotificationError) {
            Button("button_ok", role: .cancel) { }
        } message: {
            Text(notificationErrorMessage)
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
            Text(text)
        }
        .font(.body)
        .lineSpacing(6)
        .foregroundColor(.secondary)
    }

    private var headerView: some View {
        Image("settings-notification-header")
            .resizable()
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(25)
    }

    // MARK: - Notification Management

    private func registerForNotifications() async {
        do {
            // Request notification permission
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }

                // Wait a moment for token to be received
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Register with relay
                await manager.registerForPushNotifications()

                // One global setting: restore exit check-in reminders
                // if a forced move is underway
                if let exits = try? await manager.getExitVtxos(), exits.contains(where: { $0.isActive }) {
                    await ExitProgressionNotifications.shared.scheduleCheckInSequence()
                }

                print("✅ Successfully registered for notifications")
            } else {
                // User denied permission
                await MainActor.run {
                    notificationsEnabled = false
                    notificationErrorMessage = String(localized: "notification_error_permission_denied", defaultValue: "Notification permission denied. Please enable in Settings.")
                    showNotificationError = true
                }
            }
        } catch {
            // Error requesting permission
            await MainActor.run {
                notificationsEnabled = false
                notificationErrorMessage = String(localized: "notification_error_registration_failed", defaultValue: "Failed to register: \(error.localizedDescription)")
                showNotificationError = true
            }
        }
    }

    private func unregisterFromNotifications() async {
        await manager.unregisterFromPushNotifications()
        // One global setting: silence exit check-in reminders too
        await ExitProgressionNotifications.shared.cancelAllCheckInReminders()
    }
}
