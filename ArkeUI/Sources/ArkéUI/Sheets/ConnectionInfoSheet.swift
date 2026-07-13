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
                    Text("connection_sheet_title", bundle: .module)
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

                                Text("connection_readonly_title", bundle: .module)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            if connectionStatus.readOnlyReason == .seedNotSynced {
                                Text("connection_readonly_seed_not_synced_message", bundle: .module)
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_viewing_only", bundle: .module))
                                    ConnectionInfoRow(icon: "icloud.and.arrow.down", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_key_syncing", bundle: .module))
                                    ConnectionInfoRow(icon: "key.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_enter_phrase", bundle: .module))
                                }

                                if let onEnterRecoveryPhrase {
                                    Button {
                                        dismiss()
                                        onEnterRecoveryPhrase()
                                    } label: {
                                        Text("button_enter_recovery_phrase", bundle: .module)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .tint(Color.Arke.blue)
                                    .padding(.top, 4)
                                }
                            } else {
                                Text("connection_readonly_not_primary_message", bundle: .module)
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_viewing_only", bundle: .module))
                                    ConnectionInfoRow(icon: "icloud.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_data_synced", bundle: .module))
                                    ConnectionInfoRow(icon: "lock.fill", iconColor: Color.Arke.blue, text: String(localized: "connection_readonly_row_send_receive_disabled", bundle: .module))
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
                                
                                Text("connection_test_network_title", bundle: .module)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("connection_test_network_message \(networkName)", bundle: .module)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "testtube.2", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_safe", bundle: .module))
                                ConnectionInfoRow(icon: "bitcoinsign", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_no_value", bundle: .module))
                                ConnectionInfoRow(icon: "books.vertical", iconColor: Color.Arke.blue, text: String(localized: "connection_test_network_row_faucet", bundle: .module))
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

                                Text("connection_ark_server_title", bundle: .module)
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
                                    ? String(localized: "connection_row_connected", bundle: .module)
                                    : String(localized: "connection_row_not_connected", bundle: .module)
                            )
                            
                            if hasArkConnection {
                                ConnectionInfoRow(
                                    icon: connectionQualityIcon,
                                    iconColor: connectionQualityColor,
                                    text: String(localized: "connection_row_quality \(connectionQualityText)", bundle: .module)
                                )
                            }
                            
                            if connectionStatus.reconnectionAttempts > 0 {
                                ConnectionInfoRow(
                                    icon: "arrow.clockwise",
                                    iconColor: Color.Arke.orange,
                                    text: String(localized: "connection_row_reconnection_attempts \(connectionStatus.reconnectionAttempts)", bundle: .module)
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
                                
                                Text("connection_troubleshooting_title", bundle: .module)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("connection_troubleshooting_message", bundle: .module)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "wifi", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_internet", bundle: .module))
                                ConnectionInfoRow(icon: "arrow.clockwise", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_refresh", bundle: .module))
                                ConnectionInfoRow(icon: "arrow.down.app", iconColor: Color.Arke.orange, text: String(localized: "connection_troubleshooting_row_restart", bundle: .module))
                            }
                        }
                    }
                }
                .padding()
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button_done", bundle: .module)) {
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

