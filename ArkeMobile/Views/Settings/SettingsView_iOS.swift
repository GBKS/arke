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
    
    @AppStorage(UserDefaults.proximityPermissionKey)
    private var proximityEnabled: Bool = false

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    @State private var navPath = NavigationPath()
    @State private var defaultAvatarImage: String = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"

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
                NavigationLink(destination: UserProfileSettingView()) {
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
                            //Text(String(localized: "settings_my_profile", defaultValue: "My Profile"))
                            //    .font(.callout)
                            
                            if let profile = userProfile, profile.isConfigured {
                                if profile.name.isEmpty {
                                    Text(String(localized: "profile_photo_set", defaultValue: "Photo set"))
                                        .font(.title3.weight(.semibold))
                                } else {
                                    Text(profile.name)
                                        .font(.title3.weight(.semibold))
                                }
                            } else {
                                Text(String(localized: "profile_customize_info", defaultValue: "Your name and photo"))
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
                            Text(String(localized: "settings_unit_format", defaultValue: "Unit Format"))
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
                            Text(String(localized: "action_hide_balance", defaultValue: "Hide Card Balance"))
                                .font(.body)
                            Text(String(localized: "balance_reveal_hint", defaultValue: "Long-press balance card to reveal"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                
                // Notifications (only in primary mode - requires ASP connection)
                if !manager.isReadOnlyMode {
                    NavigationLink(destination: NotificationsSettingView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.Arke.orange)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "settings_notifications", defaultValue: "Notifications"))
                                    .font(.body)
                                Text(String(localized: "settings_notifications_hint", defaultValue: "Get notified when funds arrive"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(String(localized: "settings_general", defaultValue: "General"))
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
                                Text(L10n.settingsManualBackup)
                                    .font(.body)
                                Text(String(localized: "settings_manual_backup_hint", defaultValue: "Save your wallet offline"))
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
                            Text(L10n.settingsLinkedDevices)
                                .font(.body)
                            Text(String(localized: "settings_devices_connected", defaultValue: "\(deviceCount) devices connected"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(String(localized: "settings_security", defaultValue: "Security"))
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
                            Text(String(localized: "onboarding_intro_video", defaultValue: "Intro Video"))
                                .font(.body)
                            Text(String(localized: "settings_learn_how", defaultValue: "Learn how everything works"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(String(localized: "settings_help_learning", defaultValue: "Help & Learning"))
            }

            // Behind the Curtain Section
            Section {
                // Fee Summary
                NavigationLink(destination: FeeSummaryView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.Arke.green)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.activityFeeSummary)
                                .font(.body)
                            Text(String(localized: "action_view_fees", defaultValue: "View transaction fees"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // ASP-dependent rows (only in primary mode)
                if !manager.isReadOnlyMode {
                    // Server Fee Schedule
                    NavigationLink(destination: FeeScheduleView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundColor(.Arke.teal)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.settingsFeeSchedule)
                                    .font(.body)
                                Text(String(localized: "settings_fee_schedule_hint", defaultValue: "Server fee breakdown"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // Address History
                    NavigationLink(destination: AddressHistoryView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(.Arke.blue)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.receiveAddressHistory)
                                    .font(.body)
                                Text(String(localized: "action_view_addresses", defaultValue: "View generated addresses"))
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
                                Text(L10n.dataXrayTitle)
                                    .font(.body)
                                Text(String(localized: "data_wallet_raw", defaultValue: "Your wallet data, raw"))
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
                                Text(String(localized: "nav_title_transaction_testing", defaultValue: "Transaction Testing"))
                                    .font(.callout)
                                Text("Developer stress tests")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    */
                }
            } header: {
                Text(String(localized: "data_behind_curtain", defaultValue: "Behind the curtain"))
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
                            Text(String(localized: "settings_proximity_sharing", defaultValue: "Nearby Sharing"))
                                .font(.body)
                            Text(String(localized: "settings_proximity_sharing_hint", defaultValue: "Share payment info with nearby devices when tilting"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)

                // Address Icons
                NavigationLink(destination: AddressPatternsSettingView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(.Arke.teal)
                            .accessibilityHidden(true)
                            .frame(width: iconSize, height: iconSize)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.settingsAddressPatterns)
                                .font(.body)
                            Text(String(localized: "settings_address_patterns_hint", defaultValue: "Show unique visual patterns to help identify addresses"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(String(localized: "settings_experimental", defaultValue: "Experimental"))
            }

            // Danger Zone Section (only in primary mode)
            //if !manager.isReadOnlyMode {
                Section {
                    // Exit
                    NavigationLink(destination: ExitView_iOS(
                        onNavigateToBalance: onNavigateToBalance,
                        onNavigateToActivity: onNavigateToActivity
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "light.beacon.max.fill")
                                .foregroundColor(.Arke.orange)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "button_force_move_savings", defaultValue: "Force Move to Savings"))
                                    .font(.body)
                                Text(String(localized: "balance_transfer_independently", defaultValue: "Transfer your bitcoin independently"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // Delete Wallet
                    NavigationLink(destination: DeleteWalletView(onWalletDeleted: onWalletDeleted)) {
                        HStack(spacing: 12) {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.Arke.red)
                                .accessibilityHidden(true)
                                .frame(width: iconSize, height: iconSize)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.buttonDeleteWallet)
                                    .font(.body)
                                    .foregroundColor(.Arke.red)
                                Text(String(localized: "settings_delete_wallet_title", defaultValue: "Permanently remove your wallet"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(L10n.settingsDangerZone)
                }
            //}
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle(L10n.settingsTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await deviceService.loadRegisteredDevices()
        }
    }
    
    private var deviceCount: Int {
        deviceService.registeredDevices.filter { $0.isActive && !$0.isStale }.count
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
