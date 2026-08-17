//
//  ConnectionInfoSheet.swift
//  Arké
//
//  Created by Claude on 4/13/26.
//

import SwiftUI

public struct ConnectionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isOnSignet: Bool
    let networkName: String
    let connectionStatus: ConnectionStatus
    /// Shown as a button in the read-only section when the wallet key hasn't
    /// synced to this device yet (`readOnlyReason == .seedNotSynced`)
    let onEnterRecoveryPhrase: (() -> Void)?

    public init(
        isOnSignet: Bool,
        networkName: String,
        connectionStatus: ConnectionStatus,
        onEnterRecoveryPhrase: (() -> Void)? = nil
    ) {
        self.isOnSignet = isOnSignet
        self.networkName = networkName
        self.connectionStatus = connectionStatus
        self.onEnterRecoveryPhrase = onEnterRecoveryPhrase
    }

    private var hasArkConnection: Bool {
        connectionStatus.isConnected
    }
    
    private var hasGoodConnection: Bool {
        connectionStatus.quality == .excellent || connectionStatus.quality == .good
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(String(localized: "connection_sheet_title", defaultValue: "Connection Status", bundle: .module))
                        .font(.system(size: 30, design: .serif))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Read-Only Mode Section
                    if connectionStatus.isReadOnlyMode {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color.Arke.blue)

                                Text(String(localized: "connection_readonly_title", defaultValue: "Read-Only Mode", bundle: .module))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            if connectionStatus.readOnlyReason == .seedNotSynced {
                                Text(String(localized: "connection_readonly_seed_not_synced_message", defaultValue: "This device is viewing wallet data synced via iCloud. Your wallet key hasn’t arrived on this device yet — it usually syncs on its own through iCloud Keychain.", bundle: .module))
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_viewing_only", defaultValue: "Viewing synced data only", bundle: .module))
                                    ConnectionInfoRow(icon: "icloud.and.arrow.down", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_key_syncing", defaultValue: "Wallet key syncing via iCloud Keychain", bundle: .module))
                                    ConnectionInfoRow(icon: "key.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_enter_phrase", defaultValue: "Or enter your recovery phrase now", bundle: .module))
                                }

                                if let onEnterRecoveryPhrase {
                                    Button {
                                        dismiss()
                                        onEnterRecoveryPhrase()
                                    } label: {
                                        Text(String(localized: "button_enter_recovery_phrase", defaultValue: "Enter Recovery Phrase", bundle: .module))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .tint(Color.Arke.blue)
                                    .padding(.top, 4)
                                }
                            } else {
                                Text(String(localized: "connection_readonly_not_primary_message", defaultValue: "This device is viewing wallet data synced from your primary device via iCloud. Send and receive functions are only available on your primary device.", bundle: .module))
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_viewing_only", defaultValue: "Viewing synced data only", bundle: .module))
                                    ConnectionInfoRow(icon: "icloud.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_data_synced", defaultValue: "Data synced via iCloud", bundle: .module))
                                    ConnectionInfoRow(icon: "lock.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_send_receive_disabled", defaultValue: "Send and receive disabled", bundle: .module))
                                }
                            }
                        }

                        Divider()
                    }

                    // Signet Network Section
                    if isOnSignet {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "network.badge.shield.half.filled")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color.Arke.blue)
                                
                                Text(String(localized: "connection_test_network_title", defaultValue: "Test Network", bundle: .module))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text(String(localized: "connection_test_network_message %@", defaultValue: "You are connected to \(networkName), a test network for development and experimentation.", bundle: .module))
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "testtube.2", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_safe", defaultValue: "Test network for safe experimentation", bundle: .module))
                                ConnectionInfoRow(icon: "bitcoinsign", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_no_value", defaultValue: "Test coins have no real value", bundle: .module))
                                ConnectionInfoRow(icon: "books.vertical", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_faucet", defaultValue: "Use the faucet to get test funds", bundle: .module))
                            }
                        }
                        
                        Divider()
                    }
                    
                    // Ark Server Connection Section (hide in read-only mode)
                    if !connectionStatus.isReadOnlyMode {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: hasArkConnection ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(hasArkConnection ? Color.Arke.green : Color.Arke.red)

                                Text(String(localized: "connection_ark_server_title", defaultValue: "Ark Server", bundle: .module))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                        
                        Text(connectionStatus.statusMessage)
                            .font(.body)
                            .foregroundColor(hasArkConnection ? .secondary : Color.Arke.red)
                        
                        if let detailedMessage = connectionStatus.detailedMessage {
                            Text(detailedMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ConnectionInfoRow(
                                icon: hasArkConnection ? "checkmark.circle.fill" : "xmark.circle.fill",
                                iconColor: hasArkConnection ? Color.Arke.green : Color.Arke.red,
                                text: hasArkConnection
                                    ? String(localized: "connection_row_connected", defaultValue: "Connected to Ark server", bundle: .module)
                                    : String(localized: "connection_row_not_connected", defaultValue: "No connection to Ark server", bundle: .module)
                            )
                            
                            if hasArkConnection {
                                ConnectionInfoRow(
                                    icon: connectionQualityIcon,
                                    iconColor: connectionQualityColor,
                                    text: String(localized: "connection_row_quality %@", defaultValue: "Connection quality: \(connectionQualityText)", bundle: .module)
                                )
                            }
                            
                            if connectionStatus.reconnectionAttempts > 0 {
                                ConnectionInfoRow(
                                    icon: "arrow.clockwise",
                                    iconColor: Color.Arke.orange,
                                    text: String(localized: "connection_row_reconnection_attempts %lld", defaultValue: "Reconnection attempts: \(connectionStatus.reconnectionAttempts)", bundle: .module)
                                )
                            }
                            
                            if let lastError = connectionStatus.lastError {
                                ConnectionInfoRow(
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: Color.Arke.red,
                                    text: lastError
                                )
                            }
                        }
                        }
                    }

                    if !hasArkConnection || !hasGoodConnection {
                        Divider()

                        // Troubleshooting Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color.Arke.orange)
                                
                                Text(String(localized: "connection_troubleshooting_title", defaultValue: "Troubleshooting", bundle: .module))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text(String(localized: "connection_troubleshooting_message", defaultValue: "If you’re experiencing connection issues, try:", bundle: .module))
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "wifi", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_internet", defaultValue: "Check your internet connection", bundle: .module))
                                ConnectionInfoRow(icon: "arrow.clockwise", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_refresh", defaultValue: "Pull down to refresh", bundle: .module))
                                ConnectionInfoRow(icon: "arrow.down.app", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_restart", defaultValue: "Restart the app", bundle: .module))
                            }
                        }
                    }
                }
                .padding()
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.buttonDone) {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
    
    private var connectionQualityIcon: String {
        switch connectionStatus.quality {
        case .excellent:
            return "wifi"
        case .good:
            return "wifi"
        case .poor:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        }
    }
    
    private var connectionQualityColor: Color {
        switch connectionStatus.quality {
        case .excellent:
            return .green
        case .good:
            return .green
        case .poor:
            return .orange
        case .disconnected:
            return .red
        }
    }
    
    private var connectionQualityText: String {
        connectionStatus.quality.displayName
    }
}

public struct ConnectionInfoRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    public init(icon: String, iconColor: Color, text: String) {
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
        }
    }
}

#Preview("Connected on Signet") {
    ConnectionInfoSheet(
        isOnSignet: true,
        networkName: "Bitcoin Signet",
        connectionStatus: ConnectionStatus(
            isConnected: true,
            quality: .excellent,
            lastSuccessfulSync: Date().addingTimeInterval(-30),
            reconnectionAttempts: 0,
            lastError: nil
        )
    )
}
#Preview("Poor Connection") {
    ConnectionInfoSheet(
        isOnSignet: false,
        networkName: "Bitcoin Mainnet",
        connectionStatus: ConnectionStatus(
            isConnected: true,
            quality: .poor,
            lastSuccessfulSync: Date().addingTimeInterval(-600),
            reconnectionAttempts: 2,
            lastError: nil
        )
    )
}

#Preview("Read-Only, Seed Not Synced") {
    ConnectionInfoSheet(
        isOnSignet: false,
        networkName: "Bitcoin Mainnet",
        connectionStatus: ConnectionStatus(
            isReadOnlyMode: true,
            readOnlyReason: .seedNotSynced
        ),
        onEnterRecoveryPhrase: {}
    )
}

#Preview("Read-Only, Not Primary") {
    ConnectionInfoSheet(
        isOnSignet: false,
        networkName: "Bitcoin Mainnet",
        connectionStatus: ConnectionStatus(
            isReadOnlyMode: true,
            readOnlyReason: .notPrimary
        )
    )
}

#Preview("Disconnected") {
    ConnectionInfoSheet(
        isOnSignet: true,
        networkName: "Bitcoin Signet",
        connectionStatus: ConnectionStatus(
            isConnected: false,
            quality: .disconnected,
            lastSuccessfulSync: Date().addingTimeInterval(-3600),
            reconnectionAttempts: 5,
            lastError: "Failed to connect to server"
        )
    )
}

