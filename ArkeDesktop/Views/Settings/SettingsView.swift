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
    case theme
    case manualBackup
    case linkedDevices
    case feeSummary
    case feeSchedule
    case addressHistory
    case xray
    case addressPatterns
    case deleteWallet

    var id: String { rawValue }
}

struct SettingsView: View {
    @Binding var selectedItem: SettingsDetailItem?

    @Environment(WalletManager.self) private var manager
    @Environment(\.deviceRegistrationService) private var deviceService

    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var bitcoinFormat: String = BitcoinAmountFormat.defaultFormat.rawValue

    @AppStorage(UserDefaults.appThemeKey)
    private var appTheme: String = AppTheme.defaultTheme.rawValue

    @State private var defaultAvatarImage: String = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"

    @Query private var profiles: [UserProfile]

    private var userProfile: UserProfile? {
        profiles.first
    }

    private var selectedFormat: BitcoinAmountFormat {
        BitcoinAmountFormat(rawValue: bitcoinFormat) ?? .defaultFormat
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appTheme) ?? .defaultTheme
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
                    title: String(localized: "settings_unit_format", defaultValue: "Unit Format"),
                    subtitle: Text(String(localized: "format_currently", defaultValue: "Currently: \(selectedFormat.displayName)"))
                )
                .tag(SettingsDetailItem.unitFormat)

                settingsRow(
                    icon: "paintpalette.fill",
                    color: .Arke.pink,
                    title: L10n.settingsTheme,
                    subtitle: Text(String(localized: "format_currently", defaultValue: "Currently: \(selectedTheme.displayName)"))
                )
                .tag(SettingsDetailItem.theme)
            } header: {
                Text(String(localized: "settings_general", defaultValue: "General"))
            }

            // Security Section
            Section {
                if !manager.isReadOnlyMode {
                    settingsRow(
                        icon: "shield.fill",
                        color: .Arke.green,
                        title: L10n.settingsManualBackup,
                        subtitle: Text(String(localized: "settings_manual_backup_hint", defaultValue: "Save your wallet offline"))
                    )
                    .tag(SettingsDetailItem.manualBackup)
                }

                settingsRow(
                    icon: "laptopcomputer.and.iphone",
                    color: .Arke.purple,
                    title: L10n.settingsLinkedDevices,
                    subtitle: Text(String(localized: "settings_devices_connected", defaultValue: "\(deviceCount) devices connected"))
                )
                .tag(SettingsDetailItem.linkedDevices)
            } header: {
                Text(String(localized: "settings_security", defaultValue: "Security"))
            }

            // Behind the Curtain Section
            Section {
                settingsRow(
                    icon: "chart.bar.fill",
                    color: .Arke.green,
                    title: L10n.activityFeeSummary,
                    subtitle: Text(String(localized: "action_view_fees", defaultValue: "View transaction fees"))
                )
                .tag(SettingsDetailItem.feeSummary)

                // ASP-dependent rows (only in primary mode)
                if !manager.isReadOnlyMode {
                    settingsRow(
                        icon: "list.bullet.rectangle.fill",
                        color: .Arke.teal,
                        title: L10n.settingsFeeSchedule,
                        subtitle: Text(String(localized: "settings_fee_schedule_hint", defaultValue: "Server fee breakdown"))
                    )
                    .tag(SettingsDetailItem.feeSchedule)

                    settingsRow(
                        icon: "building.columns.fill",
                        color: .Arke.blue,
                        title: L10n.receiveAddressHistory,
                        subtitle: Text(String(localized: "action_view_addresses", defaultValue: "View generated addresses"))
                    )
                    .tag(SettingsDetailItem.addressHistory)

                    settingsRow(
                        icon: "brain.head.profile.fill",
                        color: .Arke.teal,
                        title: L10n.dataXrayTitle,
                        subtitle: Text(String(localized: "data_wallet_raw", defaultValue: "Your wallet data, raw"))
                    )
                    .tag(SettingsDetailItem.xray)
                }
            } header: {
                Text(String(localized: "data_behind_curtain", defaultValue: "Behind the curtain"))
            }

            // Experimental Section
            Section {
                settingsRow(
                    icon: "square.grid.2x2.fill",
                    color: .Arke.teal,
                    title: L10n.settingsAddressPatterns,
                    subtitle: Text(String(localized: "settings_address_patterns_hint", defaultValue: "Show unique visual patterns to help identify addresses"))
                )
                .tag(SettingsDetailItem.addressPatterns)
            } header: {
                Text(String(localized: "settings_experimental", defaultValue: "Experimental"))
            }

            // Danger Zone Section
            Section {
                settingsRow(
                    icon: "trash.fill",
                    color: .Arke.red,
                    title: L10n.buttonDeleteWallet,
                    titleColor: .Arke.red,
                    subtitle: Text(String(localized: "settings_delete_wallet_title", defaultValue: "Permanently remove your wallet"))
                )
                .tag(SettingsDetailItem.deleteWallet)
            } header: {
                Text(L10n.settingsDangerZone)
            }
        }
        .navigationTitle(L10n.settingsTitle)
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
        .padding(.vertical, 4)
    }

    private func settingsRow(
        icon: String,
        color: Color,
        title: String,
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
        case .theme:
            ThemeSettingView()
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
        case .xray:
            XRaySettingDetailView()
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
                    Text(L10n.settingsTitle)
                        .font(.system(size: 19, design: .serif))
                }
            }
        }
    }
}

// MARK: - X-Ray

// Hosts DataView in the settings detail column. The VTXO/UTXO detail
// column from the old sidebar layout doesn't exist here, so selections
// present as a sheet instead.
private struct XRaySettingDetailView: View {
    @State private var selectedDataItem: DataDetailItem?

    var body: some View {
        DataView(selectedDataItem: $selectedDataItem)
            .sheet(item: $selectedDataItem) { item in
                XRayDataDetailSheet(item: item)
            }
    }
}

private struct XRayDataDetailSheet: View {
    let item: DataDetailItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L10n.buttonDone) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal])

            switch item {
            case .vtxo(let vtxo):
                VTXODetailView(vtxo: vtxo)
            case .utxo(let utxo):
                UTXODetailView(utxo: utxo)
            }
        }
        .frame(width: 420, height: 560)
    }
}

extension DataDetailItem: Identifiable {
    var id: String {
        switch self {
        case .vtxo(let vtxo): return "vtxo-\(vtxo.id)"
        case .utxo(let utxo): return "utxo-\(utxo.id)"
        }
    }
}
