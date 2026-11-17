//
//  LinkWalletView.swift
//  Arké
//
//  Created by Assistant on 11/14/26.
//

import SwiftUI
import ArkeUI

/// The link screen (Device_Linking.md §4.2): the one place an install adopts
/// the account's wallet. Shown whenever the account has a wallet and this
/// install holds no valid link record — a new device, a reinstall, an
/// install that removed the wallet locally, or one that another device
/// unlinked. One action, no decline: one wallet per iCloud account means
/// there is nothing to decline into, and closing the app is "not now".
///
/// The screen hosts the first CloudKit import pass. The action enables when
/// that pass lands or after a bounded wait (DECIDED 2026-11-13: about 30 s),
/// and the copy sharpens as the import answers two questions: which device
/// is primary, and whether this device's own old row says it was primary
/// before (a reinstall).
struct LinkWalletView: View {
    let reason: LinkPromptReason
    /// True while the owner is linking (record, registration, detection).
    /// Owned by the main view so a failed attempt that lands back here does
    /// not leave the button spinning (adversarial pass 2026-11-14, F2).
    let isLinking: Bool
    /// Called when the user links, or asks to check again in the waiting and
    /// mismatch variants. The owner writes the record, registers the device
    /// and re-runs detection.
    let onLink: () -> Void

    @Environment(WalletManager.self) private var walletManager
    @Environment(\.deviceRegistrationService) private var deviceService
    @Environment(\.securityService) private var securityService

    @State private var importSettled = false
    @State private var importTimedOut = false
    @State private var primaryDeviceName: String?
    @State private var ownRowWasPrimary = false
    @State private var seedPresent = false
    #if os(iOS)
    @State private var showSeedEntry = false
    #endif

    private static let importWait: Duration = .seconds(30)

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ArkeCircularIcon(icon: Image(systemName: isBlocked ? "icloud" : "link"))
                .padding(.bottom, 8)

            Text(title)
                .font(.system(.title, design: .serif))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !isBlocked {
                statusLine
            }

            Spacer()

            if isBlocked {
                ArkeGlassButton(
                    String(localized: "link_button_check_again", defaultValue: "Check Again"),
                    isLoading: isLinking,
                    action: onLink
                )
                .disabled(isLinking)
            } else {
                if importSettled && !seedPresent {
                    seedMissingSection
                }
                ArkeGlassButton(
                    String(localized: "link_button", defaultValue: "Link This Device"),
                    isLoading: isLinking,
                    action: onLink
                )
                .disabled(!importSettled || isLinking)
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await settle()
        }
        #if os(iOS)
        .sheet(isPresented: $showSeedEntry) {
            SeedEntrySheet_iOS(
                networkConfig: walletManager.networkConfig ?? .mainnet,
                onCancel: { showSeedEntry = false },
                onSeedSaved: {
                    showSeedEntry = false
                    seedPresent = securityService.hasMnemonic()
                }
            )
            .environment(walletManager)
        }
        #endif
    }

    // MARK: - Copy

    /// The variant with nothing to link to yet: no import wait, no link
    /// action. The mismatch has its own screen (`LaunchCheckView`).
    private var isBlocked: Bool {
        reason == .waitingForICloud
    }

    private var title: String {
        switch reason {
        case .waitingForICloud:
            return String(localized: "link_title_waiting", defaultValue: "Waiting for iCloud")
        case .walletMismatch:
            // Routed to LaunchCheckView by the main views; never shown here
            return String(localized: "launch_check_title_undetermined", defaultValue: "iCloud isn't answering")
        case .removedHere, .removedByAnotherDevice:
            return String(localized: "link_title_again", defaultValue: "Link this device again")
        case .newDevice:
            return String(localized: "link_title", defaultValue: "Link this device to your wallet")
        }
    }

    private var message: String {
        switch reason {
        case .waitingForICloud:
            return String(localized: "link_message_waiting",
                          defaultValue: "This device held a wallet before. iCloud hasn't answered yet; the wallet appears as soon as it does.")
        case .walletMismatch:
            return ""
        case .removedHere(let leftAt):
            return String(format: String(localized: "link_message_removed_here %@",
                                         defaultValue: "You removed this wallet from this device on %@. Link it again to keep viewing it."),
                          leftAt.formatted(date: .abbreviated, time: .omitted))
        case .removedByAnotherDevice:
            return String(localized: "link_message_removed_elsewhere",
                          defaultValue: "This device was removed from the wallet's device list on another device. Link it again to keep viewing the wallet.")
        case .newDevice:
            if importSettled && ownRowWasPrimary {
                return String(localized: "link_message_was_primary",
                              defaultValue: "This device was the primary device for this wallet. Link it to continue as before.")
            }
            if let primaryDeviceName {
                return String(format: String(localized: "link_message_new_device %@",
                                             defaultValue: "This iCloud account has a wallet. Its primary device is %@. This device will show the wallet; spending stays on the primary device until you move it here."),
                              primaryDeviceName)
            }
            return String(localized: "link_message_new_device",
                          defaultValue: "This iCloud account has a wallet. This device will show it; spending stays on the primary device until you move it here.")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !importSettled {
            HStack(spacing: 8) {
                ProgressView()
                Text(String(localized: "link_status_syncing", defaultValue: "Syncing with iCloud…"))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if importTimedOut {
            Text(String(localized: "link_status_slow",
                        defaultValue: "iCloud is slow right now. You can continue; details fill in later."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var seedMissingSection: some View {
        VStack(spacing: 12) {
            Text(String(localized: "link_seed_missing",
                        defaultValue: "The wallet key hasn't reached this device through iCloud Keychain yet. You can enter the recovery phrase instead."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #if os(iOS)
            ArkeGlassButton(
                String(localized: "link_button_enter_phrase", defaultValue: "Enter Recovery Phrase"),
                variant: .secondary
            ) {
                showSeedEntry = true
            }
            #endif
        }
    }

    // MARK: - Behaviour

    /// Hosts the first import pass, then reads what it brought: the primary
    /// device's name and this device's own old row.
    private func settle() async {
        seedPresent = securityService.hasMnemonic()
        guard !isBlocked else { return }

        let opened = await walletManager.cloudKitFirstImportGate.waitForFirstImport(timeout: Self.importWait)
        importTimedOut = !opened

        if let hash = deviceService.accountWalletHash(),
           let primary = try? await deviceService.getPrimaryDevice(walletHash: hash) {
            let name = primary.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            primaryDeviceName = name.isEmpty ? nil : name
        }
        // Same wallet the route and the link action ask about: KVS, else the
        // seed in hand (adversarial pass 2026-11-16 on the G1 fix, F3)
        let seedHash = (try? securityService.loadMnemonic()).flatMap { $0 }.map(securityService.hashMnemonic)
        ownRowWasPrimary = await deviceService.ownRowEvidence(fallbackContainer: nil, walletHash: deviceService.accountWalletHash() ?? seedHash) == .primary
        importSettled = true
    }

}

#Preview("New device") {
    LinkWalletView(reason: .newDevice, isLinking: false) {}
        .environment(WalletManager())
}

#Preview("Removed here") {
    LinkWalletView(reason: .removedHere(leftAt: Date(timeIntervalSince1970: 1_761_000_000)), isLinking: false) {}
        .environment(WalletManager())
}
