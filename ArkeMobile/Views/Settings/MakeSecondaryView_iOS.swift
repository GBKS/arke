//
//  MakeSecondaryView_iOS.swift
//  Arké
//
//  The old primary's half of flow 4.3 branch A (Device_Linking.md §4.3,
//  §14): demote, then wait for the final backup to upload before telling the
//  user to continue on the other device. The handover instruction on the
//  other device points at this action by name.
//

import SwiftUI
import ArkeUI

struct MakeSecondaryView_iOS: View {
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    @Environment(\.deviceRegistrationService) private var deviceService

    private enum Phase: Equatable {
        case confirm
        case demoting
        case uploading
        case done(uploaded: Bool)
    }

    @State private var phase: Phase = .confirm
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ArkeCircularIcon(icon: Image(systemName: "arrow.down.circle"))

                Text(title)
                    .font(.system(.title, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if phase == .demoting || phase == .uploading {
                    ProgressView()
                }

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.Arke.red)
                        .padding(.horizontal)
                }

                buttons
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle(L10n.sectionDeviceRole)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(phase == .demoting || phase == .uploading)
    }

    private var title: String {
        switch phase {
        case .confirm:
            return String(localized: "settings_make_this_device_secondary", defaultValue: "Make This Device Secondary?")
        case .demoting:
            return String(localized: "make_secondary_closing", defaultValue: "Closing the wallet…")
        case .uploading:
            return String(localized: "make_secondary_uploading", defaultValue: "Uploading the final backup…")
        case .done(true):
            return String(localized: "make_secondary_done", defaultValue: "Now continue on your other device")
        case .done(false):
            return String(localized: "make_secondary_done_slow", defaultValue: "This device is now secondary")
        }
    }

    private var message: String {
        switch phase {
        case .confirm:
            return String(localized: "make_secondary_help",
                          defaultValue: "This device switches to view-only and writes its final backup to iCloud. Then make your other device primary; it continues from that backup. Keep this device online until the upload finishes.")
        case .demoting, .uploading:
            return String(localized: "make_secondary_keep_online", defaultValue: "Keep this device online.")
        case .done(true):
            return String(localized: "make_secondary_done_help",
                          defaultValue: "The backup is in iCloud. On your other device, open Settings › Devices and tap Make This Device Primary.")
        case .done(false):
            return String(localized: "make_secondary_done_slow_help",
                          defaultValue: "The backup is still uploading. Keep this device online a little longer before making the other device primary.")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .confirm:
            VStack(spacing: 12) {
                ArkeGlassButton(String(localized: "settings_make_secondary", defaultValue: "Make Secondary")) {
                    Task { await demote() }
                }
                ArkeGlassButton(L10n.buttonCancel, variant: .secondary) {
                    isPresented = false
                }
            }
        case .demoting, .uploading:
            EmptyView()
        case .done:
            ArkeGlassButton(L10n.buttonOk) {
                isPresented = false
                onSuccess?()
            }
        }
    }

    private func demote() async {
        errorMessage = nil
        phase = .demoting
        let startedAt = Date()
        do {
            try await deviceService.demoteThisDevice()
        } catch {
            errorMessage = error.localizedDescription
            phase = .confirm
            return
        }
        // WalletManager answers the demotion notification by closing bark and
        // writing the final backup; the slot monitor tells us when iCloud has
        // it. Two minutes covers a slow upload; a timeout is reported, not hidden.
        phase = .uploading
        let uploaded = await BackupSlotMonitor().waitForUpload(after: startedAt.addingTimeInterval(-5), timeout: .seconds(120))
        phase = .done(uploaded: uploaded)
    }
}
