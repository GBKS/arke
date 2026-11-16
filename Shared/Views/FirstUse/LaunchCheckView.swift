//
//  LaunchCheckView.swift
//  Arké
//
//  Created by Assistant on 11/16/26.
//

import SwiftUI
import ArkeUI

/// The launch-check screen (Device_Linking.md §4.5, §15): this install's
/// link record names a wallet the iCloud account no longer has, or a
/// different one. Nothing is adopted, registered or opened, and nothing
/// happens without a tap. Three cases share the view; the fourth is the
/// honest fallback when iCloud would not say whether an account is present.
///
/// Exits: check again (sign back in first, where that is the remedy),
/// restore with the recovery phrase (deleted elsewhere, iOS), and remove the
/// wallet from this device, which is the ordinary local-only deletion behind
/// the same slider sheet the settings flow uses. Local files are never paired
/// with another account's data: linking this account's wallet is possible
/// only after removing the old one.
struct LaunchCheckView: View {
    let launchCase: LaunchCheckCase
    /// True while the owner re-runs detection
    let isChecking: Bool
    let onCheckAgain: () -> Void
    /// Deleted-elsewhere only: the owner opens onboarding at the phrase step
    /// with the local files untouched. Nil hides the exit (desktop).
    var onRestore: (() -> Void)? = nil
    /// The local-only deletion finished; the owner routes again
    let onRemoved: () -> Void

    @Environment(WalletManager.self) private var walletManager
    @Environment(\.walletDataCleanupService) private var cleanupService
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ArkeCircularIcon(icon: Image(systemName: iconName))
                .padding(.bottom, 8)

            Text(title)
                .font(.system(.title, design: .serif))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.Arke.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                if launchCase == .deletedElsewhere, let onRestore {
                    ArkeGlassButton(
                        String(localized: "launch_check_button_restore", defaultValue: "Restore with Recovery Phrase"),
                        action: onRestore
                    )
                    .disabled(isBusy)
                    ArkeGlassButton(
                        String(localized: "link_button_check_again", defaultValue: "Check Again"),
                        variant: .secondary,
                        isLoading: isChecking,
                        action: onCheckAgain
                    )
                    .disabled(isBusy)
                } else {
                    ArkeGlassButton(
                        String(localized: "link_button_check_again", defaultValue: "Check Again"),
                        isLoading: isChecking,
                        action: onCheckAgain
                    )
                    .disabled(isBusy)
                }

                Button {
                    errorMessage = nil
                    showingRemoveConfirmation = true
                } label: {
                    Text(String(localized: "launch_check_button_remove", defaultValue: "Remove from This Device…"))
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .foregroundColor(.Arke.red)
                .disabled(isBusy)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: scenePhase) { _, phase in
            // The remedy for two of the cases happens in the Settings app;
            // look again when the user comes back
            if phase == .active, !isBusy {
                onCheckAgain()
            }
        }
        .sheet(isPresented: $showingRemoveConfirmation) {
            DeletePermanentlyConfirmationView(
                deletionStrategy: .localOnly,
                onConfirm: { await remove() },
                onBack: { showingRemoveConfirmation = false },
                warningOverride: removeWarning
            )
        }
    }

    private var isBusy: Bool { isChecking || isRemoving }

    // MARK: - Copy

    private var iconName: String {
        switch launchCase {
        case .deletedElsewhere: return "trash"
        case .signedOut, .undetermined: return "icloud.slash"
        case .differentAccount: return "person.crop.circle.badge.exclamationmark"
        }
    }

    private var title: String {
        switch launchCase {
        case .deletedElsewhere:
            return String(localized: "launch_check_title_deleted", defaultValue: "This wallet was deleted from your iCloud account")
        case .signedOut:
            return String(localized: "launch_check_title_signed_out", defaultValue: "You are signed out of iCloud")
        case .differentAccount:
            return String(localized: "launch_check_title_different_account", defaultValue: "This device is signed in to a different iCloud account")
        case .undetermined:
            return String(localized: "launch_check_title_undetermined", defaultValue: "iCloud isn't answering")
        }
    }

    private var message: String {
        switch launchCase {
        case .deletedElsewhere:
            return String(localized: "launch_check_message_deleted",
                          defaultValue: "It was deleted on another device. Its data is still on this device. Restore it with your recovery phrase to keep using it here, or remove it from this device.")
        case .signedOut:
            return String(localized: "launch_check_message_signed_out",
                          defaultValue: "Spending and sync need the wallet's iCloud account. Sign back in in the Settings app, then check again. Or remove the wallet from this device.")
        case .differentAccount:
            return String(localized: "launch_check_message_different_account",
                          defaultValue: "The wallet on this device belongs to another iCloud account. Sign back in to that account and check again, or remove the wallet from this device before linking this account's wallet.")
        case .undetermined:
            return String(localized: "launch_check_message_undetermined",
                          defaultValue: "The wallet on this device is no longer the one on this iCloud account, and iCloud hasn't said whether you are signed in. Check again in a moment, or remove the wallet from this device.")
        }
    }

    /// The slider sheet's local-only copy says the other devices keep the
    /// wallet; after a wipe elsewhere that is false, so each case states
    /// what is true for it
    private var removeWarning: String {
        switch launchCase {
        case .deletedElsewhere:
            return String(localized: "launch_check_remove_warning_deleted",
                          defaultValue: "All wallet data will be permanently deleted from this device. The wallet was already deleted from iCloud, so only your recovery phrase can restore it later.")
        case .signedOut, .differentAccount, .undetermined:
            return String(localized: "launch_check_remove_warning_kept",
                          defaultValue: "All wallet data will be permanently deleted from this device. The wallet stays on its iCloud account and on any other device linked to it.")
        }
    }

    // MARK: - Remove

    /// The ordinary local-only deletion, run with no wallet open: the seed
    /// stays wherever it is, the link record is cleared, the breadcrumb
    /// remembers the record's wallet (not this account's), and the local
    /// files go. Mirrors `DeleteWalletSettingView.deleteWallet`'s two phases.
    private func remove() async {
        isRemoving = true
        walletManager.setWalletDeletionInProgress(true)
        defer {
            walletManager.setWalletDeletionInProgress(false)
            isRemoving = false
        }
        // A detection that landed here during an in-flight open may have
        // left a bark handle open (adversarial pass 2026-11-16, F3). The
        // teardown's own shutdown backs up by default, and that backup would
        // go to whichever account's Drive is current. Close without one first.
        if (walletManager.wallet as? BarkWalletFFI)?.wallet != nil || walletManager.isInitialized {
            try? await walletManager.closeWalletForMigration(backingUp: false)
        }
        do {
            _ = try await cleanupService.deleteWalletData(
                strategy: .localOnly,
                overrideConfirmed: false,
                isLoadingWalletData: { walletManager.isLoadingWalletData }
            )
        } catch {
            showingRemoveConfirmation = false
            errorMessage = error.localizedDescription
            return
        }
        do {
            _ = try await walletManager.deleteWallet(scope: .localOnly)
        } catch {
            // Account-side part is done; the leftover directory is not wallet
            // evidence and the next create or import removes it first
            SecurityService.clearLocalWalletEvidence()
            SecurityService.recordStaleWalletDirectory()
        }
        showingRemoveConfirmation = false
        onRemoved()
    }
}

#Preview("Deleted elsewhere") {
    LaunchCheckView(launchCase: .deletedElsewhere, isChecking: false, onCheckAgain: {}, onRestore: {}, onRemoved: {})
        .environment(WalletManager())
}

#Preview("Signed out") {
    LaunchCheckView(launchCase: .signedOut, isChecking: false, onCheckAgain: {}, onRemoved: {})
        .environment(WalletManager())
}
