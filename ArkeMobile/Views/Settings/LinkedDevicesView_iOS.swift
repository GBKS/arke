//
//  LinkedDevicesView_iOS.swift
//  Arké
//
//  Created by Christoph on 12/04/25.
//

import SwiftUI
import ArkeUI

struct LinkedDevicesView_iOS: View {
    let onNavigateToActivity: (() -> Void)?
    @Environment(\.deviceRegistrationService) private var deviceService
    @Environment(\.dismiss) private var dismiss
    @State private var deviceToUnlink: UnlinkTarget?
    @State private var showingUnlinkConfirmation = false
    @State private var isUnlinking = false
    @State private var errorMessage: String?
    @State private var showDemoteSheet = false
    @State private var showPromoteSheet = false
    @State private var noPrimaryDeviceDetected = false
    @State private var hasPrimaryDevice = false
    /// The merged two-store view. Read for the mirror-only entries the registry
    /// can't show, and for the wallet hash that scopes this list.
    @State private var otherDeviceReport: OtherDeviceReport?
    @State private var accountWalletHash: String?
    
    var body: some View {
        List {
            Text(!hasAnyOtherDevice
                 ? String(localized: "linked_devices_single_device_description",
                          defaultValue: "You're using Arké on one device. Install Arké on another iPhone or iPad signed in to the same iCloud, and it'll appear here automatically. View-only at first, ready to take over if you need it.")
                 : String(localized: "linked_devices_multiple_devices_description",
                          defaultValue: "Only your primary device can spend. Secondary devices can view balance and history."))
                .font(.title3)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .padding(.vertical, 15)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityAddTraits(.isStaticText)
            
            Section {
                // Current device section
                // The current device gets no unlink: self-unlink is the path
                // behind the open "checkReadOnlyMode infers primary" item and
                // has not been run on device.
                if let currentDevice = currentDevice {
                    DeviceRow_iOS(device: currentDevice, isCurrent: true, onUnlink: nil)
                }

                // Other devices section. Unlink is deliberately reachable only
                // through the row's context menu (touch and hold) — a stuck-user
                // remedy, not a discoverable feature yet.
                if !otherDevices.isEmpty {
                    ForEach(otherDevices) { device in
                        DeviceRow_iOS(device: device, isCurrent: false, onUnlink: {
                            deviceToUnlink = UnlinkTarget(deviceId: device.deviceId, displayName: device.deviceName)
                            showingUnlinkConfirmation = true
                        })
                    }
                }

                // Devices the fast mirror knows about but this device's registry
                // copy does not. The same unlink applies: `unlinkDevice` clears
                // the mirror entries first and treats a row-less ID as success.
                ForEach(otherDeviceReport?.mirrorOnly ?? []) { device in
                    UnsyncedDeviceRow(device: device, onUnlink: {
                        deviceToUnlink = UnlinkTarget(
                            deviceId: device.deviceId,
                            displayName: device.deviceName
                                ?? String(localized: "linked_devices_unsynced_device", defaultValue: "Unrecognized device")
                        )
                        showingUnlinkConfirmation = true
                    })
                }
            }
            
            // Show banner if no primary device exists
            if noPrimaryDeviceDetected {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "linked_devices_no_active_wallet",
                                        defaultValue: "No Active Wallet"))
                                .font(.headline)
                            Text(String(localized: "linked_devices_no_active_wallet_description",
                                        defaultValue: "Make this device your primary wallet to send and receive."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "accessibility_no_primary_device_alert",
                                               defaultValue: "Warning: No active wallet. Make this device your primary wallet to send and receive."))
                    .accessibilityAddTraits(.isStaticText)
                }
            }
            
            // Device Role Management - only show if at least one button is visible
            if currentDevice?.isPrimaryDevice == true || (currentDevice?.isPrimaryDevice == false && !hasPrimaryDevice) {
                Section {
                    // Show "Make This Device Secondary" if this is primary
                    if currentDevice?.isPrimaryDevice == true {
                        Button(action: { showDemoteSheet = true }) {
                            Label(String(localized: "button_make_device_secondary",
                                         defaultValue: "Make Device Secondary"),
                                  systemImage: "arrow.down.circle")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityHint(String(localized: "accessibility_make_secondary_hint",
                                                  defaultValue: "Converts this device to view-only mode. You won't be able to spend from this device."))
                    }
                    
                    // Show "Make This Device Primary" if this is secondary and no primary exists
                    if currentDevice?.isPrimaryDevice == false && !hasPrimaryDevice {
                        Button(action: { showPromoteSheet = true }) {
                            Label(String(localized: "button_make_device_primary",
                                         defaultValue: "Make Device Primary"),
                                  systemImage: "arrow.up.circle")
                                .foregroundStyle(Color.Arke.green)
                        }
                        .accessibilityHint(String(localized: "accessibility_make_primary_hint",
                                                  defaultValue: "Enables spending on this device. This device will have full wallet access."))
                    }
                } header: {
                    Text(L10n.sectionDeviceRole)
                }
            }
            
            // Error message
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.Arke.red)
                        .font(.system(size: 14))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .listSectionSpacing(8)
        .navigationTitle(L10n.settingsLinkedDevices)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showDemoteSheet) {
            DemoteDeviceSheet(isPresented: $showDemoteSheet, onSuccess: {
                // Navigate back to Activity view after successful demotion
                onNavigateToActivity?()
            })
        }
        .sheet(isPresented: $showPromoteSheet) {
            PromoteDeviceSheet(isPresented: $showPromoteSheet, onSuccess: {
                // Navigate back to Activity view after successful promotion
                onNavigateToActivity?()
            })
        }
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .confirmationDialog(String(localized: "settings_unlink_device", defaultValue: "Unlink Device"),
            isPresented: $showingUnlinkConfirmation,
            presenting: deviceToUnlink
        ) { (target: UnlinkTarget) in
            Button(String(format: String(localized: "button_unlink_device_name",
                                         defaultValue: "Unlink %@"),
                          target.displayName), role: .destructive) {
                Task {
                    await unlinkDevice(target)
                }
            }
            Button(L10n.buttonCancel, role: .cancel) { }
        } message: { (target: UnlinkTarget) in
            // Honest about what unlink does: it edits the device list, nothing
            // more. A device that still runs Arké keeps its seed and registers
            // itself again on its next launch.
            Text(String(localized: "alert_unlink_device_explanation",
                        defaultValue: "Removes this device from the wallet's device list. Use this for a device you no longer have. If it still runs Arké, it will reappear here on its own."))
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
    
    /// Other devices registered to *this* wallet.
    ///
    /// The wallet-hash scoping matches what the deletion decision has always
    /// applied. Without it this list also counted registrations left behind by
    /// other (test) wallets, so the two surfaces could disagree in both
    /// directions — too many devices here, or too few.
    private var otherDevices: [DeviceRegistration] {
        deviceService.registeredDevices.filter { device in
            do {
                let currentDeviceId = try deviceService.getOrCreateDeviceId()
                guard device.deviceId != currentDeviceId, device.isActive else { return false }
                // A missing hash means the account wallet is unknown (iCloud
                // sign-out, S10); stay unscoped rather than show nothing
                guard let accountWalletHash else { return true }
                return device.walletHash == accountWalletHash
            } catch {
                return false
            }
        }.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    /// Whether anything other than this device holds the wallet — including the
    /// mirror-only entries, which are what the delete flow actually blocks on.
    private var hasAnyOtherDevice: Bool {
        !otherDevices.isEmpty || !(otherDeviceReport?.mirrorOnly.isEmpty ?? true)
    }
    
    // MARK: - Actions
    
    private func unlinkDevice(_ target: UnlinkTarget) async {
        isUnlinking = true
        errorMessage = nil

        do {
            try await deviceService.unlinkDevice(target.deviceId)
            // The mirror-only list comes from the merged report, not from
            // `registeredDevices`, so it needs its own re-read
            otherDeviceReport = try? await deviceService.currentOtherDeviceReport()

            // Provide haptic feedback
            await MainActor.run {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                errorMessage = String(format: String(localized: "error_unlink_device",
                                                     defaultValue: "Failed to unlink device: %@"),
                                      error.localizedDescription)
                
                // Announce error to VoiceOver users
                UIAccessibility.post(notification: .announcement, argument: errorMessage)
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
        
        isUnlinking = false
    }
    
    private func reload() async {
        accountWalletHash = deviceService.accountWalletHash()
        await deviceService.loadRegisteredDevices()

        // Mirror entries are the ones the delete flow blocks on, so this list
        // has to read the same merged report the delete flow does
        otherDeviceReport = try? await deviceService.currentOtherDeviceReport()

        await checkForNoPrimaryDevice()
        await checkForPrimaryDevice()
    }

    private func checkForNoPrimaryDevice() async {
        do {
            noPrimaryDeviceDetected = try await deviceService.checkForNoPrimaryDevice()
        } catch {
            print("Error checking for no primary device: \(error)")
        }
    }
    
    private func checkForPrimaryDevice() async {
        do {
            let primaryDevice = try await deviceService.getPrimaryDevice()
            hasPrimaryDevice = primaryDevice != nil
        } catch {
            print("Error checking for primary device: \(error)")
            hasPrimaryDevice = false
        }
    }
}

/// What the unlink confirmation acts on. Covers both a registry row and a
/// mirror-only entry, which have no common model type but the same remedy.
private struct UnlinkTarget {
    let deviceId: String
    let displayName: String
}

// MARK: - Device Row

struct DeviceRow_iOS: View {
    let device: DeviceRegistration
    let isCurrent: Bool
    /// Offered in the row's context menu when non-nil. Nil for the current
    /// device, which must not unlink itself here.
    let onUnlink: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Platform icon
            Text(device.platformIcon)
                .font(.system(size: 32))
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                // Device name
                HStack {
                    Text(device.deviceName)
                        .font(.system(size: 16, weight: .medium))
                    
                    if isCurrent {
                        Text(L10n.settingsThisDeviceParentheses)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Platform and status
                HStack(spacing: 4) {
                    Text(device.platformDisplayName)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text(L10n.symbolBullet)
                        .foregroundColor(.secondary)
                    
                    Text(device.lastSeenRelative)
                        .font(.system(size: 14))
                        .foregroundColor(device.isStale ? .Arke.red : .secondary)
                }
                
                // Status badges
                HStack(spacing: 6) {
                    if device.isPrimaryDevice {
                        StatusBadge_iOS(text: L10n.statusFullWallet, color: .Arke.blue)
                    } else {
                        StatusBadge_iOS(text: L10n.statusMetadataOnly, color: .Arke.orange)
                    }

                    if device.isStale {
                        StatusBadge_iOS(text: String(localized: "status_stale", defaultValue: "Stale"), color: .Arke.red)
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(deviceAccessibilityLabel)
        // Touch and hold. VoiceOver exposes the menu through the actions rotor,
        // so no hint is needed and the old "double tap for options" one was
        // untrue since the inline menu went away.
        .contextMenu {
            if let onUnlink {
                Button(role: .destructive, action: onUnlink) {
                    Label(String(localized: "settings_unlink_device", defaultValue: "Unlink Device"),
                          systemImage: "minus.circle")
                }
            }
        }
    }
    
    private var deviceAccessibilityLabel: String {
        var parts: [String] = []
        
        // Device name and current status
        if isCurrent {
            parts.append("\(device.deviceName), \(L10n.settingsThisDeviceParentheses)")
        } else {
            parts.append(device.deviceName)
        }

        // Platform
        parts.append(device.platformDisplayName)

        // Last seen
        parts.append(String(localized: "accessibility_last_seen", defaultValue: "last seen") + " \(device.lastSeenRelative)")

        // Primary/Secondary status
        if device.isPrimaryDevice {
            parts.append(L10n.statusFullWallet)
        } else {
            parts.append(L10n.statusMetadataOnly)
        }

        // Stale warning
        if device.isStale {
            parts.append(String(localized: "accessibility_device_stale_warning",
                                defaultValue: "Warning: not seen recently"))
        }
        
        return parts.joined(separator: ", ")
    }
}

struct StatusBadge_iOS: View {
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
