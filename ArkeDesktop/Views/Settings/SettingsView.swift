//
//  SettingsView.swift
//  Ark wallet prototype
//
//  Middle column of the three-column settings layout. Mirrors the
//  mobile settings list; the selected row renders in the detail column
//  via SettingsDetailView.
//

import SwiftUI
import SwiftData
import ArkeUI

enum SettingsDetailItem: String, CaseIterable, Identifiable, Hashable {
    case profile
    case unitFormat
    case manualBackup
    case linkedDevices
    case feeSummary
    case feeSchedule
    case addressHistory
    case addressPatterns
    case deleteWallet

    var id: String { rawValue }
}

struct SettingsView: View {
    @Binding var selectedItem: SettingsDetailItem?
    let onNavigateToData: () -> Void

    @Environment(WalletManager.self) private var manager
    @Environment(\.deviceRegistrationService) private var deviceService

    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var bitcoinFormat: String = BitcoinAmountFormat.defaultFormat.rawValue

    @State private var defaultAvatarImage: String = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"

    @Query private var profiles: [UserProfile]

    private var userProfile: UserProfile? {
        profiles.first
    }

    private var selectedFormat: BitcoinAmountFormat {
        BitcoinAmountFormat(rawValue: bitcoinFormat) ?? .defaultFormat
    }

    private var deviceCount: Int {
        deviceService.registeredDevices.filter { $0.isActive && !$0.isStale }.count
    }

    var body: some View {
        List(selection: $selectedItem) {
            // Profile Section
            Section {
                profileRow
                    .tag(SettingsDetailItem.profile)
            }

            // General Section
            Section {
                settingsRow(
                    icon: "numbers",
                    color: .Arke.indigo,
                    title: "settings_unit_format",
                    subtitle: Text(String(localized: "format_currently", defaultValue: "Currently: \(selectedFormat.displayName)"))
                )
                .tag(SettingsDetailItem.unitFormat)
            } header: {
                Text("settings_general")
            }

            // Security Section
            Section {
                if !manager.isReadOnlyMode {
                    settingsRow(
                        icon: "shield.fill",
                        color: .Arke.green,
                        title: "settings_manual_backup",
                        subtitle: Text("settings_manual_backup_hint")
                    )
                    .tag(SettingsDetailItem.manualBackup)
                }

                settingsRow(
                    icon: "laptopcomputer.and.iphone",
                    color: .Arke.purple,
                    title: "settings_linked_devices",
                    subtitle: Text(String(localized: "settings_devices_connected", defaultValue: "\(deviceCount) devices connected"))
                )
                .tag(SettingsDetailItem.linkedDevices)
            } header: {
                Text("settings_security")
            }

            // Behind the Curtain Section
            Section {
                settingsRow(
                    icon: "chart.bar.fill",
                    color: .Arke.green,
                    title: "activity_fee_summary",
                    subtitle: Text("action_view_fees")
                )
                .tag(SettingsDetailItem.feeSummary)

                // ASP-dependent rows (only in primary mode)
                if !manager.isReadOnlyMode {
                    settingsRow(
                        icon: "list.bullet.rectangle.fill",
                        color: .Arke.teal,
                        title: "settings_fee_schedule",
                        subtitle: Text("settings_fee_schedule_hint")
                    )
                    .tag(SettingsDetailItem.feeSchedule)

                    settingsRow(
                        icon: "building.columns.fill",
                        color: .Arke.blue,
                        title: "receive_address_history",
                        subtitle: Text("action_view_addresses")
                    )
                    .tag(SettingsDetailItem.addressHistory)

                    // X-Ray lives in the sidebar; this row just navigates there
                    Button {
                        onNavigateToData()
                    } label: {
                        settingsRow(
                            icon: "brain.head.profile.fill",
                            color: .Arke.teal,
                            title: "data_xray_title",
                            subtitle: Text("data_wallet_raw")
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("data_behind_curtain")
            }

            // Experimental Section
            Section {
                settingsRow(
                    icon: "square.grid.2x2.fill",
                    color: .Arke.teal,
                    title: "settings_address_patterns",
                    subtitle: Text("settings_address_patterns_hint")
                )
                .tag(SettingsDetailItem.addressPatterns)
            } header: {
                Text("settings_experimental")
            }

            // Danger Zone Section
            Section {
                settingsRow(
                    icon: "trash.fill",
                    color: .Arke.red,
                    title: "button_delete_wallet",
                    titleColor: .Arke.red,
                    subtitle: Text("settings_delete_wallet_title")
                )
                .tag(SettingsDetailItem.deleteWallet)
            } header: {
                Text("settings_danger_zone")
            }
        }
        .navigationTitle("settings_title")
        .task {
            await deviceService.loadRegisteredDevices()
        }
    }

    // MARK: - Rows

    private var profileRow: some View {
        HStack(spacing: 12) {
            // Avatar preview
            if let avatarData = userProfile?.avatarData,
               let nsImage = NSImage(data: avatarData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
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
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .accessibilityHidden(true)
            }

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
        .padding(.vertical, 4)
    }

    private func settingsRow(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        titleColor: Color = .primary,
        subtitle: Text
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .accessibilityHidden(true)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundColor(titleColor)
                subtitle
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail Column

struct SettingsDetailView: View {
    let item: SettingsDetailItem?
    let onWalletDeleted: (() -> Void)?

    var body: some View {
        switch item {
        case .profile:
            UserProfileSettingView()
        case .unitFormat:
            ScrollView {
                BitcoinFormatSettingView()
                    .padding()
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
            }
        case .manualBackup:
            ManualBackupView()
        case .linkedDevices:
            LinkedDevicesView()
        case .feeSummary:
            FeeSummaryView()
        case .feeSchedule:
            FeeScheduleView()
        case .addressHistory:
            AddressHistoryView()
        case .addressPatterns:
            AddressPatternsSettingView()
        case .deleteWallet:
            ScrollView {
                DeleteWalletSettingView(onWalletDeleted: onWalletDeleted)
                    .padding()
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
            }
        case nil:
            ContentUnavailableView {
                VStack(spacing: 15) {
                    Image(systemName: "gearshape")
                        .imageScale(.medium)
                        .symbolVariant(.none)
                    Text("settings_title")
                        .font(.system(size: 19, design: .serif))
                }
            }
        }
    }
}
