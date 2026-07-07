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
                    Text("Connection Status")
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

                                Text("Read-Only Mode")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            if connectionStatus.readOnlyReason == .seedNotSynced {
                                Text("This device is viewing wallet data synced via iCloud. Your wallet key hasn't arrived on this device yet — it usually syncs on its own through iCloud Keychain.")
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: "Viewing synced data only")
                                    ConnectionInfoRow(icon: "icloud.and.arrow.down", iconColor: Color.Arke.blue, text: "Wallet key syncing via iCloud Keychain")
                                    ConnectionInfoRow(icon: "key.fill", iconColor: Color.Arke.blue, text: "Or enter your recovery phrase now")
                                }

                                if let onEnterRecoveryPhrase {
                                    Button {
                                        dismiss()
                                        onEnterRecoveryPhrase()
                                    } label: {
                                        Text("Enter Recovery Phrase")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .tint(Color.Arke.blue)
                                    .padding(.top, 4)
                                }
                            } else {
                                Text("This device is viewing wallet data synced from your primary device via iCloud. Send and receive functions are only available on your primary device.")
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ConnectionInfoRow(icon: "eye.fill", iconColor: Color.Arke.blue, text: "Viewing synced data only")
                                    ConnectionInfoRow(icon: "icloud.fill", iconColor: Color.Arke.blue, text: "Data synced via iCloud")
                                    ConnectionInfoRow(icon: "lock.fill", iconColor: Color.Arke.blue, text: "Send and receive disabled")
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
                                
                                Text("Test Network")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("You are connected to \(networkName), a test network for development and experimentation.")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "testtube.2", iconColor: Color.Arke.blue, text: "Test network for safe experimentation")
                                ConnectionInfoRow(icon: "bitcoinsign", iconColor: Color.Arke.blue, text: "Test coins have no real value")
                                ConnectionInfoRow(icon: "books.vertical", iconColor: Color.Arke.blue, text: "Use the faucet to get test funds")
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

                                Text("Ark Server")
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
                                text: hasArkConnection ? "Connected to Ark server" : "No connection to Ark server"
                            )
                            
                            if hasArkConnection {
                                ConnectionInfoRow(
                                    icon: connectionQualityIcon,
                                    iconColor: connectionQualityColor,
                                    text: "Connection quality: \(connectionQualityText)"
                                )
                            }
                            
                            if connectionStatus.reconnectionAttempts > 0 {
                                ConnectionInfoRow(
                                    icon: "arrow.clockwise",
                                    iconColor: Color.Arke.orange,
                                    text: "Reconnection attempts: \(connectionStatus.reconnectionAttempts)"
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
                                
                                Text("Troubleshooting")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("If you're experiencing connection issues, try:")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionInfoRow(icon: "wifi", iconColor: Color.Arke.orange, text: "Check your internet connection")
                                ConnectionInfoRow(icon: "arrow.clockwise", iconColor: Color.Arke.orange, text: "Pull down to refresh")
                                ConnectionInfoRow(icon: "arrow.down.app", iconColor: Color.Arke.orange, text: "Restart the app")
                            }
                        }
                    }
                }
                .padding()
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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

