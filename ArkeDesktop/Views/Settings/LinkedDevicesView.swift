//
//  LinkedDevicesView.swift
//  Arké
//
//  Created by Christoph on 12/04/25.
//

import SwiftUI
import ArkeUI

struct LinkedDevicesView: View {
    @Environment(\.deviceRegistrationService) private var deviceService
    @State private var showingUnlinkAllConfirmation = false
    @State private var deviceToUnlink: DeviceRegistration?
    @State private var showingUnlinkConfirmation = false
    @State private var isUnlinking = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("settings_linked_devices")
                    .font(.system(size: 28, weight: .bold, design: .default))
                
                Text("Manage devices that have access to your wallet")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current device
                    if let currentDevice = currentDevice {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("settings_this_device")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            
                            DeviceCard(device: currentDevice, isCurrent: true)
                        }
                    }
                    
                    // Other devices
                    if !otherDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "settings_other_devices_count", defaultValue: "Other Devices (\(otherDevices.count))"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            
                            ForEach(otherDevices) { device in
                                DeviceCard(
                                    device: device,
                                    isCurrent: false,
                                    onUnlink: {
                                        deviceToUnlink = device
                                        showingUnlinkConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                    
                    // Danger zone
                    if !otherDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("settings_danger_zone")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.Arke.red)
                                .textCase(.uppercase)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text(String(localized: "settings_unlink_all_help"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button {
                                    showingUnlinkAllConfirmation = true
                                } label: {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("button_unlink_all_others")
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.Arke.red)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(isUnlinking)
                            }
                            .padding(16)
                            .background(Color.Arke.red.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.Arke.red.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.Arke.red)
                            .font(.system(size: 13))
                            .padding(12)
                            .background(Color.Arke.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await deviceService.loadRegisteredDevices()
        }
        .alert("settings_unlink_device", isPresented: $showingUnlinkConfirmation, presenting: deviceToUnlink) { device in
            Button("Cancel", role: .cancel) { }
            Button("Unlink", role: .destructive) {
                Task {
                    await unlinkDevice(device)
                }
            }
        } message: { device in
            Text("Are you sure you want to unlink \(device.deviceName)? It will need to re-import the recovery phrase to regain access.")
        }
        .alert("button_unlink_all_others", isPresented: $showingUnlinkAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(String(localized: "button_unlink_all_devices", defaultValue: "Unlink All (\(otherDevices.count) devices)"), role: .destructive) {
                Task {
                    await unlinkAllOtherDevices()
                }
            }
        } message: {
            Text(String(localized: "settings_unlink_all_warning"))
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentDevice: DeviceRegistration? {
        deviceService.registeredDevices.first { device in
            do {
                let currentDeviceId = try deviceService.getOrCreateDeviceId()
                return device.deviceId == currentDeviceId
            } catch {
                return false
            }
        }
    }
    
    private var otherDevices: [DeviceRegistration] {
        deviceService.registeredDevices.filter { device in
            do {
                let currentDeviceId = try deviceService.getOrCreateDeviceId()
                return device.deviceId != currentDeviceId && device.isActive
            } catch {
                return false
            }
        }.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }
    
    // MARK: - Actions
    
    private func unlinkDevice(_ device: DeviceRegistration) async {
        isUnlinking = true
        errorMessage = nil
        
        do {
            try await deviceService.unlinkDevice(device.deviceId)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to unlink device: \(error.localizedDescription)"
            }
        }
        
        isUnlinking = false
    }
    
    private func unlinkAllOtherDevices() async {
        isUnlinking = true
        errorMessage = nil
        
        do {
            try await deviceService.unlinkAllOtherDevices()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to unlink devices: \(error.localizedDescription)"
            }
        }
        
        isUnlinking = false
    }
}

// MARK: - Device Card

struct DeviceCard: View {
    let device: DeviceRegistration
    let isCurrent: Bool
    var onUnlink: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            // Platform icon
            Text(device.platformIcon)
                .font(.system(size: 40))
            
            // Device info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.deviceName)
                        .font(.system(size: 16, weight: .semibold))
                    
                    if isCurrent {
                        Text(String(localized: "settings_this_device_parentheses"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(device.platformDisplayName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text("symbol_bullet")
                        .foregroundColor(.secondary)
                    
                    Text(device.lastSeenRelative)
                        .font(.system(size: 13))
                        .foregroundColor(device.isStale ? .Arke.red : .secondary)
                }
                
                HStack(spacing: 6) {
                    if device.hasSeed {
                        StatusBadge(text: "Full Wallet", color: .Arke.green)
                    } else {
                        StatusBadge(text: "Metadata Only", color: .Arke.orange)
                    }
                    
                    if device.isStale {
                        StatusBadge(text: "Stale", color: .Arke.red)
                    }
                }
            }
            
            Spacer()
            
            // Unlink button for other devices
            if !isCurrent, let onUnlink = onUnlink {
                Button {
                    onUnlink()
                } label: {
                    Text("button_unlink")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.Arke.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.Arke.red.opacity(0.1))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}
