//
//  SettingsView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct SettingsView_iOS: View {
    let onWalletDeleted: (() -> Void)?
    let onNavigateToActivity: (() -> Void)?
    var onNavigateToBalance: (() -> Void)? = nil
    @Environment(WalletManager.self) private var manager
    @Environment(\.deviceRegistrationService) private var deviceService
    
    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var bitcoinFormat: String = BitcoinAmountFormat.defaultFormat.rawValue
    
    @AppStorage(UserDefaults.balancePrivacyKey)
    private var balancePrivacyEnabled: Bool = false
    
    @AppStorage(UserDefaults.notificationsEnabledKey)
    private var notificationsEnabled: Bool = false
    
    @AppStorage(UserDefaults.proximityPermissionKey)
    private var proximityEnabled: Bool = false
    
    @AppStorage(UserDefaults.showAddressIconsKey)
    private var showAddressIcons: Bool = true

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    @State private var navPath = NavigationPath()
    @State private var defaultAvatarImage: String = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"
    @State private var showNotificationError: Bool = false
    @State private var notificationErrorMessage: String = ""
    
    @Query private var profiles: [UserProfile]
    
    private var userProfile: UserProfile? {
        profiles.first
    }
    
    private var selectedFormat: BitcoinAmountFormat {
        BitcoinAmountFormat(rawValue: bitcoinFormat) ?? .defaultFormat
    }
    
    var body: some View {
        List {
            // Profile Section
            Section {
                NavigationLink(destination: UserProfileSettingView_iOS()) {
                    HStack(spacing: 12) {
                        // Avatar preview
                        if let avatarData = userProfile?.avatarData,
                           let uiImage = UIImage(data: avatarData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                        } else {
                            ZStack {
                                Image(defaultAvatarImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            }
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            //Text("settings_my_profile")
                            //    .font(.callout)
                            
                            if let profile = userProfile, profile.isConfigured {
                                if profile.name.isEmpty {
                                    Text("profile_photo_set")
                                        .font(.title3.weight(.semibold))
                                } else {
                                    Text(profile.name)
                                        .font(.title3.weight(.semibold))
                                }
                            } else {
                                Text("profile_customize_info")
                                    .font(.callout)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // General Section
            Section {
                NavigationLink(destination: DisplaySettingsView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "numbers")
                            .foregroundColor(.Arke.indigo)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings_unit_format")
                                .font(.body)
                            Text(String(localized: "format_currently", defaultValue: "Currently: \(selectedFormat.displayName)"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                // Balance Privacy Toggle
                Toggle(isOn: $balancePrivacyEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: balancePrivacyEnabled ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.Arke.purple)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("action_hide_balance")
                                .font(.body)
                            Text("balance_reveal_hint")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                
                // Notifications (only in primary mode - requires ASP connection)
                if !manager.isReadOnlyMode {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.Arke.orange)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings_notifications")
                                    .font(.body)
                                Text("settings_notifications_hint")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
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
                    .padding(.vertical, 4)
                }
            } header: {
                Text("settings_general")
            }

            // Security Section
            Section {
                if !manager.isReadOnlyMode {
                    NavigationLink(destination: ManualBackupView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.Arke.green)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings_manual_backup")
                                    .font(.body)
                                Text("settings_manual_backup_hint")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Linked Devices
                NavigationLink(destination: LinkedDevicesView_iOS(onNavigateToActivity: onNavigateToActivity)) {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .foregroundColor(.Arke.purple)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings_linked_devices")
                                .font(.body)
                            Text(String(localized: "settings_devices_connected", defaultValue: "\(deviceCount) devices connected"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("settings_security")
            }
            
            // Help & Learning Section
            Section {
                // Intro Video
                NavigationLink(destination: IntroVideoSettingsView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.Arke.purple)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("onboarding_intro_video")
                                .font(.body)
                            Text("settings_learn_how")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("settings_help_learning")
            }

            // Behind the Curtain Section
            Section {
                // Fee Summary
                NavigationLink(destination: FeeSummaryView_iOS()) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.Arke.green)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("activity_fee_summary")
                                .font(.body)
                            Text("action_view_fees")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // ASP-dependent rows (only in primary mode)
                if !manager.isReadOnlyMode {
                    // Server Fee Schedule
                    NavigationLink(destination: FeeScheduleView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundColor(.Arke.teal)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings_fee_schedule")
                                    .font(.body)
                                Text("settings_fee_schedule_hint")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // Address History
                    NavigationLink(destination: AddressHistoryView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(.Arke.blue)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("receive_address_history")
                                    .font(.body)
                                Text("action_view_addresses")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // X-Ray
                    NavigationLink(value: ActivityDestination.data) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile.fill")
                                .foregroundColor(.Arke.teal)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("data_xray_title")
                                    .font(.body)
                                Text("data_wallet_raw")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    /*
                    // Transaction Testing
                    NavigationLink(destination: TransactionTestingView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "testtube.2")
                                .foregroundColor(.Arke.orange)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("nav_title_transaction_testing")
                                    .font(.callout)
                                Text("Developer stress tests")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    */
                
                    /*
                    // Console
                    NavigationLink(destination: ConsoleView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "arcade.stick.console.fill")
                                .foregroundColor(.orange)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("console_title")
                                    .font(.callout)
                                Text("Debug logs and diagnostics")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    */
                }
            } header: {
                Text("data_behind_curtain")
            }

            // Experimental Section
            Section {
                // Proximity Sharing
                Toggle(isOn: $proximityEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.Arke.blue)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings_proximity_sharing")
                                .font(.body)
                            Text("settings_proximity_sharing_hint")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)

                // Address Icons
                Toggle(isOn: $showAddressIcons) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(.Arke.teal)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings_address_patterns")
                                .font(.body)
                            Text("settings_address_patterns_hint")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("settings_experimental")
            }

            // Danger Zone Section (only in primary mode)
            //if !manager.isReadOnlyMode {
                Section {
                    // Exit
                    NavigationLink(destination: ExitView_iOS(onNavigateToBalance: onNavigateToBalance)) {
                        HStack(spacing: 12) {
                            Image(systemName: "light.beacon.max.fill")
                                .foregroundColor(.Arke.orange)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("button_force_move_savings")
                                    .font(.body)
                                Text(manager.hasActiveUnilateralExits ? String(localized: "status_in_progress") : String(localized: "balance_transfer_independently"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .disabled(manager.hasActiveUnilateralExits)
                    .opacity(manager.hasActiveUnilateralExits ? 0.5 : 1.0)

                    // Delete Wallet
                    NavigationLink(destination: DeleteWalletView(onWalletDeleted: onWalletDeleted)) {
                        HStack(spacing: 12) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.Arke.red)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("button_delete_wallet")
                                    .font(.body)
                                    .foregroundColor(.Arke.red)
                                Text("settings_delete_wallet_title")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("settings_danger_zone")
                }
            //}
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("settings_title")
        .navigationBarTitleDisplayMode(.large)
        .alert("notification_error_title", isPresented: $showNotificationError) {
            Button("button_ok", role: .cancel) { }
        } message: {
            Text(notificationErrorMessage)
        }
        .task {
            await deviceService.loadRegisteredDevices()
        }
    }
    
    private var deviceCount: Int {
        deviceService.registeredDevices.filter { $0.isActive && !$0.isStale }.count
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

// MARK: - Supporting Views

struct DeleteWalletView: View {
    let onWalletDeleted: (() -> Void)?
    
    var body: some View {
        DeleteWalletSettingView(onWalletDeleted: onWalletDeleted)
    }
}

struct DisplaySettingsView: View {
    var body: some View {
        BitcoinFormatSettingView_iOS()
            .padding()
    }
}
struct IntroVideoSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var manager
    
    var body: some View {
        IntroVideoView_iOS(
            onBack: { dismiss() },
            onContinue: nil,
            onSkip: nil,
            isMainnet: manager.networkConfig?.isMainnet ?? false
        )
        .navigationBarHidden(true)
    }
}
