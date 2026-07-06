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
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Image(defaultAvatarImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            //Text("settings_my_profile")
                            //    .font(.system(size: 16))
                            
                            if let profile = userProfile, profile.isConfigured {
                                Text(profile.name.isEmpty ? "profile_photo_set" : profile.name)
                                    .font(.system(size: 19, weight: .semibold))
                            } else {
                                Text("profile_customize_info")
                                    .font(.system(size: 16))
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
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_unit_format")
                                .font(.system(size: 16))
                            Text(String(localized: "format_currently", defaultValue: "Currently: \(selectedFormat.displayName)"))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Balance Privacy Toggle
                Toggle(isOn: $balancePrivacyEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: balancePrivacyEnabled ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.Arke.purple)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("action_hide_balance")
                                .font(.system(size: 16))
                            Text("balance_reveal_hint")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                // Notifications (only in primary mode - requires ASP connection)
                if !manager.isReadOnlyMode {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.Arke.orange)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications")
                                    .font(.system(size: 16))
                                Text("Get notified when funds arrive")
                                    .font(.system(size: 13))
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
                Text("General")
            }

            // Security Section
            Section {
                if !manager.isReadOnlyMode {
                    NavigationLink(destination: ManualBackupView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.Arke.green)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manual Backup")
                                    .font(.system(size: 16))
                                Text("Save your wallet offline")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Linked Devices
                NavigationLink(destination: LinkedDevicesView_iOS(onNavigateToActivity: onNavigateToActivity)) {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .foregroundColor(.Arke.purple)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_linked_devices")
                                .font(.system(size: 16))
                            Text("\(deviceCount) \(deviceCount == 1 ? "device" : "devices") connected")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("onboarding_intro_video")
                                .font(.system(size: 16))
                            Text("settings_learn_how")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("activity_fee_summary")
                                .font(.system(size: 16))
                            Text("action_view_fees")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ASP-dependent rows (only in primary mode)
                if !manager.isReadOnlyMode {
                    // Server Fee Schedule
                    NavigationLink(destination: FeeScheduleView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundColor(.Arke.teal)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fee Schedule")
                                    .font(.system(size: 16))
                                Text("Server fee breakdown")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Address History
                    NavigationLink(destination: AddressHistoryView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(.Arke.blue)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("receive_address_history")
                                    .font(.system(size: 16))
                                Text("action_view_addresses")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // X-Ray
                    NavigationLink(value: ActivityDestination.data) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile.fill")
                                .foregroundColor(.Arke.teal)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("data_xray_title")
                                    .font(.system(size: 16))
                                Text("data_wallet_raw")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    /*
                    // Transaction Testing
                    NavigationLink(destination: TransactionTestingView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "testtube.2")
                                .foregroundColor(.Arke.orange)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transaction Testing")
                                    .font(.system(size: 16))
                                Text("Developer stress tests")
                                    .font(.system(size: 13))
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
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("console_title")
                                    .font(.system(size: 16))
                                Text("Debug logs and diagnostics")
                                    .font(.system(size: 13))
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
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_proximity_sharing")
                                .font(.system(size: 16))
                            Text("settings_proximity_sharing_hint")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                // Address Icons
                Toggle(isOn: $showAddressIcons) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(.Arke.teal)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Address Patterns")
                                .font(.system(size: 16))
                            Text("Show unique visual patterns to help identify addresses")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Experimental")
            }

            // Danger Zone Section (only in primary mode)
            //if !manager.isReadOnlyMode {
                Section {
                    // Exit
                    NavigationLink(destination: ExitView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "light.beacon.max.fill")
                                .foregroundColor(.Arke.orange)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("button_force_move_savings")
                                    .font(.system(size: 16))
                                Text(manager.hasActiveUnilateralExits ? String(localized: "status_in_progress") : String(localized: "balance_transfer_independently"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(manager.hasActiveUnilateralExits)
                    .opacity(manager.hasActiveUnilateralExits ? 0.5 : 1.0)

                    // Delete Wallet
                    NavigationLink(destination: DeleteWalletView(onWalletDeleted: onWalletDeleted)) {
                        HStack(spacing: 12) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.Arke.red)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("button_delete_wallet")
                                    .font(.system(size: 16))
                                    .foregroundColor(.Arke.red)
                                Text("settings_delete_wallet_title")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("settings_danger_zone")
                }
            //}
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("settings_title")
        .navigationBarTitleDisplayMode(.large)
        .alert("Notification Error", isPresented: $showNotificationError) {
            Button("OK", role: .cancel) { }
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
                
                print("✅ Successfully registered for notifications")
            } else {
                // User denied permission
                await MainActor.run {
                    notificationsEnabled = false
                    notificationErrorMessage = "Notification permission denied. Please enable in Settings."
                    showNotificationError = true
                }
            }
        } catch {
            // Error requesting permission
            await MainActor.run {
                notificationsEnabled = false
                notificationErrorMessage = "Failed to register: \(error.localizedDescription)"
                showNotificationError = true
            }
        }
    }
    
    private func unregisterFromNotifications() async {
        await manager.unregisterFromPushNotifications()
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

